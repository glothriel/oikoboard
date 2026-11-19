package app_test

import (
	"context"
	"net/http"
	"net/url"
	"testing"
	"time"

	"oikoboard/server/internal/core"
)

type todoDay struct {
	ID          string
	CalendarID  string `json:"calendar_id"`
	Title       string
	Description string
	Kind        string
	StartsAt    time.Time `json:"starts_at"`
	MemberIDs   []string  `json:"member_ids"`
}

// todoDays: the due-task events by date, waiting until they match n days.
func (c *client) todoDays(n int) map[string]todoDay {
	c.e.t.Helper()
	var out map[string]todoDay
	deadline := time.Now().Add(5 * time.Second)
	for {
		var res struct {
			Data struct {
				Events []todoDay `json:"calendar_events"`
			}
		}
		now := time.Now()
		c.do("GET", "/views/calendar.range?params="+rangeParams(now.AddDate(0, 0, -40), now.AddDate(0, 2, 0)), nil, &res)
		out = map[string]todoDay{}
		for _, e := range res.Data.Events {
			if e.Kind == "todo-day" {
				out[e.StartsAt.UTC().Format("2006-01-02")] = e
			}
		}
		if len(out) == n || time.Now().After(deadline) {
			return out
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestTodoCalendar(t *testing.T) {
	e := setup(t, mockCalendars)
	a := e.newFamily("Kowalscy")
	warsaw, _ := time.LoadLocation("Europe/Warsaw")
	today := core.DateOf(time.Now().In(warsaw))
	day := func(n int) string { return today.AddDays(n).String() }

	// The first writable calendar is the target.
	_, cals := a.view("calendar.calendars", nil)
	family := idOf(cals["calendars"], "remote_id", "family")
	school := idOf(cals["calendars"], "remote_id", "school")
	for _, c := range cals["calendars"] {
		if (c["todo_target"] == true) != (c["id"] == family) {
			t.Fatalf("todo target: %+v", c)
		}
	}

	_, lists := a.view("todo.lists", nil)
	list := lists["todo_lists"][0]["id"]
	add := func(title, due string) string {
		var it struct{ ID, Due string }
		if st := a.do("POST", "/todo/items", map[string]any{"list_id": list, "title": title, "due": due}, &it); st != http.StatusCreated || it.Due != due {
			t.Fatalf("add task: %d %+v", st, it)
		}
		return it.ID
	}

	// Sample tasks are due yesterday, in 2 and in 14 days.
	first := add("Kupić prezent", day(5))
	days := a.todoDays(4)
	if d := days[day(5)]; d.Title != "Zadanie: Kupić prezent" || d.CalendarID != family || len(days) != 4 {
		t.Fatalf("days: %+v", days)
	}
	if d := days[day(2)]; d.Description != "• Zapłacić za prąd — Mama" || len(d.MemberIDs) != 1 {
		t.Fatalf("day with an assignee: %+v", d)
	}

	second := add("Zapakować prezent", day(5))
	waitTitle := func(date, title string, n int) {
		t.Helper()
		deadline := time.Now().Add(5 * time.Second)
		for a.todoDays(n)[date].Title != title {
			if time.Now().After(deadline) {
				t.Fatalf("%s: want %q, have %+v", date, title, a.todoDays(n))
			}
			time.Sleep(20 * time.Millisecond)
		}
	}
	waitTitle(day(5), "Zadania: 2", 4)

	// Moving a task to another day; the old day keeps the other one.
	a.do("PATCH", "/todo/items/"+first, map[string]any{"due": day(6)}, nil)
	waitTitle(day(6), "Zadanie: Kupić prezent", 5)
	waitTitle(day(5), "Zadanie: Zapakować prezent", 5)

	// A day without tasks loses its event (deleted or done).
	a.do("DELETE", "/todo/items/"+second, nil, nil)
	if days := a.todoDays(4); days[day(5)].ID != "" {
		t.Fatalf("emptied day kept: %+v", days)
	}
	a.do("PATCH", "/todo/items/"+first, map[string]any{"done": true}, nil)
	if days := a.todoDays(3); days[day(6)].ID != "" {
		t.Fatalf("done day kept: %+v", days)
	}

	// The events are managed: the calendar API refuses to change them.
	days = a.todoDays(3)
	if st := a.do("PATCH", "/calendar/events/"+days[day(2)].ID, map[string]any{"title": "x"}, nil); st != http.StatusConflict {
		t.Fatalf("patch managed: %d", st)
	}

	// Deleted elsewhere ("in Google"): sync drops it, reconciliation restores it.
	e.db.Exec(`UPDATE mock_provider_events SET deleted = true, seq = nextval('mock_provider_events_seq_seq')
		WHERE data->>'Kind' = 'todo-day' AND left(data->>'Start', 10) = ?`, day(2))
	a.do("POST", "/calendars/"+family+"/sync", nil, nil)
	if days := a.todoDays(2); len(days) != 2 {
		t.Fatalf("after deleting at the provider: %+v", days)
	}
	e.app.Calendar.ReconcileAllTodos(context.Background())
	if days := a.todoDays(3); days[day(2)].CalendarID != family {
		t.Fatalf("not restored: %+v", days)
	}

	// Another target: the events move there.
	if st := a.do("PATCH", "/calendars/"+school, map[string]any{"todo_target": true}, nil); st != http.StatusOK {
		t.Fatalf("set target: %d", st)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		moved := 0
		for _, d := range a.todoDays(3) {
			if d.CalendarID == school {
				moved++
			}
		}
		if moved == 3 && len(a.todoDays(3)) == 3 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("not moved: %+v", a.todoDays(3))
		}
		time.Sleep(20 * time.Millisecond)
	}

	// Unlinking the target removes its events and picks another target.
	if st := a.do("DELETE", "/calendars/"+school, nil, nil); st != http.StatusNoContent {
		t.Fatalf("unlink: %d", st)
	}
	deadline = time.Now().Add(5 * time.Second)
	for {
		days := a.todoDays(3)
		if len(days) == 3 && days[day(2)].CalendarID == family {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("after unlink: %+v", days)
		}
		time.Sleep(20 * time.Millisecond)
	}
	var left int64
	e.db.Raw(`SELECT count(*) FROM mock_provider_events WHERE calendar_id = 'school' AND NOT deleted
		AND data->>'Kind' = 'todo-day'`).Scan(&left)
	if left != 0 {
		t.Fatalf("events left in the unlinked calendar: %d", left)
	}
}

func rangeParams(from, to time.Time) string {
	return url.QueryEscape(`{"from":"` + from.Format(time.RFC3339) + `","to":"` + to.Format(time.RFC3339) + `"}`)
}

// todoTasks: the events of tasks due at a time, by title, waiting until there are n.
func (c *client) todoTasks(n int) map[string]todoDay {
	c.e.t.Helper()
	var out map[string]todoDay
	deadline := time.Now().Add(5 * time.Second)
	for {
		var res struct {
			Data struct {
				Events []struct {
					todoDay
					EndsAt time.Time `json:"ends_at"`
					AllDay bool      `json:"all_day"`
				} `json:"calendar_events"`
			}
		}
		now := time.Now()
		c.do("GET", "/views/calendar.range?params="+rangeParams(now.AddDate(0, 0, -40), now.AddDate(0, 2, 0)), nil, &res)
		out = map[string]todoDay{}
		for _, e := range res.Data.Events {
			if e.Kind == "todo-task" {
				if e.AllDay || e.EndsAt.Sub(e.StartsAt) != 15*time.Minute {
					c.e.t.Fatalf("task event span: %+v", e)
				}
				out[e.Title] = e.todoDay
			}
		}
		if len(out) == n || time.Now().After(deadline) {
			return out
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestTodoDueTime(t *testing.T) {
	e := setup(t, mockCalendars)
	a := e.newFamily("Kowalscy")
	warsaw, _ := time.LoadLocation("Europe/Warsaw")
	today := core.DateOf(time.Now().In(warsaw))
	day := func(n int) string { return today.AddDays(n).String() }
	_, lists := a.view("todo.lists", nil)
	list := lists["todo_lists"][0]["id"]
	type item struct {
		ID, Due string
		DueTime *string `json:"due_time"`
	}

	if st := a.do("POST", "/todo/items", map[string]any{"list_id": list, "title": "x", "due_time": "10:00"}, nil); st != http.StatusBadRequest {
		t.Fatalf("time without a date: %d", st)
	}
	var it item
	if st := a.do("POST", "/todo/items", map[string]any{"list_id": list, "title": "Odebrać paczkę", "due": day(3),
		"due_time": "17:30"}, &it); st != http.StatusCreated || it.DueTime == nil || *it.DueTime != "17:30" {
		t.Fatalf("add: %d %+v", st, it)
	}

	// Its own event at that time; the day keeps no line for it.
	ev := a.todoTasks(1)["Zadanie: Odebrać paczkę"]
	if want := time.Date(today.Year(), today.Month(), today.Day()+3, 17, 30, 0, 0, warsaw); !ev.StartsAt.Equal(want) {
		t.Fatalf("task event: %+v, want %v", ev, want)
	}
	if d := a.todoDays(3)[day(3)]; d.ID != "" {
		t.Fatalf("timed task in the day event: %+v", d)
	}
	if st := a.do("PATCH", "/calendar/events/"+ev.ID, map[string]any{"title": "x"}, nil); st != http.StatusConflict {
		t.Fatalf("patch managed: %d", st)
	}

	// Another time moves the event.
	a.do("PATCH", "/todo/items/"+it.ID, map[string]any{"due_time": "08:15"}, nil)
	deadline := time.Now().Add(5 * time.Second)
	for a.todoTasks(1)["Zadanie: Odebrać paczkę"].StartsAt.In(warsaw).Hour() != 8 {
		if time.Now().After(deadline) {
			t.Fatalf("not moved: %+v", a.todoTasks(1))
		}
		time.Sleep(20 * time.Millisecond)
	}

	// Without the time, back to the day's event.
	a.do("PATCH", "/todo/items/"+it.ID, map[string]any{"due_time": nil}, &it)
	if it.DueTime != nil || it.Due != day(3) {
		t.Fatalf("clear time: %+v", it)
	}
	if n := len(a.todoTasks(0)); n != 0 {
		t.Fatalf("task event kept: %d", n)
	}
	if d := a.todoDays(4)[day(3)]; d.Title != "Zadanie: Odebrać paczkę" {
		t.Fatalf("day event: %+v", d)
	}

	// Clearing the date clears the time; done tasks lose their event.
	a.do("PATCH", "/todo/items/"+it.ID, map[string]any{"due_time": "12:00"}, nil)
	a.todoTasks(1)
	if st := a.do("PATCH", "/todo/items/"+it.ID, map[string]any{"due": nil}, &it); st != http.StatusOK || it.DueTime != nil {
		t.Fatalf("clear due: %d %+v", st, it)
	}
	a.do("PATCH", "/todo/items/"+it.ID, map[string]any{"due": day(1), "due_time": "12:00"}, nil)
	a.todoTasks(1)
	a.do("PATCH", "/todo/items/"+it.ID, map[string]any{"done": true}, nil)
	if n := len(a.todoTasks(0)); n != 0 {
		t.Fatalf("done task event kept: %d", n)
	}
}
