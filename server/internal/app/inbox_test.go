package app_test

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"oikoboard/server/internal/seed"
)

// login signs in as another member of a household made by newFamily.
func (e *env) login(household, member string) *client {
	e.t.Helper()
	email := fmt.Sprintf("%s-%d@example.test", member, time.Now().UnixNano())
	if err := seed.LinkEmail(context.Background(), e.db, household, member, email); err != nil {
		e.t.Fatal(err)
	}
	return e.devLogin(email)
}

func (e *env) memberID(household, member string) string {
	e.t.Helper()
	var id string
	err := e.db.Raw(`SELECT m.id FROM members m JOIN households h ON h.id = m.household_id
	                 WHERE h.name = ? AND m.name = ?`, household, member).Scan(&id).Error
	if err != nil || id == "" {
		e.t.Fatalf("member %s/%s: %v", household, member, err)
	}
	return id
}

func mention(name, id string) string { return fmt.Sprintf("[@%s](member:%s)", name, id) }

func (c *client) inbox(member string) []map[string]any {
	_, d := c.view("todo.inbox", map[string]any{"member_id": member})
	return d["todo_inbox"]
}

func TestTodoInbox(t *testing.T) {
	e := setup(t)
	tata := e.newFamily("Kowalscy")
	mama := e.login("Kowalscy", "Mama")
	ola := e.login("Kowalscy", "Ola")
	tataID := e.memberID("Kowalscy", "Tata")
	mamaID := e.memberID("Kowalscy", "Mama")
	olaID := e.memberID("Kowalscy", "Ola")
	kubaID := e.memberID("Kowalscy", "Kuba")

	_, lists := tata.view("todo.lists", nil)
	list := lists["todo_lists"][0]["id"]

	// Assigning a new task to someone else lands in their inbox; to yourself doesn't.
	var item struct{ ID string }
	tata.do("POST", "/todo/items", map[string]any{"list_id": list, "title": "Paszport", "assignee_id": mamaID}, &item)
	var own struct{ ID string }
	tata.do("POST", "/todo/items", map[string]any{"list_id": list, "title": "Own", "assignee_id": tataID}, &own)
	if in := mama.inbox(mamaID); len(in) != 1 || in[0]["kind"] != "assigned" || in[0]["title"] != "Paszport" || in[0]["actor_id"] != tataID {
		t.Fatalf("mama after assign: %+v", in)
	}
	if in := tata.inbox(tataID); len(in) != 0 {
		t.Fatalf("self-assignment notified: %+v", in)
	}

	w := ola.ws()
	w.sub("i", "todo.inbox", map[string]any{"member_id": olaID})

	// A comment mentioning Ola: a mention for her, a reply for Mama (the assignee).
	body := "Ask " + mention("Ola", olaID) + " please"
	var cm struct{ ID string }
	tata.do("POST", "/todo/comments", map[string]any{"item_id": item.ID, "body": body}, &cm)
	if m := w.next(); m.Entity != "todo_inbox" {
		t.Fatalf("ola change: %+v", m)
	}
	in := ola.inbox(olaID)
	if len(in) != 1 || in[0]["kind"] != "mention" || in[0]["comment_id"] != cm.ID || in[0]["excerpt"] != body {
		t.Fatalf("ola inbox: %+v", in)
	}
	if in := mama.inbox(mamaID); len(in) != 2 || in[0]["kind"] != "reply" {
		t.Fatalf("mama inbox: %+v", in)
	}

	// Ola answers: Tata (commented) and Mama (assignee) get replies, Ola nothing.
	ola.do("POST", "/todo/comments", map[string]any{"item_id": item.ID, "body": "ok"}, nil)
	if in := tata.inbox(tataID); len(in) != 1 || in[0]["kind"] != "reply" || in[0]["excerpt"] != "ok" {
		t.Fatalf("tata inbox: %+v", in)
	}
	if in := ola.inbox(olaID); len(in) != 1 {
		t.Fatalf("ola notified of her own comment: %+v", in)
	}
	w.expectNone()

	// A mention in a task description notifies once, not on every save.
	desc := "Kuba: " + mention("Kuba", kubaID)
	tata.do("PATCH", "/todo/items/"+own.ID, map[string]any{"description": desc}, nil)
	tata.do("PATCH", "/todo/items/"+own.ID, map[string]any{"description": desc + " too"}, nil)
	if kuba := tata.inbox(kubaID); len(kuba) != 1 || kuba[0]["kind"] != "mention" || kuba[0]["comment_id"] != nil {
		t.Fatalf("kuba inbox: %+v", kuba)
	}
	// A mention of someone outside the household is ignored.
	b := e.newFamily("Nowakowie")
	if st := tata.do("PATCH", "/todo/items/"+own.ID, map[string]any{"description": mention("X", e.memberID("Nowakowie", "Ola"))}, nil); st != http.StatusOK {
		t.Fatalf("foreign mention: %d", st)
	}

	// Only the recipient marks an entry read.
	id := in[0]["id"].(string)
	now := time.Now().UTC().Format(time.RFC3339)
	if st := tata.do("PATCH", "/todo/inbox/"+id, map[string]any{"read_at": now}, nil); st != http.StatusForbidden {
		t.Fatalf("other member marks read: %d", st)
	}
	if st := b.do("PATCH", "/todo/inbox/"+id, map[string]any{"read_at": now}, nil); st != http.StatusNotFound {
		t.Fatalf("other household marks read: %d", st)
	}
	var read struct {
		ReadAt *string `json:"read_at"`
	}
	if st := ola.do("PATCH", "/todo/inbox/"+id, map[string]any{"read_at": now}, &read); st != http.StatusOK || read.ReadAt == nil {
		t.Fatalf("mark read: %d %+v", st, read)
	}
	if st := ola.do("PATCH", "/todo/inbox/"+id, map[string]any{"kind": "reply"}, nil); st != http.StatusBadRequest {
		t.Fatalf("change kind: %d", st)
	}

	// Deleting the comment takes its entries with it.
	tata.do("DELETE", "/todo/comments/"+cm.ID, nil, nil)
	if in := ola.inbox(olaID); len(in) != 0 {
		t.Fatalf("after comment delete: %+v", in)
	}
}
