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

type recRow struct {
	ID          string  `json:"id"`
	Active      bool    `json:"active"`
	LastRunDate *string `json:"last_run_date"`
	CreateTime  string  `json:"create_time"`
}

func (c *client) firstList() string {
	_, lists := c.view("todo.lists", nil)
	return lists["todo_lists"][0]["id"].(string)
}

func (c *client) recurringItems(recID string) []map[string]any {
	_, d := c.view("todo.open", nil)
	var out []map[string]any
	for _, it := range d["todo_items"] {
		if it["recurring_id"] == recID {
			out = append(out, it)
		}
	}
	return out
}

func TestRecurringCRUD(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	list := a.firstList()

	body := map[string]any{"list_id": list, "title": "Zakupy", "rrule": "FREQ=WEEKLY;BYDAY=MO,FR",
		"start_date": "2026-01-01", "due_offset_days": 2}
	var rec recRow
	if st := a.do("POST", "/todo/recurring", body, &rec); st != http.StatusCreated || !rec.Active || rec.CreateTime != "06:00" || rec.LastRunDate == nil {
		t.Fatalf("create: %d %+v", st, rec)
	}

	// validation
	for name, patch := range map[string]map[string]any{
		"count":     {"rrule": "FREQ=DAILY;COUNT=3"},
		"hourly":    {"rrule": "FREQ=HOURLY"},
		"end<start": {"end_date": "2025-01-01"},
		"title":     {"title": ""},
	} {
		if st := a.do("PATCH", "/todo/recurring/"+rec.ID, patch, nil); st != http.StatusBadRequest {
			t.Errorf("%s: %d", name, st)
		}
	}
	// a due time needs a due offset; clearing the offset clears the time
	if st := a.do("PATCH", "/todo/recurring/"+rec.ID, map[string]any{"due_offset_days": nil}, nil); st != http.StatusOK {
		t.Errorf("clear offset: %d", st)
	}
	if st := a.do("PATCH", "/todo/recurring/"+rec.ID, map[string]any{"due_time": "09:00"}, nil); st != http.StatusBadRequest {
		t.Errorf("time without offset: %d", st)
	}
	bad := map[string]any{"list_id": list, "title": "x", "rrule": "nonsense", "start_date": "2026-01-01"}
	if st := a.do("POST", "/todo/recurring", bad, nil); st != http.StatusBadRequest {
		t.Errorf("create with a bad rule: %d", st)
	}

	// preview
	var pv struct{ Dates []string }
	if st := a.do("POST", "/todo/recurring/preview", map[string]any{"rrule": "FREQ=DAILY", "start_date": "2026-01-01", "count": 3}, &pv); st != http.StatusOK || len(pv.Dates) != 3 {
		t.Fatalf("preview: %d %+v", st, pv)
	}

	// pause, then it is in the view
	if st := a.do("PATCH", "/todo/recurring/"+rec.ID, map[string]any{"active": false}, &rec); st != http.StatusOK || rec.Active {
		t.Fatalf("pause: %d %+v", st, rec)
	}
	if _, d := a.view("todo.recurring", nil); len(d["todo_recurring"]) != 1 {
		t.Fatalf("view: %+v", d)
	}

	// another household sees and touches nothing
	b := e.newFamily("Nowakowie")
	if _, d := b.view("todo.recurring", nil); len(d["todo_recurring"]) != 0 {
		t.Fatalf("other household sees: %+v", d)
	}
	if st := b.do("PATCH", "/todo/recurring/"+rec.ID, map[string]any{"title": "x"}, nil); st != http.StatusNotFound {
		t.Errorf("other household patch: %d", st)
	}
	if st := b.do("DELETE", "/todo/recurring/"+rec.ID, nil, nil); st != http.StatusNotFound {
		t.Errorf("other household delete: %d", st)
	}
	foreign := map[string]any{"list_id": b.firstList(), "title": "x", "rrule": "FREQ=DAILY", "start_date": "2026-01-01"}
	if st := a.do("POST", "/todo/recurring", foreign, nil); st == http.StatusCreated {
		t.Error("a template in another household's list must be rejected")
	}

	if st := a.do("DELETE", "/todo/recurring/"+rec.ID, nil, nil); st != http.StatusNoContent {
		t.Fatalf("delete: %d", st)
	}
}

func TestRecurringGenerate(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	list := a.firstList()
	var rec recRow
	a.do("POST", "/todo/recurring", map[string]any{"list_id": list, "title": "Zakupy", "description": "chleb",
		"rrule": "FREQ=WEEKLY;BYDAY=MO,FR", "start_date": "2026-01-01", "due_offset_days": 2, "due_time": "18:00"}, &rec)
	ctx := context.Background()
	date := func(s string) core.Date { v, _ := core.ParseDate(s); return v }

	// Monday 2026-11-23: one task, due Wednesday 18:00
	if created, err := todo.Generate(ctx, e.db, nil, mustUUID(t, rec.ID), date("2026-11-23")); err != nil || !created {
		t.Fatalf("generate: %v %v", created, err)
	}
	items := a.recurringItems(rec.ID)
	if len(items) != 1 || items[0]["title"] != "Zakupy" || items[0]["due"] != "2026-11-25" || items[0]["due_time"] != "18:00" ||
		items[0]["occurrence_date"] != "2026-11-23" || items[0]["description"] != "chleb" {
		t.Fatalf("generated: %+v", items)
	}
	// the same occurrence again: still one
	if created, _ := todo.Generate(ctx, e.db, nil, mustUUID(t, rec.ID), date("2026-11-23")); created {
		t.Error("duplicate trigger created a task")
	}
	// Tuesday doesn't match
	if created, _ := todo.Generate(ctx, e.db, nil, mustUUID(t, rec.ID), date("2026-11-24")); created {
		t.Error("created on a non-matching day")
	}
	if len(a.recurringItems(rec.ID)) != 1 {
		t.Fatal("expected exactly one task")
	}

	// paused: nothing
	a.do("PATCH", "/todo/recurring/"+rec.ID, map[string]any{"active": false}, nil)
	if created, _ := todo.Generate(ctx, e.db, nil, mustUUID(t, rec.ID), date("2026-11-27")); created {
		t.Error("created while paused")
	}
	// deleted template: generate is a no-op, tasks stay as ordinary ones
	a.do("DELETE", "/todo/recurring/"+rec.ID, nil, nil)
	if created, err := todo.Generate(ctx, e.db, nil, mustUUID(t, rec.ID), date("2026-11-30")); created || err != nil {
		t.Errorf("deleted template: %v %v", created, err)
	}
	_, d := a.view("todo.open", nil)
	n := 0
	for _, it := range d["todo_items"] {
		if it["title"] == "Zakupy" && it["recurring_id"] == nil {
			n++
		}
	}
	if n != 1 {
		t.Fatalf("the generated task must stay after the template is deleted, got %d", n)
	}
}

func TestRecurringCatchUp(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	list := a.firstList()
	var rec recRow
	a.do("POST", "/todo/recurring", map[string]any{"list_id": list, "title": "Zakupy",
		"rrule": "FREQ=WEEKLY;BYDAY=MO,FR", "start_date": "2026-01-01"}, &rec)
	// pretend the server last processed Sunday 2026-11-22 and was down since
	if err := e.db.Exec("UPDATE todo_recurring SET last_run_date = '2026-11-22' WHERE id = ?", rec.ID).Error; err != nil {
		t.Fatal(err)
	}
	warsaw, _ := time.LoadLocation("Europe/Warsaw")
	saturday := time.Date(2026, 11, 28, 12, 0, 0, 0, warsaw)
	if err := todo.CatchUp(context.Background(), e.db, nil, saturday); err != nil {
		t.Fatal(err)
	}
	items := a.recurringItems(rec.ID)
	if len(items) != 1 || items[0]["occurrence_date"] != "2026-11-27" {
		t.Fatalf("only the latest missed occurrence (Friday) expected: %+v", items)
	}
	// a second pass changes nothing
	if err := todo.CatchUp(context.Background(), e.db, nil, saturday); err != nil {
		t.Fatal(err)
	}
	if len(a.recurringItems(rec.ID)) != 1 {
		t.Fatal("catch-up is not idempotent")
	}

	// a schedule change never produces retroactive tasks
	a.do("PATCH", "/todo/recurring/"+rec.ID, map[string]any{"rrule": "FREQ=DAILY"}, &rec)
	if rec.LastRunDate == nil {
		t.Fatal("last_run_date must be reset on a schedule change")
	}
	// ...while a title edit keeps it
	before := *rec.LastRunDate
	a.do("PATCH", "/todo/recurring/"+rec.ID, map[string]any{"title": "Zakupy 2"}, &rec)
	if rec.LastRunDate == nil || *rec.LastRunDate != before {
		t.Fatalf("a title edit must not touch last_run_date: %v vs %v", rec.LastRunDate, before)
	}
}

func mustUUID(t *testing.T, s string) uuid.UUID {
	t.Helper()
	id, err := uuid.Parse(s)
	if err != nil {
		t.Fatal(err)
	}
	return id
}
