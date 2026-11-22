package app_test

import (
	"net/http"
	"net/url"
	"testing"
	"time"
)

func TestSearch(t *testing.T) {
	e := setup(t, mockCalendars)
	a := e.newFamily("Kowalscy")
	_, lists := a.view("todo.lists", nil)
	list := lists["todo_lists"][0]["id"]
	for _, title := range []string{"Zamówić 100% soku", "Zamówić mleko", "Inne"} {
		a.do("POST", "/todo/items", map[string]any{"list_id": list, "title": title}, nil)
	}
	a.do("POST", "/todo/items", map[string]any{"list_id": list, "title": "Coś", "description": "też ZAMÓWIĆ"}, nil)

	var todo struct {
		Lists []struct{ ID string }
		Items []struct{ Title string }
	}
	search := func(path, q string, out any) {
		t.Helper()
		if st := a.do("GET", path+"?q="+url.QueryEscape(q), nil, out); st != http.StatusOK {
			t.Fatalf("search %s %q: %d", path, q, st)
		}
	}
	search("/todo/search", "zamówić", &todo)
	if len(todo.Items) != 3 {
		t.Fatalf("tasks: %+v", todo.Items)
	}
	search("/todo/search", "100%", &todo)
	if len(todo.Items) != 1 || todo.Items[0].Title != "Zamówić 100% soku" {
		t.Fatalf("wildcard not escaped: %+v", todo.Items)
	}
	search("/todo/search", "  ", &todo)
	if len(todo.Items) != 0 || len(todo.Lists) != 0 {
		t.Fatalf("empty query: %+v", todo)
	}

	// Other households don't see it.
	b := e.newFamily("Nowakowie")
	if b.do("GET", "/todo/search?q=soku", nil, &todo); len(todo.Items) != 0 {
		t.Fatalf("other household: %+v", todo.Items)
	}

	// A weekly series is one hit: its next occurrence.
	var cal struct {
		Events []occ
	}
	search("/calendar/search", "basen", &cal)
	if len(cal.Events) != 1 || cal.Events[0].Title != "Basen" {
		t.Fatalf("series: %+v", cal.Events)
	}
	if s := cal.Events[0].StartsAt; s.Before(time.Now().Add(-24*time.Hour)) || s.After(time.Now().AddDate(0, 0, 8)) {
		t.Fatalf("not the next occurrence: %s", s)
	}
}
