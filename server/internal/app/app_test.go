package app_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"oikoboard/server/internal/app"
	"oikoboard/server/internal/core"
	"oikoboard/server/internal/seed"
)

// Testy wymagają Postgresa (docker compose up -d postgres). Każdy test
// tworzy własną, tymczasową bazę.
func setup(t *testing.T, opts ...func(*core.AuthConfig)) *env {
	t.Helper()
	admin := os.Getenv("OIKO_TEST_DATABASE_URL")
	if admin == "" {
		admin = "postgres://oiko:oiko@localhost:5433/oiko?sslmode=disable"
	}
	adb, err := core.OpenDB(admin)
	if err != nil {
		t.Skipf("brak Postgresa: %v", err)
	}
	if err := adb.Exec("SELECT 1").Error; err != nil {
		t.Skipf("brak Postgresa: %v", err)
	}
	name := fmt.Sprintf("oiko_test_%d", time.Now().UnixNano())
	if err := adb.Exec("CREATE DATABASE " + name).Error; err != nil {
		t.Fatal(err)
	}
	u, _ := url.Parse(admin)
	u.Path = "/" + name
	dsn := u.String()

	db, err := core.OpenDB(dsn)
	if err != nil {
		t.Fatal(err)
	}
	if err := core.Migrate(db); err != nil {
		t.Fatal(err)
	}
	gin.SetMode(gin.TestMode)
	idp := newFakeIDP(t)
	cfg := core.AuthConfig{
		DevLogin:   true,
		ReturnURLs: []string{"http://localhost:*", "oikoboard://auth"},
		Google: &core.GoogleConfig{
			ClientID: idp.clientID, ClientSecret: "sekret", PublicURL: "http://api.test", Issuer: idp.srv.URL,
		},
	}
	for _, o := range opts {
		o(&cfg)
	}
	a := app.New(db, cfg)
	a.Calendar.TodoDelay = 20 * time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	go a.Hub.Listen(ctx, dsn)
	srv := httptest.NewServer(a.Router)

	t.Cleanup(func() {
		srv.Close()
		cancel()
		if s, err := db.DB(); err == nil {
			s.Close()
		}
		adb.Exec("DROP DATABASE " + name + " WITH (FORCE)")
		if s, err := adb.DB(); err == nil {
			s.Close()
		}
	})
	time.Sleep(200 * time.Millisecond) // listener zdąży zrobić LISTEN
	return &env{t: t, db: db, srv: srv, idp: idp, app: a}
}

type env struct {
	t   *testing.T
	db  *gorm.DB
	srv *httptest.Server
	idp *fakeIDP
	app *app.App
}

// newFamily tworzy przykładową rodzinę i loguje się jako „Tata”
// (e-mail przypięty do Taty, logowanie dev).
func (e *env) newFamily(name string) *client {
	e.t.Helper()
	if err := seed.Family(context.Background(), e.db, name); err != nil {
		e.t.Fatal(err)
	}
	email := fmt.Sprintf("tata-%d@example.test", time.Now().UnixNano())
	if err := seed.LinkEmail(context.Background(), e.db, name, "Tata", email); err != nil {
		e.t.Fatal(err)
	}
	return e.devLogin(email)
}

func (e *env) devLogin(email string) *client {
	e.t.Helper()
	c := &client{e: e}
	var res struct{ Token string }
	if st := c.do("POST", "/auth/dev/login", map[string]any{"email": email}, &res); st != http.StatusOK {
		e.t.Fatalf("dev login: %d", st)
	}
	c.token = res.Token
	return c
}

type client struct {
	e     *env
	token string
}

func (c *client) do(method, path string, body any, out any) int {
	c.e.t.Helper()
	var buf bytes.Buffer
	if body != nil {
		json.NewEncoder(&buf).Encode(body)
	}
	req, _ := http.NewRequest(method, c.e.srv.URL+"/api/v1"+path, &buf)
	req.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		c.e.t.Fatal(err)
	}
	defer res.Body.Close()
	if out != nil {
		json.NewDecoder(res.Body).Decode(out)
	}
	return res.StatusCode
}

func (c *client) view(name string, params any) (seq int64, data map[string][]map[string]any) {
	p, _ := json.Marshal(params)
	var res struct {
		Seq  int64
		Data map[string][]map[string]any
	}
	c.do("GET", "/views/"+name+"?params="+url.QueryEscape(string(p)), nil, &res)
	return res.Seq, res.Data
}

type msg struct {
	T      string                      `json:"t"`
	Sub    string                      `json:"sub"`
	Seq    int64                       `json:"seq"`
	Entity string                      `json:"entity"`
	ID     string                      `json:"id"`
	Row    map[string]any              `json:"row"`
	Data   map[string][]map[string]any `json:"data"`
	Code   string                      `json:"code"`
}

type wsClient struct {
	t    *testing.T
	conn *websocket.Conn
	msgs chan msg
}

func (c *client) ws() *wsClient {
	c.e.t.Helper()
	u := "ws" + strings.TrimPrefix(c.e.srv.URL, "http") + "/api/v1/ws"
	conn, _, err := websocket.Dial(context.Background(), u, nil)
	if err != nil {
		c.e.t.Fatal(err)
	}
	conn.SetReadLimit(10 << 20)
	w := &wsClient{t: c.e.t, conn: conn, msgs: make(chan msg, 10000)}
	go func() {
		for {
			var m msg
			if err := wsjson.Read(context.Background(), conn, &m); err != nil {
				close(w.msgs)
				return
			}
			w.msgs <- m
		}
	}()
	c.e.t.Cleanup(func() { conn.CloseNow() })
	w.send(map[string]any{"t": "auth", "token": c.token})
	if m := w.next(); m.T != "ready" {
		c.e.t.Fatalf("oczekiwano ready, jest %+v", m)
	}
	return w
}

func (w *wsClient) send(v any) {
	if err := wsjson.Write(context.Background(), w.conn, v); err != nil {
		w.t.Fatal(err)
	}
}

func (w *wsClient) sub(id, view string, params any) msg {
	w.t.Helper()
	w.send(map[string]any{"t": "sub", "id": id, "view": view, "params": params})
	m := w.next()
	if m.T != "snapshot" || m.Sub != id {
		w.t.Fatalf("oczekiwano snapshot %s, jest %+v", id, m)
	}
	return m
}

func (w *wsClient) next() msg {
	w.t.Helper()
	select {
	case m, ok := <-w.msgs:
		if !ok {
			w.t.Fatal("połączenie zamknięte")
		}
		return m
	case <-time.After(5 * time.Second):
		w.t.Fatal("timeout: brak wiadomości")
	}
	return msg{}
}

// expectNone: przez chwilę nie powinno przyjść nic.
func (w *wsClient) expectNone() {
	w.t.Helper()
	select {
	case m := <-w.msgs:
		w.t.Fatalf("nieoczekiwana wiadomość: %+v", m)
	case <-time.After(300 * time.Millisecond):
	}
}

func idOf(rows []map[string]any, field, value string) string {
	for _, r := range rows {
		if r[field] == value {
			return r["id"].(string)
		}
	}
	return ""
}

// Każdy widok dostaje tylko zmiany, które go dotyczą; rodziny są odizolowane.
func TestViewsGetOnlyRelevantChanges(t *testing.T) {
	e := setup(t)
	a := e.newFamily("A")
	b := e.newFamily("B")

	_, lists := a.view("todo.lists", nil)
	zakupy := idOf(lists["todo_lists"], "name", "Zakupy")
	dom := idOf(lists["todo_lists"], "name", "Dom")

	now := time.Now()
	rng := map[string]any{"from": now.Add(-24 * time.Hour), "to": now.Add(7 * 24 * time.Hour)}

	e.app.Calendar.ReconcileAllTodos(context.Background()) // due tasks → calendar, before watching changes
	ws := a.ws()
	snap := ws.sub("list", "todo.list", map[string]any{"list_id": zakupy})
	if len(snap.Data["todo_items"]) != 5 {
		t.Fatalf("snapshot zakupów: %d zadań", len(snap.Data["todo_items"]))
	}
	ws.sub("open", "todo.open", nil)
	cal := ws.sub("cal", "calendar.range", rng)

	// 1. Nowe zadanie w Zakupach → list + open, kalendarz nic.
	var item map[string]any
	a.do("POST", "/todo/items", map[string]any{"list_id": zakupy, "title": "Masło"}, &item)
	got := map[string]string{}
	for range 2 {
		m := ws.next()
		got[m.Sub] = m.T
		if m.Row["title"] != "Masło" {
			t.Fatalf("zły wiersz: %+v", m)
		}
	}
	if got["list"] != "upsert" || got["open"] != "upsert" {
		t.Fatalf("oczekiwano upsert na list i open, jest %v", got)
	}
	ws.expectNone()

	// 2. Zadanie w innej liście → tylko open.
	a.do("POST", "/todo/items", map[string]any{"list_id": dom, "title": "Umyć okna"}, nil)
	if m := ws.next(); m.Sub != "open" || m.T != "upsert" {
		t.Fatalf("oczekiwano upsert na open, jest %+v", m)
	}
	ws.expectNone()

	// 3. Zmiana tytułu wydarzenia → tylko kalendarz.
	var evID string
	for _, ev := range cal.Data["calendar_events"] {
		if ev["kind"] == "" && evID == "" {
			evID = ev["id"].(string)
		}
	}
	a.do("PATCH", "/calendar/events/"+evID, map[string]any{"title": "Nowy tytuł"}, nil)
	if m := ws.next(); m.Sub != "cal" || m.T != "upsert" || m.Row["title"] != "Nowy tytuł" {
		t.Fatalf("oczekiwano upsert na cal, jest %+v", m)
	}
	ws.expectNone()

	// 4. Odhaczenie → list: upsert, open: remove (wypada z widoku).
	a.do("PATCH", "/todo/items/"+item["id"].(string), map[string]any{"done": true}, nil)
	got = map[string]string{}
	for range 2 {
		m := ws.next()
		got[m.Sub] = m.T
	}
	if got["list"] != "upsert" || got["open"] != "remove" {
		t.Fatalf("oczekiwano list=upsert open=remove, jest %v", got)
	}

	// 5. Wydarzenie przesunięte poza zakres → remove.
	far := now.Add(60 * 24 * time.Hour)
	a.do("PATCH", "/calendar/events/"+evID, map[string]any{"starts_at": far, "ends_at": far.Add(time.Hour)}, nil)
	if m := ws.next(); m.Sub != "cal" || m.T != "remove" {
		t.Fatalf("oczekiwano remove na cal, jest %+v", m)
	}

	// 6. Usunięcie listy kaskadowo usuwa zadania → remove listy i każdego zadania.
	a.do("DELETE", "/todo/lists/"+zakupy, nil, nil)
	removed := map[string]int{}
	for {
		select {
		case m := <-ws.msgs:
			if m.T != "remove" {
				t.Fatalf("oczekiwano remove, jest %+v", m)
			}
			removed[m.Sub+"/"+m.Entity]++
			continue
		case <-time.After(300 * time.Millisecond):
		}
		break
	}
	// list: lista + 6 zadań; open: 4 niezrobione z Zakupów
	if removed["list/todo_lists"] != 1 || removed["list/todo_items"] != 6 || removed["open/todo_items"] != 4 {
		t.Fatalf("usunięcia: %v", removed)
	}

	// 7. Inna rodzina: zmiany B nie docierają do A, a A nie widzi danych B.
	_, bl := b.view("todo.lists", nil)
	bZakupy := idOf(bl["todo_lists"], "name", "Zakupy")
	b.do("POST", "/todo/items", map[string]any{"list_id": bZakupy, "title": "Tajne"}, nil)
	ws.drain()
	ws.expectNone()
	if code := a.do("POST", "/todo/items", map[string]any{"list_id": bZakupy, "title": "x"}, nil); code != 400 {
		t.Fatalf("A dodało zadanie do listy B: %d", code)
	}
	if code := a.do("DELETE", "/todo/lists/"+bZakupy, nil, nil); code != 404 {
		t.Fatalf("A usunęło listę B: %d", code)
	}
}

func (w *wsClient) drain() {
	for {
		select {
		case <-w.msgs:
		case <-time.After(300 * time.Millisecond):
			return
		}
	}
}

// Snapshot + strumień są spójne nawet przy zapisach w trakcie subskrypcji:
// stan klienta po wszystkim = stan w bazie, bez dziur i duplikatów.
func TestSnapshotUnderConcurrentWrites(t *testing.T) {
	e := setup(t)
	a := e.newFamily("A")
	_, lists := a.view("todo.lists", nil)
	zakupy := idOf(lists["todo_lists"], "name", "Zakupy")

	const writes = 150
	var wg sync.WaitGroup
	start := make(chan struct{})
	for w := range 3 {
		wg.Go(func() {
			<-start
			for i := range writes / 3 {
				a.do("POST", "/todo/items", map[string]any{
					"list_id": zakupy, "title": fmt.Sprintf("w%d-%d", w, i),
				}, nil)
			}
		})
	}

	ws := a.ws()
	close(start)
	time.Sleep(400 * time.Millisecond) // subskrybujemy w trakcie zapisów
	snap := ws.sub("list", "todo.list", map[string]any{"list_id": zakupy})

	state := map[string]bool{}
	for _, r := range snap.Data["todo_items"] {
		state[r["id"].(string)] = true
	}
	initial := len(state)
	lastSeq := snap.Seq
	dup := 0
	wg.Wait()

	_, final := a.view("todo.list", map[string]any{"list_id": zakupy})
	want := len(final["todo_items"])
	deadline := time.After(10 * time.Second)
	for len(state) < want {
		select {
		case m := <-ws.msgs:
			if m.Seq <= lastSeq {
				t.Fatalf("seq nie rośnie: %d po %d", m.Seq, lastSeq)
			}
			lastSeq = m.Seq
			if state[m.ID] {
				dup++
			}
			state[m.ID] = true
		case <-deadline:
			t.Fatalf("brakuje zmian: mam %d, w bazie %d", len(state), want)
		}
	}
	if dup > 0 {
		t.Fatalf("%d zmian dostarczonych podwójnie (już były w snapshocie)", dup)
	}
	for _, r := range final["todo_items"] {
		if !state[r["id"].(string)] {
			t.Fatalf("brak %v", r["title"])
		}
	}
	ws.expectNone()
	t.Logf("snapshot miał %d zadań, %d doszło strumieniem", initial, want-initial)
}

// Reconnect = nowy WS + ponowny sub = świeży snapshot z tym, co się zmieniło.
func TestReconnectGetsFreshSnapshot(t *testing.T) {
	e := setup(t)
	a := e.newFamily("A")
	ws := a.ws()
	ws.sub("open", "todo.open", nil)
	ws.conn.CloseNow()

	_, lists := a.view("todo.lists", nil)
	a.do("POST", "/todo/items", map[string]any{
		"list_id": lists["todo_lists"][0]["id"], "title": "Podczas przerwy",
	}, nil)

	ws2 := a.ws()
	snap := ws2.sub("open", "todo.open", nil)
	if idOf(snap.Data["todo_items"], "title", "Podczas przerwy") == "" {
		t.Fatal("snapshot po reconnect nie zawiera zmiany z przerwy")
	}
}

func TestBadSubscriptions(t *testing.T) {
	e := setup(t)
	a := e.newFamily("A")
	ws := a.ws()
	ws.send(map[string]any{"t": "sub", "id": "x", "view": "nope"})
	if m := ws.next(); m.T != "error" || m.Code != "unknown_view" {
		t.Fatalf("%+v", m)
	}
	ws.send(map[string]any{"t": "sub", "id": "y", "view": "todo.list", "params": map[string]any{}})
	if m := ws.next(); m.T != "error" || m.Code != "bad_params" {
		t.Fatalf("%+v", m)
	}

	// zły token → zamknięcie połączenia
	u := "ws" + strings.TrimPrefix(e.srv.URL, "http") + "/api/v1/ws"
	conn, _, err := websocket.Dial(context.Background(), u, nil)
	if err != nil {
		t.Fatal(err)
	}
	wsjson.Write(context.Background(), conn, map[string]any{"t": "auth", "token": "zły"})
	_, _, err = conn.Read(context.Background())
	if websocket.CloseStatus(err) != 4001 {
		t.Fatalf("oczekiwano zamknięcia 4001, jest %v", err)
	}
}

func TestServeWeb(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "index.html"), []byte("<html>app</html>"), 0o644)
	os.WriteFile(filepath.Join(dir, "main.js"), []byte("js"), 0o644)
	e := setup(t)
	e.app.ServeWeb(dir)
	for path, want := range map[string]string{"/": "<html>app</html>", "/index.html": "<html>app</html>",
		"/some/route": "<html>app</html>", "/main.js": "js"} {
		res := e.get(path, nil)
		body, _ := io.ReadAll(res.Body)
		res.Body.Close()
		if res.StatusCode != http.StatusOK || string(body) != want {
			t.Errorf("%s: %s %q", path, res.Status, body)
		}
	}
	if res := e.get("/api/v1/nope", nil); res.StatusCode != http.StatusNotFound {
		t.Errorf("api 404: %s", res.Status)
	}
}
