package app_test

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"

	"oikoboard/server/internal/core"
	"oikoboard/server/internal/modules/todo"
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

func TestCleanupDone(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	_, lists := a.view("todo.lists", nil)
	list := lists["todo_lists"][0]["id"]
	mk := func(title string, extra map[string]any) string {
		body := map[string]any{"list_id": list, "title": title}
		for k, v := range extra {
			body[k] = v
		}
		var it struct {
			ID          string
			KeepForever bool `json:"keep_forever"`
		}
		if st := a.do("POST", "/todo/items", body, &it); st != http.StatusCreated {
			t.Fatalf("add %s: %d", title, st)
		}
		return it.ID
	}
	done := func(id string) {
		if st := a.do("PATCH", "/todo/items/"+id, map[string]any{"done": true}, nil); st != http.StatusOK {
			t.Fatalf("done: %d", st)
		}
	}
	oldDone := mk("old done", nil)
	kept := mk("old kept", map[string]any{"keep_forever": true})
	recent := mk("recent done", nil)
	openOld := mk("old open", nil)
	for _, id := range []string{oldDone, kept, recent} {
		done(id)
	}
	// done_at NULL on a done task: nothing to measure from.
	noDoneAt := mk("done without date", nil)
	done(noDoneAt)
	e.db.Exec("UPDATE todo_items SET done_at = NULL WHERE id = ?", noDoneAt)
	e.db.Exec("UPDATE todo_items SET done_at = now() - interval '40 days' WHERE id IN (?, ?)", oldDone, kept)
	e.db.Exec("UPDATE todo_items SET created_at = now() - interval '90 days' WHERE id = ?", openOld)
	if st := a.do("POST", "/todo/comments", map[string]any{"item_id": oldDone, "body": "x"}, nil); st != http.StatusCreated {
		t.Fatalf("comment: %d", st)
	}

	count := func(id string) int64 {
		var n int64
		e.db.Raw("SELECT count(*) FROM todo_items WHERE id = ?", id).Scan(&n)
		return n
	}
	ctx := context.Background()
	if err := todo.CleanupDone(ctx, e.db, 0, nil); err != nil {
		t.Fatal(err)
	}
	if count(oldDone) != 1 {
		t.Fatal("days=0 deleted something")
	}

	w := a.ws()
	w.sub("o", "todo.list", map[string]any{"list_id": list})
	var changed []uuid.UUID
	if err := todo.CleanupDone(ctx, e.db, 30, func(h uuid.UUID) { changed = append(changed, h) }); err != nil {
		t.Fatal(err)
	}
	if count(oldDone) != 0 || count(kept) != 1 || count(recent) != 1 || count(openOld) != 1 || count(noDoneAt) != 1 {
		t.Fatal("wrong set of tasks deleted")
	}
	var comments int64
	e.db.Raw("SELECT count(*) FROM todo_comments WHERE item_id = ?", oldDone).Scan(&comments)
	if comments != 0 {
		t.Fatal("comment survived")
	}
	if len(changed) != 1 {
		t.Fatalf("onChanged: %v", changed)
	}
	if m := w.next(); m.Entity != "todo_items" || m.ID != oldDone {
		t.Fatalf("delete change: %+v", m)
	}

	// keep_forever: set, clear, null rejected.
	var it struct {
		KeepForever bool `json:"keep_forever"`
	}
	for _, v := range []bool{false, true} {
		if st := a.do("PATCH", "/todo/items/"+recent, map[string]any{"keep_forever": v}, &it); st != http.StatusOK || it.KeepForever != v {
			t.Fatalf("patch %v: %d %+v", v, st, it)
		}
	}
	if st := a.do("PATCH", "/todo/items/"+recent, map[string]any{"keep_forever": nil}, nil); st != http.StatusBadRequest {
		t.Fatalf("null: %d", st)
	}
}
