package app_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"oikoboard/server/internal/core"
)

func withSealer(c *core.AuthConfig) {
	s, err := core.NewSealer(strings.Repeat("ab", 32))
	if err != nil {
		panic(err)
	}
	c.Sealer = s
}

// oauthToken connects an OAuth client for c's member (registration, consent,
// token) and returns the access token and the member id.
func (e *env) oauthToken(c *client) (string, string) {
	e.t.Helper()
	var me struct {
		User     struct{ ID string }
		MemberID string `json:"member_id"`
	}
	c.do("GET", "/me", nil, &me)
	redirect := "https://client.example.test/cb"
	body, _ := json.Marshal(map[string]any{"client_name": "Test", "redirect_uris": []string{redirect}})
	res, err := http.Post(e.srv.URL+"/oauth/register", "application/json", strings.NewReader(string(body)))
	if err != nil {
		e.t.Fatal(err)
	}
	var reg struct {
		ClientID string `json:"client_id"`
	}
	json.NewDecoder(res.Body).Decode(&reg)
	res.Body.Close()
	code := e.authorize(reg.ClientID, redirect, me.User.ID, "allow").Query().Get("code")
	st, tok := e.token(url.Values{"grant_type": {"authorization_code"}, "code": {code}, "redirect_uri": {redirect},
		"client_id": {reg.ClientID}, "code_verifier": {"verifier-0123456789-0123456789-0123456789"}})
	if st != http.StatusOK {
		e.t.Fatalf("token: %d", st)
	}
	return tok.AccessToken, me.MemberID
}

// mcpSession connects an MCP client with a bearer token.
func (e *env) mcpSession(token string) *mcp.ClientSession {
	e.t.Helper()
	client := mcp.NewClient(&mcp.Implementation{Name: "test"}, nil)
	sess, err := client.Connect(context.Background(), &mcp.StreamableClientTransport{
		Endpoint:   e.srv.URL + "/mcp",
		HTTPClient: &http.Client{Transport: headerRT{"Bearer " + token}},
	}, nil)
	if err != nil {
		e.t.Fatal(err)
	}
	e.t.Cleanup(func() { sess.Close() })
	return sess
}

type headerRT struct{ auth string }

func (h headerRT) RoundTrip(r *http.Request) (*http.Response, error) {
	r = r.Clone(r.Context())
	r.Header.Set("Authorization", h.auth)
	return http.DefaultTransport.RoundTrip(r)
}

// tool calls an MCP tool and decodes its structured result; fails on a tool error unless wantErr.
func tool(t *testing.T, s *mcp.ClientSession, name string, args map[string]any, out any) string {
	t.Helper()
	res, err := s.CallTool(context.Background(), &mcp.CallToolParams{Name: name, Arguments: args})
	if err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	text := ""
	if len(res.Content) > 0 {
		if tc, ok := res.Content[0].(*mcp.TextContent); ok {
			text = tc.Text
		}
	}
	if res.IsError {
		if out != nil {
			t.Fatalf("%s: tool error: %s", name, text)
		}
		return text
	}
	if out != nil {
		b, _ := json.Marshal(res.StructuredContent)
		if err := json.Unmarshal(b, out); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
	}
	return ""
}

func TestMCP(t *testing.T) {
	e := setup(t, withSealer, mockCalendars)
	a := e.newFamily("Kowalscy")
	token, me := e.oauthToken(a)
	s := e.mcpSession(token)

	var fam struct {
		Today     string
		Timezone  string
		Members   []struct{ ID, Name string }
		TodoLists []struct{ ID, Name string } `json:"todo_lists"`
		Calendars []struct {
			ID, Name string
			Default  bool
		}
	}
	tool(t, s, "family", nil, &fam)
	if fam.Timezone != "Europe/Warsaw" || len(fam.Members) != 4 || len(fam.TodoLists) == 0 || len(fam.Calendars) == 0 {
		t.Fatalf("family: %+v", fam)
	}

	// Todos: add (by names) → visible in the app's view with the member as actor.
	ws := a.ws()
	ws.sub("open", "todo.open", nil)
	type todo struct {
		ID, List, Title, Assignee, Due string
		Done                           bool
	}
	var added todo
	tool(t, s, "add_todo", map[string]any{"list": "zakupy", "title": "Mleko", "assignee": "Mama", "due": fam.Today}, &added)
	if added.List != "Zakupy" || added.Assignee != "Mama" || added.Due != fam.Today {
		t.Fatalf("add_todo: %+v", added)
	}
	m := ws.next()
	if m.T != "upsert" || m.Row["title"] != "Mleko" {
		t.Fatalf("ws: %+v", m)
	}
	var actor string
	e.db.Raw("SELECT actor_id::text FROM changes WHERE entity_id = ? ORDER BY seq DESC LIMIT 1", added.ID).Scan(&actor)
	if actor != me {
		t.Fatalf("actor %q, member %q", actor, me)
	}
	if msg := tool(t, s, "add_todo", map[string]any{"list": "Nieistniejąca", "title": "x"}, nil); !strings.Contains(msg, "Zakupy") {
		t.Fatalf("unknown list error should list lists: %q", msg)
	}

	var list struct{ Todos []todo }
	tool(t, s, "list_todos", map[string]any{"assignee": "mama"}, &list)
	found := false
	for _, it := range list.Todos {
		found = found || it.ID == added.ID
		if it.Assignee != "Mama" {
			t.Fatalf("filter: %+v", it)
		}
	}
	if !found {
		t.Fatalf("list_todos: %+v", list)
	}
	var upd todo
	tool(t, s, "update_todo", map[string]any{"id": added.ID, "done": true, "assignee": ""}, &upd)
	if !upd.Done || upd.Assignee != "" {
		t.Fatalf("update_todo: %+v", upd)
	}
	type comment struct{ ID, Task, Author, At, Body string }
	var cm comment
	tool(t, s, "add_comment", map[string]any{"id": added.ID, "body": "  Bez laktozy "}, &cm)
	if cm.Task != added.ID || cm.Body != "Bez laktozy" || cm.Author == "" || cm.At == "" {
		t.Fatalf("add_comment: %+v", cm)
	}
	// Comments: a count on the task, the thread via list_comments or with_comments.
	type withComments struct {
		ID           string
		CommentCount int `json:"comment_count"`
		Comments     []comment
	}
	findTask := func(todos []withComments) withComments {
		for _, it := range todos {
			if it.ID == added.ID {
				return it
			}
		}
		t.Fatalf("task %s not listed", added.ID)
		return withComments{}
	}
	var counted struct{ Todos []withComments }
	tool(t, s, "list_todos", map[string]any{"list": "zakupy", "include_done": true}, &counted)
	if it := findTask(counted.Todos); it.CommentCount != 1 || len(it.Comments) != 0 {
		t.Fatalf("list_todos comment_count: %+v", it)
	}
	tool(t, s, "list_todos", map[string]any{"list": "zakupy", "include_done": true, "with_comments": true}, &counted)
	if it := findTask(counted.Todos); it.CommentCount != 1 || len(it.Comments) != 1 ||
		it.Comments[0].Body != "Bez laktozy" || it.Comments[0].Author != cm.Author {
		t.Fatalf("list_todos with_comments: %+v", it)
	}
	var thread struct {
		Task, List, Title string
		Comments          []comment
	}
	tool(t, s, "list_comments", map[string]any{"id": added.ID}, &thread)
	if thread.Title != "Mleko" || thread.List != "Zakupy" || len(thread.Comments) != 1 ||
		thread.Comments[0].ID != cm.ID || thread.Comments[0].Author != cm.Author {
		t.Fatalf("list_comments: %+v", thread)
	}
	if msg := tool(t, s, "list_comments", map[string]any{"id": "00000000-0000-0000-0000-000000000001"}, nil); !strings.Contains(msg, "no such task") {
		t.Fatalf("list_comments unknown task: %q", msg)
	}
	tool(t, s, "delete_todo", map[string]any{"id": added.ID}, &struct{}{})

	// A new list, usable by name right away; tasks can be added already done.
	var newList struct{ ID, Name, Due string }
	tool(t, s, "create_todo_list", map[string]any{"name": "Remont", "due": fam.Today}, &newList)
	if newList.ID == "" || newList.Name != "Remont" || newList.Due != fam.Today {
		t.Fatalf("create_todo_list: %+v", newList)
	}
	if msg := tool(t, s, "create_todo_list", map[string]any{"name": "remont"}, nil); !strings.Contains(msg, "exists") {
		t.Fatalf("duplicate list: %q", msg)
	}
	var timed todo
	tool(t, s, "add_todo", map[string]any{"list": "remont", "title": "Fachowiec", "due": fam.Today + "T09:30"}, &timed)
	if timed.Due != fam.Today+" 09:30" {
		t.Fatalf("add_todo with a time: %+v", timed)
	}
	tool(t, s, "update_todo", map[string]any{"id": timed.ID, "due": fam.Today}, &timed)
	if timed.Due != fam.Today {
		t.Fatalf("update_todo without a time: %+v", timed)
	}
	var doneTodo todo
	tool(t, s, "add_todo", map[string]any{"list": "remont", "title": "Farba", "done": true}, &doneTodo)
	if doneTodo.List != "Remont" || !doneTodo.Done {
		t.Fatalf("add_todo done: %+v", doneTodo)
	}
	if msg := tool(t, s, "delete_todo", map[string]any{"id": added.ID}, nil); msg == "" {
		t.Fatal("deleting twice should fail")
	}

	// Calendar: create (local time), agenda, move, delete.
	day := time.Now().AddDate(0, 0, 3).Format("2006-01-02")
	type ev struct {
		ID, Title, Start, End, Calendar string
		Members                         []string
		AllDay                          bool `json:"all_day"`
		Recurring                       bool
	}
	var created ev
	tool(t, s, "create_event", map[string]any{"title": "Dentysta", "start": day + "T16:30", "members": []string{"Kuba"}}, &created)
	if created.Start != day+" 16:30" || created.End != day+" 17:30" || len(created.Members) != 1 || created.Members[0] != "Kuba" {
		t.Fatalf("create_event: %+v", created)
	}
	var trip ev
	tool(t, s, "create_event", map[string]any{"title": "Wyjazd", "start": day, "end": day}, &trip)
	if !trip.AllDay || trip.Start != day || trip.End != day {
		t.Fatalf("all-day: %+v", trip)
	}
	var weekly ev
	tool(t, s, "create_event", map[string]any{"title": "Joga", "start": day + "T07:00",
		"recurrence": []string{"FREQ=WEEKLY;COUNT=3"}}, &weekly)
	if !weekly.Recurring || weekly.Start != day+" 07:00" {
		t.Fatalf("recurring create_event: %+v", weekly)
	}
	var ag struct{ Events []ev }
	tool(t, s, "agenda", map[string]any{"from": day, "days": 21}, &ag)
	n := 0
	for _, x := range ag.Events {
		if x.Title == "Joga" {
			n++
		}
	}
	if n != 3 {
		t.Fatalf("recurring occurrences: %d", n)
	}
	if msg := tool(t, s, "create_event", map[string]any{"title": "x", "start": day,
		"recurrence": []string{"BOGUS:1"}}, nil); msg == "" {
		t.Fatal("bad recurrence should fail")
	}
	tool(t, s, "agenda", map[string]any{"from": day, "member": "Kuba"}, &ag)
	inAgenda := false
	for _, x := range ag.Events {
		inAgenda = inAgenda || x.ID == created.ID
		if !slices.Contains(x.Members, "Kuba") {
			t.Fatalf("agenda member filter: %+v", x)
		}
	}
	if !inAgenda {
		t.Fatalf("agenda: %+v", ag)
	}
	var moved ev
	tool(t, s, "update_event", map[string]any{"id": created.ID, "start": day + "T18:00", "end": day + "T19:00"}, &moved)
	if moved.Start != day+" 18:00" {
		t.Fatalf("update_event: %+v", moved)
	}
	tool(t, s, "delete_event", map[string]any{"id": created.ID}, &struct{}{})
	tool(t, s, "agenda", map[string]any{"from": day}, &ag)
	for _, x := range ag.Events {
		if x.ID == created.ID {
			t.Fatal("event not deleted")
		}
	}
}

func TestToolTokenScope(t *testing.T) {
	e := setup(t, withSealer, mockCalendars)
	a := e.newFamily("Kowalscy")
	token, _ := e.oauthToken(a)
	tc := &client{e: e, token: token}
	if st := tc.do("GET", "/views/todo.lists", nil, nil); st != http.StatusOK {
		t.Fatalf("view: %d", st)
	}
	for _, c := range []struct{ method, path string }{
		{"POST", "/invites"}, {"GET", "/calendar/connections"}, {"GET", "/me"}, {"GET", "/oauth/grants"},
	} {
		if st := tc.do(c.method, c.path, map[string]any{}, nil); st != http.StatusForbidden && st != http.StatusUnauthorized {
			t.Fatalf("%s %s: %d", c.method, c.path, st)
		}
	}
}
