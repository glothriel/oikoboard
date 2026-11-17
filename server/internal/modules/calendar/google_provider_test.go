package calendar

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

// fakeGoogle serves the few Calendar API v3 endpoints the provider uses.
func fakeGoogle(t *testing.T) (*httptest.Server, *[]string) {
	var calls []string
	mux := http.NewServeMux()
	mux.HandleFunc("GET /users/me/calendarList", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"items":[
			{"id":"fam@group.calendar.google.com","summary":"Rodzina","backgroundColor":"#16a765","accessRole":"owner","timeZone":"Europe/Warsaw"},
			{"id":"pl.polish#holiday","summary":"Święta","summaryOverride":"Święta w Polsce","backgroundColor":"#ffad46","accessRole":"reader"}]}`))
	})
	mux.HandleFunc("GET /calendars/{cal}/events", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		calls = append(calls, "list "+r.PathValue("cal")+" sync="+q.Get("syncToken")+" page="+q.Get("pageToken"))
		switch {
		case q.Get("syncToken") == "expired":
			w.WriteHeader(http.StatusGone)
		case q.Get("syncToken") != "":
			w.Write([]byte(`{"items":[
				{"id":"gone","status":"cancelled"},
				{"id":"ser_20260310T090000Z","status":"cancelled","recurringEventId":"ser",
				 "originalStartTime":{"dateTime":"2026-03-10T10:00:00+01:00","timeZone":"Europe/Warsaw"}}],
				"nextSyncToken":"t2"}`))
		case q.Get("pageToken") == "":
			w.Write([]byte(`{"items":[
				{"id":"ser","status":"confirmed","etag":"\"1\"","updated":"2026-03-01T10:00:00.000Z","summary":"Basen",
				 "start":{"dateTime":"2026-03-03T17:00:00+01:00","timeZone":"Europe/Warsaw"},
				 "end":{"dateTime":"2026-03-03T18:00:00+01:00","timeZone":"Europe/Warsaw"},
				 "recurrence":["RRULE:FREQ=WEEKLY"],
				 "extendedProperties":{"private":{"oiko.members":"6c1b3b1e-8d7e-4b8a-9d55-0c9c1b8f5a01"}}},
				{"id":"old","status":"cancelled"}],
				"nextPageToken":"p2"}`))
		default:
			w.Write([]byte(`{"items":[
				{"id":"bday","status":"confirmed","updated":"2026-03-01T10:00:00Z","summary":"Urodziny",
				 "start":{"date":"2026-03-05"},"end":{"date":"2026-03-06"},
				 "attendees":[{"email":"Mama@Example.com"}]}],
				"nextSyncToken":"t1"}`))
		}
	})
	echo := func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		calls = append(calls, r.Method+" "+r.URL.Path+" "+string(b))
		if r.Method == "POST" && strings.Contains(string(b), `"id":"dup"`) {
			w.WriteHeader(http.StatusConflict)
			return
		}
		var ev map[string]any
		json.Unmarshal(b, &ev)
		if ev["id"] == nil {
			ev["id"] = r.PathValue("id")
		}
		ev["etag"], ev["updated"], ev["status"] = `"2"`, "2026-03-02T10:00:00Z", "confirmed"
		json.NewEncoder(w).Encode(ev)
	}
	mux.HandleFunc("POST /calendars/{cal}/events", echo)
	mux.HandleFunc("PATCH /calendars/{cal}/events/{id}", echo)
	mux.HandleFunc("DELETE /calendars/{cal}/events/{id}", func(w http.ResponseWriter, r *http.Request) {
		calls = append(calls, "DELETE "+r.PathValue("id"))
		w.WriteHeader(http.StatusGone) // already deleted — fine
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv, &calls
}

func TestGoogleProvider(t *testing.T) {
	srv, calls := fakeGoogle(t)
	g := googleProvider{http: srv.Client(), base: srv.URL}
	ctx := context.Background()

	cals, err := g.ListCalendars(ctx)
	if err != nil || len(cals) != 2 {
		t.Fatalf("calendars: %v %+v", err, cals)
	}
	if !cals[0].Writable || cals[1].Writable || cals[1].Name != "Święta w Polsce" || cals[0].Color != 0xFF16a765 {
		t.Fatalf("calendar mapping: %+v", cals)
	}

	// Full listing over two pages; cancelled non-exceptions are skipped.
	cs, err := g.Changes(ctx, "fam@group.calendar.google.com", "")
	if err != nil || !cs.Full || cs.Token != "t1" || len(cs.Events) != 2 {
		t.Fatalf("full: %v %+v", err, cs)
	}
	ser, bday := cs.Events[0], cs.Events[1]
	if ser.TimeZone != "Europe/Warsaw" || len(ser.Recurrence) != 1 || len(ser.MemberIDs) != 1 || ser.Start.Hour() != 17 {
		t.Fatalf("series mapping: %+v", ser)
	}
	if !bday.AllDay || !bday.Start.Equal(time.Date(2026, 3, 5, 0, 0, 0, 0, time.UTC)) ||
		bday.AttendeeEmails[0] != "mama@example.com" {
		t.Fatalf("all-day mapping: %+v", bday)
	}

	// Incremental: deletions and a cancelled instance.
	cs, _ = g.Changes(ctx, "fam@group.calendar.google.com", "t1")
	if cs.Full || cs.Token != "t2" || len(cs.Events) != 2 || cs.Events[1].SeriesRemoteID != "ser" ||
		cs.Events[1].OriginalStart.UTC().Hour() != 9 {
		t.Fatalf("incremental: %+v", cs)
	}
	if _, err := g.Changes(ctx, "x", "expired"); err != ErrSyncReset {
		t.Fatalf("410 → %v", err)
	}

	// Writes: our fields only; members in private extended properties;
	// a retried create (409) becomes a patch.
	mid := uuid.MustParse("6c1b3b1e-8d7e-4b8a-9d55-0c9c1b8f5a01")
	start := time.Date(2026, 3, 9, 10, 0, 0, 0, time.UTC)
	out, err := g.Put(ctx, "fam", RemoteEvent{RemoteID: "dup", Title: "Fryzjer", Start: start,
		End: start.Add(time.Hour), TimeZone: "Europe/Warsaw", MemberIDs: []uuid.UUID{mid}}, true)
	if err != nil || out.Title != "Fryzjer" || out.RemoteID != "dup" || len(out.MemberIDs) != 1 {
		t.Fatalf("put: %v %+v", err, out)
	}
	last := (*calls)[len(*calls)-1]
	if !strings.HasPrefix(last, "PATCH /calendars/fam/events/dup ") || !strings.Contains(last, `"recurrence":[]`) ||
		!strings.Contains(last, `"oiko.members":"`+mid.String()+`"`) || strings.Contains(last, "attendees") {
		t.Fatalf("patch body: %s", last)
	}
	// Instance edits don't send recurrence.
	orig := start
	g.Put(ctx, "fam", RemoteEvent{RemoteID: InstanceID("ser", orig, false), Title: "x", Start: start, End: start,
		SeriesRemoteID: "ser", OriginalStart: &orig}, false)
	if last := (*calls)[len(*calls)-1]; !strings.Contains(last, "/events/ser_20260309T100000Z") ||
		strings.Contains(last, "recurrence") {
		t.Fatalf("instance patch: %s", last)
	}
	if err := g.Delete(ctx, "fam", "gone"); err != nil {
		t.Fatalf("delete of a deleted event: %v", err)
	}
}
