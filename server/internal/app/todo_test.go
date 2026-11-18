package app_test

import (
	"net/http"
	"testing"
	"time"

	"oikoboard/server/internal/core"
)

func TestTodoComments(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	_, lists := a.view("todo.lists", nil)
	list := lists["todo_lists"][0]["id"]
	var item struct{ ID string }
	if st := a.do("POST", "/todo/items", map[string]any{"list_id": list, "title": "Paszport"}, &item); st != http.StatusCreated {
		t.Fatalf("add task: %d", st)
	}

	w := a.ws()
	snap := w.sub("c", "todo.comments", map[string]any{"item_id": item.ID})
	if len(snap.Data["todo_comments"]) != 0 {
		t.Fatalf("snapshot: %+v", snap.Data)
	}
	if st := a.do("POST", "/todo/comments", map[string]any{"item_id": item.ID, "body": "  "}, nil); st != http.StatusBadRequest {
		t.Fatalf("empty body: %d", st)
	}
	var cm struct {
		ID       string
		Body     string
		AuthorID string `json:"author_id"`
	}
	if st := a.do("POST", "/todo/comments", map[string]any{"item_id": item.ID, "body": " Wniosek złożony "}, &cm); st != http.StatusCreated || cm.Body != "Wniosek złożony" || cm.AuthorID == "" {
		t.Fatalf("add comment: %d %+v", st, cm)
	}
	if m := w.next(); m.Entity != "todo_comments" || m.ID != cm.ID {
		t.Fatalf("change: %+v", m)
	}

	// Other households can't see or delete it.
	b := e.newFamily("Nowakowie")
	if _, d := b.view("todo.comments", map[string]any{"item_id": item.ID}); len(d["todo_comments"]) != 0 {
		t.Fatalf("other household sees: %+v", d)
	}
	if st := b.do("DELETE", "/todo/comments/"+cm.ID, nil, nil); st != http.StatusNotFound {
		t.Fatalf("other household delete: %d", st)
	}

	if st := a.do("DELETE", "/todo/comments/"+cm.ID, nil, nil); st != http.StatusNoContent {
		t.Fatalf("delete: %d", st)
	}
	if m := w.next(); m.Entity != "todo_comments" || m.ID != cm.ID {
		t.Fatalf("delete change: %+v", m)
	}

	// Deleting the task deletes its thread.
	a.do("POST", "/todo/comments", map[string]any{"item_id": item.ID, "body": "x"}, nil)
	a.do("DELETE", "/todo/items/"+item.ID, nil, nil)
	if _, d := a.view("todo.comments", map[string]any{"item_id": item.ID}); len(d["todo_comments"]) != 0 {
		t.Fatalf("after task delete: %+v", d)
	}
}

func TestTodoListDue(t *testing.T) {
	e := setup(t, mockCalendars)
	a := e.newFamily("Kowalscy")
	warsaw, _ := time.LoadLocation("Europe/Warsaw")
	day := func(n int) string { return core.DateOf(time.Now().In(warsaw)).AddDays(n).String() }

	var list struct{ ID, Due string }
	if st := a.do("POST", "/todo/lists", map[string]any{"name": "Wyjazd", "due": day(4)}, &list); st != http.StatusCreated || list.Due != day(4) {
		t.Fatalf("add list: %d %+v", st, list)
	}
	// Sample tasks are due yesterday, in 2 and in 14 days; plus the empty list.
	if d := a.todoDays(4)[day(4)]; d.Title != "Lista: Wyjazd" || d.Description != "• Wyjazd (lista)" {
		t.Fatalf("list day: %+v", d)
	}

	// A list whose tasks are all done drops out.
	var it struct{ ID string }
	a.do("POST", "/todo/items", map[string]any{"list_id": list.ID, "title": "Namiot"}, &it)
	a.do("PATCH", "/todo/items/"+it.ID, map[string]any{"done": true}, nil)
	if days := a.todoDays(3); days[day(4)].ID != "" {
		t.Fatalf("done list still shown: %+v", days)
	}

	// Clearing the due date.
	a.do("PATCH", "/todo/items/"+it.ID, map[string]any{"done": false}, nil)
	if days := a.todoDays(4); days[day(4)].ID == "" {
		t.Fatalf("reopened list not shown: %+v", days)
	}
	var cleared struct{ Due *string }
	if st := a.do("PATCH", "/todo/lists/"+list.ID, map[string]any{"due": nil}, &cleared); st != http.StatusOK || cleared.Due != nil {
		t.Fatalf("clear due: %d %+v", st, cleared)
	}
	if days := a.todoDays(3); days[day(4)].ID != "" {
		t.Fatalf("list without due still shown: %+v", days)
	}
}
