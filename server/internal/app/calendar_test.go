package app_test

import (
	"context"
	"net/http"
	"net/url"
	"testing"
	"time"

	"github.com/google/uuid"

	"oikoboard/server/internal/core"
)

func mockCalendars(c *core.AuthConfig) { c.MockOAuth, c.Google = true, nil }

// connectMock goes through the connect flow like the app + browser do.
func (e *env) connectMock(c *client) string {
	e.t.Helper()
	verifier, challenge := pkce()
	var start struct{ URL string }
	if st := c.do("POST", "/calendar/connections", map[string]any{
		"return": "http://localhost:5555/", "challenge": challenge}, &start); st != http.StatusOK {
		e.t.Fatalf("start connect: %d", st)
	}
	res, err := noRedirect.Get(e.srv.URL + start.URL)
	if err != nil || res.StatusCode != http.StatusFound {
		e.t.Fatalf("browser start: %v %v", err, res.Status)
	}
	req, _ := http.NewRequest("GET", e.srv.URL+res.Header.Get("Location"), nil)
	for _, ck := range res.Cookies() {
		req.AddCookie(ck)
	}
	res, err = noRedirect.Do(req)
	if err != nil || res.StatusCode != http.StatusFound {
		e.t.Fatalf("callback: %v %v", err, res.Status)
	}
	back, _ := url.Parse(res.Header.Get("Location"))
	code := back.Query().Get("code")
	if code == "" {
		e.t.Fatalf("no code: %s", back)
	}
	var conn struct{ ID, Provider string }
	if st := c.do("POST", "/calendar/connections/complete", map[string]any{
		"code": code, "verifier": verifier}, &conn); st != http.StatusOK || conn.Provider != "mock" {
		e.t.Fatalf("complete: %d %+v", st, conn)
	}
	return conn.ID
}

type occ struct {
	ID            string
	EventID       string `json:"event_id"`
	CalendarID    string `json:"calendar_id"`
	Title         string
	StartsAt      time.Time  `json:"starts_at"`
	OriginalStart *time.Time `json:"original_start"`
	MemberIDs     []string   `json:"member_ids"`
}

func (c *client) occurrences(from, to time.Time, eventID string) []occ {
	c.e.t.Helper()
	var res struct {
		Data struct {
			Events []occ `json:"calendar_events"`
		}
	}
	p := url.QueryEscape(`{"from":"` + from.Format(time.RFC3339) + `","to":"` + to.Format(time.RFC3339) + `"}`)
	if st := c.do("GET", "/views/calendar.range?params="+p, nil, &res); st != http.StatusOK {
		c.e.t.Fatalf("range: %d", st)
	}
	var out []occ
	for _, o := range res.Data.Events {
		if eventID == "" || o.EventID == eventID {
			out = append(out, o)
		}
	}
	return out
}

func TestCalendarSync(t *testing.T) {
	e := setup(t, mockCalendars)
	a := e.newFamily("Kowalscy")
	e.app.Calendar.ReconcileAllTodos(context.Background()) // due tasks → calendar, before watching changes
	now := time.Now()
	from, to := now.AddDate(0, 0, -30), now.AddDate(0, 3, 0)

	// Sample data: three mock calendars, a weekly series among the events.
	_, cals := a.view("calendar.calendars", nil)
	if len(cals["calendars"]) != 3 {
		t.Fatalf("seed calendars: %d", len(cals["calendars"]))
	}
	holidays := idOf(cals["calendars"], "remote_id", "holidays")
	basen := 0
	for _, o := range a.occurrences(from, to, "") {
		if o.Title == "Basen" {
			basen++
		}
	}
	if basen < 4 {
		t.Fatalf("weekly series not expanded: %d", basen)
	}

	// Connect an account and link one of its calendars.
	connID := e.connectMock(a)
	var remote []struct {
		RemoteID string `json:"remote_id"`
		Linked   bool
	}
	a.do("GET", "/calendar/connections/"+connID+"/calendars", nil, &remote)
	if len(remote) != 3 || remote[0].Linked {
		t.Fatalf("remote calendars: %+v", remote)
	}
	var cal struct{ ID string }
	if st := a.do("POST", "/calendars", map[string]any{"connection_id": connID, "remote_id": "family"}, &cal); st != http.StatusCreated {
		t.Fatalf("link: %d", st)
	}
	if st := a.do("POST", "/calendars", map[string]any{"connection_id": connID, "remote_id": "family"}, nil); st != http.StatusConflict {
		t.Fatalf("link twice: %d", st)
	}

	// Another account can't complete someone else's connect flow.
	b := e.newFamily("Nowakowie")
	_, challenge := pkce()
	var start struct{ URL string }
	a.do("POST", "/calendar/connections", map[string]any{"return": "http://localhost:5555/", "challenge": challenge}, &start)
	if st := b.do("POST", "/calendar/connections/complete", map[string]any{"code": "x", "verifier": "y"}, nil); st != http.StatusBadRequest {
		t.Fatalf("foreign complete: %d", st)
	}

	ws := a.ws()
	ws.sub("cal", "calendar.range", map[string]any{"from": from, "to": to})

	// A single event.
	single := uuid.NewString() // client-chosen: idempotent retries
	start1 := time.Date(now.Year(), now.Month(), now.Day()+2, 10, 0, 0, 0, time.Local)
	var created occ
	if st := a.do("POST", "/calendar/events", map[string]any{
		"id": single, "calendar_id": cal.ID, "title": "Fryzjer",
		"starts_at": start1, "ends_at": start1.Add(time.Hour)}, &created); st != http.StatusCreated || created.Title != "Fryzjer" {
		t.Fatalf("create: %d %+v", st, created)
	}
	if m := ws.next(); m.T != "upsert" || m.Row["id"] != created.ID {
		t.Fatalf("realtime create: %+v", m)
	}
	var again occ
	a.do("POST", "/calendar/events", map[string]any{
		"id": single, "calendar_id": cal.ID, "title": "Fryzjer",
		"starts_at": start1, "ends_at": start1.Add(time.Hour)}, &again)
	if again.ID != created.ID || len(a.occurrences(from, to, created.EventID)) != 1 {
		t.Fatalf("retried create made a duplicate: %+v", again)
	}
	ws.drain()

	// A series of three; change one occurrence, then the series, delete one.
	var first occ
	a.do("POST", "/calendar/events", map[string]any{
		"calendar_id": cal.ID, "title": "Angielski",
		"starts_at": start1.Add(8 * time.Hour), "ends_at": start1.Add(9 * time.Hour),
		"recurrence": []string{"RRULE:FREQ=WEEKLY;COUNT=3"}}, &first)
	series := first.EventID
	occs := a.occurrences(from, to, series)
	if len(occs) != 3 || occs[1].OriginalStart == nil {
		t.Fatalf("series: %+v", occs)
	}
	if st := a.do("PATCH", "/calendar/events/"+occs[1].ID+"?scope=this", map[string]any{"title": "Angielski (odwołany pokój)"}, nil); st != http.StatusOK {
		t.Fatalf("patch this: %d", st)
	}
	a.do("PATCH", "/calendar/events/"+occs[0].ID+"?scope=series", map[string]any{"title": "Angielski B1"}, nil)
	got := a.occurrences(from, to, series)
	if len(got) != 3 || got[0].Title != "Angielski B1" || got[1].Title != "Angielski (odwołany pokój)" ||
		got[2].Title != "Angielski B1" || got[1].ID != occs[1].ID {
		t.Fatalf("after edits: %+v", got)
	}
	if st := a.do("DELETE", "/calendar/events/"+occs[2].ID+"?scope=this", nil, nil); st != http.StatusNoContent {
		t.Fatalf("delete this: %d", st)
	}
	if got := a.occurrences(from, to, series); len(got) != 2 {
		t.Fatalf("after delete this: %d", len(got))
	}

	// Moving the whole series shifts every occurrence and resets changes of
	// single occurrences (they'd no longer line up with the instances).
	a.do("PATCH", "/calendar/events/"+occs[0].ID+"?scope=series", map[string]any{
		"starts_at": occs[0].StartsAt.Add(time.Hour), "ends_at": occs[0].StartsAt.Add(2 * time.Hour)}, nil)
	got = a.occurrences(from, to, series)
	if len(got) != 3 || !got[0].StartsAt.Equal(occs[0].StartsAt.Add(time.Hour)) || got[1].Title != "Angielski B1" {
		t.Fatalf("after moving series: %+v", got)
	}
	a.do("PATCH", "/calendar/events/"+got[1].ID+"?scope=this", map[string]any{"title": "Angielski (odwołany pokój)"}, nil)
	a.do("DELETE", "/calendar/events/"+got[2].ID+"?scope=this", nil, nil)

	// Changed elsewhere (in "Google"): picked up by sync.
	if err := e.db.Exec(`UPDATE mock_provider_events
		SET data = jsonb_set(data, '{Title}', '"Fryzjer — przełożony"'),
		    seq = nextval('mock_provider_events_seq_seq')
		WHERE remote_id = ?`, single[:8]+single[9:13]+single[14:18]+single[19:23]+single[24:]).Error; err != nil {
		t.Fatal(err)
	}
	ws.drain()
	if st := a.do("POST", "/calendars/"+cal.ID+"/sync", nil, nil); st != http.StatusNoContent {
		t.Fatalf("sync: %d", st)
	}
	if m := ws.next(); m.T != "upsert" || m.Row["title"] != "Fryzjer — przełożony" {
		t.Fatalf("realtime after sync: %+v", m)
	}
	ws.expectNone() // nothing else changed

	// The mirror is rebuildable from the provider alone.
	e.db.Exec("DELETE FROM calendar_remote_events WHERE calendar_id = ?", cal.ID)
	e.db.Exec("UPDATE calendar_sync_state SET sync_token = '' WHERE calendar_id = ?", cal.ID)
	a.do("POST", "/calendars/"+cal.ID+"/sync", nil, nil)
	if got := a.occurrences(from, to, series); len(got) != 2 || got[1].Title != "Angielski (odwołany pokój)" {
		t.Fatalf("after rebuild: %+v", got)
	}

	// Read-only calendars refuse writes.
	if st := a.do("POST", "/calendar/events", map[string]any{"calendar_id": holidays, "title": "x",
		"starts_at": start1, "ends_at": start1}, nil); st != http.StatusForbidden {
		t.Fatalf("read-only: %d", st)
	}

	// Deleting the series removes all of it.
	a.do("DELETE", "/calendar/events/"+got[0].ID+"?scope=series", nil, nil)
	if got := a.occurrences(from, to, series); len(got) != 0 {
		t.Fatalf("after delete series: %d", len(got))
	}

	// Disconnecting the account unlinks its calendars.
	if st := a.do("DELETE", "/calendar/connections/"+connID, nil, nil); st != http.StatusNoContent {
		t.Fatalf("disconnect: %d", st)
	}
	_, cals = a.view("calendar.calendars", nil)
	if len(cals["calendars"]) != 3 {
		t.Fatalf("calendars after disconnect: %d", len(cals["calendars"]))
	}
}

func TestCalendarPreferences(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	var p struct{ View string }
	if st := a.do("GET", "/calendar/preferences", nil, &p); st != http.StatusOK || p.View != "month" {
		t.Fatalf("default: %d %+v", st, p)
	}
	if st := a.do("PATCH", "/calendar/preferences", map[string]any{"view": "3days"}, nil); st != http.StatusOK {
		t.Fatalf("update: %d", st)
	}
	if st := a.do("PATCH", "/calendar/preferences", map[string]any{"view": "year"}, nil); st != http.StatusBadRequest {
		t.Fatalf("invalid view: %d", st)
	}
	if a.do("GET", "/calendar/preferences", nil, &p); p.View != "3days" {
		t.Fatalf("saved: %+v", p)
	}
	// Another member of another household doesn't see it.
	b := e.newFamily("Nowakowie")
	if b.do("GET", "/calendar/preferences", nil, &p); p.View != "month" {
		t.Fatalf("other member: %+v", p)
	}
}
