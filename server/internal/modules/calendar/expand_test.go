package calendar

import (
	"testing"
	"time"

	"github.com/google/uuid"

	"oikoboard/server/internal/core"
)

func series(start time.Time, dur time.Duration, allDay bool, tz string, rec ...string) remoteRow {
	end := start.Add(dur)
	return remoteRow{ID: uuid.New(), RemoteID: "s", StartsAt: &start, EndsAt: &end, AllDay: allDay,
		Timezone: tz, Recurrence: core.JSONStrings(rec), Status: "confirmed"}
}

func TestExpandKeepsLocalTimeAcrossDST(t *testing.T) {
	warsaw, _ := time.LoadLocation("Europe/Warsaw")
	cal := &Calendar{Timezone: "Europe/Warsaw"}
	// 9:00 Warsaw on Saturdays, across the switch to winter time (2026-10-25).
	start := time.Date(2026, 10, 17, 9, 0, 0, 0, warsaw)
	got, err := expand(cal, series(start, time.Hour, false, "", "RRULE:FREQ=WEEKLY;COUNT=3"), start)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 3 {
		t.Fatalf("instances: %v", got)
	}
	for _, g := range got {
		if h := g.In(warsaw).Hour(); h != 9 {
			t.Fatalf("instance at %v (hour %d in Warsaw)", g, h)
		}
	}
}

func TestExpandAllDayWithExdate(t *testing.T) {
	cal := &Calendar{Timezone: "Europe/Warsaw"}
	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	got, err := expand(cal, series(start, 24*time.Hour, true, "",
		"RRULE:FREQ=DAILY;COUNT=4", "EXDATE;VALUE=DATE:20260102"), start)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"2026-01-01", "2026-01-03", "2026-01-04"}
	if len(got) != len(want) {
		t.Fatalf("instances: %v", got)
	}
	for i, g := range got {
		if g.Format("2006-01-02") != want[i] || g.Hour() != 0 {
			t.Fatalf("instance %d: %v", i, g)
		}
	}
}

func TestOccurrencesApplyExceptions(t *testing.T) {
	cal := &Calendar{ID: uuid.New(), Timezone: "UTC"}
	start := time.Date(2026, 3, 2, 10, 0, 0, 0, time.UTC)
	m := series(start, time.Hour, false, "", "RRULE:FREQ=DAILY;COUNT=3")
	second, third := start.AddDate(0, 0, 1), start.AddDate(0, 0, 2)
	moved := second.Add(2 * time.Hour)
	movedEnd := moved.Add(time.Hour)
	s := "s"
	rows := []remoteRow{m,
		{ID: uuid.New(), RemoteID: "s_2", SeriesRemoteID: &s, OriginalStart: &second, Status: "confirmed",
			Title: "moved", StartsAt: &moved, EndsAt: &movedEnd},
		{ID: uuid.New(), RemoteID: "s_3", SeriesRemoteID: &s, OriginalStart: &third, Status: "cancelled"},
	}
	got, err := occurrences(cal, "s", rows, nil, start)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("occurrences: %+v", got)
	}
	// The exception keeps the id of the instance it replaces.
	if got[1].Title != "moved" || got[1].ID != occurrenceID(m.ID, second) || !got[1].StartsAt.Equal(moved) {
		t.Fatalf("exception: %+v", got[1])
	}
}
