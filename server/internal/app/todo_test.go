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

func TestTodoDescriptions(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	type row struct{ ID, Description string }

	var list row
	if st := a.do("POST", "/todo/lists", map[string]any{"name": "Trip", "description": "**Bring** passports"}, &list); st != http.StatusCreated || list.Description != "**Bring** passports" {
		t.Fatalf("add list: %d %+v", st, list)
	}
	if st := a.do("PATCH", "/todo/lists/"+list.ID, map[string]any{"description": nil}, &list); st != http.StatusOK || list.Description != "" {
		t.Fatalf("clear list description: %d %+v", st, list)
	}

	var item row
	if st := a.do("POST", "/todo/items", map[string]any{"list_id": list.ID, "title": "Tickets"}, &item); st != http.StatusCreated || item.Description != "" {
		t.Fatalf("add task: %d %+v", st, item)
	}
	if st := a.do("PATCH", "/todo/items/"+item.ID, map[string]any{"description": "- seat 12A"}, &item); st != http.StatusOK || item.Description != "- seat 12A" {
		t.Fatalf("set task description: %d %+v", st, item)
	}
}

func TestTodoCommentCount(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	list := a.firstList()
	var item struct{ ID string }
	a.do("POST", "/todo/items", map[string]any{"list_id": list, "title": "Paszport"}, &item)
	count := func() float64 {
		t.Helper()
		_, d := a.view("todo.list", map[string]any{"list_id": list})
		for _, r := range d["todo_items"] {
			if r["id"] == item.ID {
				return r["comment_count"].(float64)
			}
		}
		t.Fatal("task not in the list view")
		return -1
	}
	if n := count(); n != 0 {
		t.Fatalf("new task: %v", n)
	}

	w := a.ws()
	w.sub("l", "todo.list", map[string]any{"list_id": list})
	var c1, c2 struct{ ID string }
	a.do("POST", "/todo/comments", map[string]any{"item_id": item.ID, "body": "one"}, &c1)
	a.do("POST", "/todo/comments", map[string]any{"item_id": item.ID, "body": "two"}, &c2)
	sawItem := false
	for i := 0; i < 2; i++ {
		if m := w.next(); m.Entity == "todo_items" && m.ID == item.ID {
			sawItem = true
		}
	}
	if !sawItem {
		t.Error("no todo_items change reached the list subscription")
	}
	if n := count(); n != 2 {
		t.Fatalf("after two comments: %v", n)
	}
	a.do("DELETE", "/todo/comments/"+c1.ID, nil, nil)
	if n := count(); n != 1 {
		t.Fatalf("after delete: %v", n)
	}
	// a client can't set it
	a.do("PATCH", "/todo/items/"+item.ID, map[string]any{"comment_count": 9}, nil)
	if n := count(); n != 1 {
		t.Fatalf("patched count: %v", n)
	}
	if st := a.do("DELETE", "/todo/items/"+item.ID, nil, nil); st != http.StatusNoContent {
		t.Fatalf("delete task with comments: %d", st)
	}
}
