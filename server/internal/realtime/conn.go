package realtime

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

// --- protokół (opis w docs/backend-realtime.md) ---

type clientMsg struct {
	T      string          `json:"t"` // auth | sub | unsub | log
	ID     string          `json:"id,omitempty"`
	Token  string          `json:"token,omitempty"`
	View   string          `json:"view,omitempty"`
	Params json.RawMessage `json:"params,omitempty"`
	Logs   json.RawMessage `json:"logs,omitempty"` // t=log: [{"ts","level","msg","attrs"}]
}

type readyMsg struct {
	T           string    `json:"t"`
	MemberID    uuid.UUID `json:"member_id"`
	HouseholdID uuid.UUID `json:"household_id"`
}

type snapshotMsg struct {
	T    string        `json:"t"`
	Sub  string        `json:"sub"`
	Seq  int64         `json:"seq"`
	Data core.Entities `json:"data"`
}

type changeMsg struct {
	T        string       `json:"t"` // upsert | remove
	Sub      string       `json:"sub"`
	Op       string       `json:"op"` // operacja w bazie: insert | update | delete
	Seq      int64        `json:"seq"`
	Entity   string       `json:"entity"`
	ID       uuid.UUID    `json:"id"`
	Row      core.RawJSON `json:"row"` // przy remove: ostatni znany stan
	Actor    *uuid.UUID   `json:"actor,omitempty"`
	Mutation *uuid.UUID   `json:"mutation,omitempty"`
}

type errorMsg struct {
	T    string `json:"t"`
	Sub  string `json:"sub,omitempty"`
	Code string `json:"code"`
	Msg  string `json:"msg"`
}

const (
	outBuffer = 256
	// pingInterval also drives the app-level {"t":"ping"} heartbeat: browsers
	// hide WebSocket control frames, so clients detect dead connections by
	// the absence of any message for a few intervals.
	pingInterval = 5 * time.Second
	// pongTimeout is generous: a phone on Wi-Fi power saving can answer late.
	pongTimeout = 15 * time.Second
	authTimeout = 10 * time.Second

	closeUnauthorized websocket.StatusCode = 4001
)

// Conn to jedno połączenie WebSocket (jedna otwarta aplikacja).
// Goroutines: handler (czytanie + subskrypcje) i writer (wysyłanie + ping).
type Conn struct {
	hub    *Hub
	ws     *websocket.Conn
	out    chan []byte
	ctx    context.Context
	cancel context.CancelCauseFunc
	actor  core.Actor
	d      *dispatcher
	subs   map[string]*subscription // tylko z goroutine handlera
}

var heartbeat = []byte(`{"t":"ping"}`)

var errSlowClient = errors.New("klient nie nadąża")

// HandleWS: GET /api/v1/ws
func (h *Hub) HandleWS(c *gin.Context) {
	ws, err := websocket.Accept(c.Writer, c.Request, &websocket.AcceptOptions{
		// Dev: Flutter web chodzi na innym porcie. Auth i tak idzie tokenem
		// w pierwszej wiadomości, nie ciasteczkiem, więc CSWSH nam nie grozi.
		InsecureSkipVerify: true,
	})
	if err != nil {
		return
	}
	ctx, cancel := context.WithCancelCause(c.Request.Context())
	conn := &Conn{hub: h, ws: ws, out: make(chan []byte, outBuffer), ctx: ctx, cancel: cancel,
		subs: map[string]*subscription{}}
	defer cancel(nil)

	if err := conn.authenticate(); err != nil {
		ws.Close(closeUnauthorized, "unauthorized")
		return
	}
	conn.d, err = h.acquire(conn.actor.HouseholdID)
	if err != nil {
		ws.Close(websocket.StatusInternalError, "internal")
		return
	}
	defer func() {
		h.presence.remove(conn)
		for _, s := range conn.subs {
			conn.d.unregister(s)
		}
		h.release(conn.d)
	}()

	go conn.writer()
	conn.send(readyMsg{T: "ready", MemberID: conn.actor.MemberID, HouseholdID: conn.actor.HouseholdID})
	h.presence.add(conn)

	for {
		var msg clientMsg
		if err := wsjson.Read(ctx, ws, &msg); err != nil {
			if errors.Is(context.Cause(ctx), errSlowClient) {
				ws.Close(websocket.StatusTryAgainLater, "slow client")
			}
			return
		}
		switch msg.T {
		case "sub":
			conn.subscribe(msg)
		case "unsub":
			conn.unsubscribe(msg.ID)
		case "log":
			conn.handleLogs(msg.Logs)
		default:
			conn.send(errorMsg{T: "error", Code: "bad_message", Msg: "nieznany typ: " + msg.T})
		}
	}
}

func (c *Conn) authenticate() error {
	ctx, cancel := context.WithTimeout(c.ctx, authTimeout)
	defer cancel()
	var msg clientMsg
	if err := wsjson.Read(ctx, c.ws, &msg); err != nil {
		return err
	}
	if msg.T != "auth" {
		return errors.New("pierwsza wiadomość musi być auth")
	}
	actor, err := c.hub.auth.Resolve(ctx, msg.Token)
	if err == nil && !actor.InHousehold() {
		err = errors.New("konto bez rodziny")
	}
	c.actor = actor
	return err
}

func (c *Conn) subscribe(msg clientMsg) {
	if msg.ID == "" {
		c.send(errorMsg{T: "error", Code: "bad_message", Msg: "sub wymaga id"})
		return
	}
	c.unsubscribe(msg.ID) // ponowny sub tym samym id = podmiana
	v, ok := c.hub.views[msg.View]
	if !ok {
		c.send(errorMsg{T: "error", Sub: msg.ID, Code: "unknown_view", Msg: "nieznany widok: " + msg.View})
		return
	}
	if !core.ViewAllowed(c.actor, v.Name()) {
		c.send(errorMsg{T: "error", Sub: msg.ID, Code: "forbidden", Msg: "not available to connected apps"})
		return
	}
	params, err := v.ParseParams(msg.Params)
	if err != nil {
		c.send(errorMsg{T: "error", Sub: msg.ID, Code: "bad_params", Msg: err.Error()})
		return
	}

	s := &subscription{id: msg.ID, conn: c, view: v, params: params}
	// 1. rejestracja (zmiany od teraz trafiają do bufora)
	if !c.d.register(s) {
		return
	}
	// 2. snapshot w jednej transakcji REPEATABLE READ
	seq, data, err := c.hub.Snapshot(c.ctx, c.actor.HouseholdID, v, params)
	if err != nil {
		c.d.unregister(s)
		slog.Error("realtime: snapshot", "view", msg.View, "err", err)
		c.send(errorMsg{T: "error", Sub: msg.ID, Code: "internal", Msg: "błąd snapshotu"})
		return
	}
	// 3. snapshot do kolejki wyjściowej, potem zmiany z bufora (seq > S)
	c.send(snapshotMsg{T: "snapshot", Sub: msg.ID, Seq: seq, Data: data})
	c.d.activate(s, seq)
	c.subs[msg.ID] = s
}

func (c *Conn) unsubscribe(id string) {
	if s, ok := c.subs[id]; ok {
		c.d.unregister(s)
		delete(c.subs, id)
	}
}

// Snapshot zwraca stan widoku i seq, na który jest aktualny. Odczyt seq
// i danych w jednej transakcji REPEATABLE READ = spójny obraz: zawiera
// dokładnie wszystkie zmiany o seq <= zwróconego.
func (h *Hub) Snapshot(ctx context.Context, hh uuid.UUID, v core.View, params any) (int64, core.Entities, error) {
	var seq int64
	var data core.Entities
	err := h.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Raw("SELECT seq FROM households WHERE id = ?", hh).Scan(&seq).Error; err != nil {
			return err
		}
		var err error
		data, err = v.Snapshot(tx, hh, params)
		return err
	}, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	return seq, data, err
}

// send jest bezpieczne z wielu goroutines i nigdy nie blokuje: gdy klient
// nie nadąża, zamykamy połączenie (klient zrobi reconnect i dostanie snapshot).
func (c *Conn) send(msg any) {
	if c.ctx.Err() != nil {
		return
	}
	b, err := json.Marshal(msg)
	if err != nil {
		slog.Error("realtime: marshal", "err", err)
		return
	}
	select {
	case c.out <- b:
	default:
		c.closeSlow()
	}
}

func (c *Conn) closeSlow() { c.cancel(errSlowClient) }

func (c *Conn) writer() {
	go c.pinger()
	t := time.NewTicker(pingInterval)
	defer t.Stop()
	for {
		select {
		case <-c.ctx.Done():
			return
		case b := <-c.out:
			if err := c.ws.Write(c.ctx, websocket.MessageText, b); err != nil {
				c.cancel(err)
				return
			}
		case <-t.C:
			if err := c.ws.Write(c.ctx, websocket.MessageText, heartbeat); err != nil {
				c.cancel(err)
				return
			}
		}
	}
}

// pinger sends WebSocket pings and closes the connection when no pong comes
// back in time. It runs apart from the writer: waiting for a pong must not
// hold back messages or the heartbeat the client watches for.
func (c *Conn) pinger() {
	t := time.NewTicker(pingInterval)
	defer t.Stop()
	for {
		select {
		case <-c.ctx.Done():
			return
		case <-t.C:
			ctx, cancel := context.WithTimeout(c.ctx, pongTimeout)
			err := c.ws.Ping(ctx)
			cancel()
			if err != nil {
				c.cancel(err)
				return
			}
		}
	}
}

// HandleViewSnapshot: GET /api/v1/views/:name?params={...} — ten sam
// snapshot co przez WS, do debugowania curl-em.
func (h *Hub) HandleViewSnapshot(c *gin.Context) {
	v, ok := h.views[c.Param("name")]
	if ok && !core.ViewAllowed(core.ActorOf(c), v.Name()) {
		core.Fail(c, http.StatusForbidden, "forbidden", "not available to connected apps")
		return
	}
	if !ok {
		core.Fail(c, http.StatusNotFound, "unknown_view", "nieznany widok")
		return
	}
	raw := c.Query("params")
	if raw == "" {
		raw = "{}"
	}
	params, err := v.ParseParams(json.RawMessage(raw))
	if err != nil {
		core.Fail(c, http.StatusBadRequest, "bad_params", err.Error())
		return
	}
	seq, data, err := h.Snapshot(c.Request.Context(), core.ActorOf(c).HouseholdID, v, params)
	if err != nil {
		core.FailErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"seq": seq, "data": data})
}
