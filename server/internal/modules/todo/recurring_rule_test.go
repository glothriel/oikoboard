package todo

import (
	"testing"
	"time"

	"oikoboard/server/internal/core"
)

func d(s string) core.Date {
	v, err := core.ParseDate(s)
	if err != nil {
		panic(err)
	}
	return v
}

func warsaw(t *testing.T) *time.Location {
	t.Helper()
	loc, err := time.LoadLocation("Europe/Warsaw")
	if err != nil {
		t.Fatal(err)
	}
	return loc
}

func mustSchedule(t *testing.T, rule, start string, end *core.Date) *Schedule {
	t.Helper()
	s, err := NewSchedule(rule, d(start), end, core.TimeOfDay{Hour: 6}, warsaw(t))
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestScheduleWeeklyMondayFriday(t *testing.T) {
	s := mustSchedule(t, "FREQ=WEEKLY;BYDAY=MO,FR", "2026-11-01", nil)
	for day, want := range map[string]bool{
		"2026-11-23": true,  // Monday
		"2026-11-24": false, // Tuesday
		"2026-11-27": true,  // Friday
		"2026-11-28": false, // Saturday
	} {
		if got := s.Matches(d(day)); got != want {
			t.Errorf("%s: got %v want %v", day, got, want)
		}
	}
	if s.Matches(d("2026-10-30")) { // a Friday before start_date
		t.Error("matched before start_date")
	}
}

func TestScheduleMonthlyLastDay(t *testing.T) {
	s := mustSchedule(t, "FREQ=MONTHLY;BYMONTHDAY=-1", "2026-01-01", nil)
	got := s.Next(d("2026-02-01"), 3)
	want := []string{"2026-02-28", "2026-03-31", "2026-04-30"}
	for i, w := range want {
		if i >= len(got) || got[i].String() != w {
			t.Fatalf("got %v want %v", got, want)
		}
	}
}

func TestScheduleMonthDayWithoutThatDay(t *testing.T) {
	s := mustSchedule(t, "FREQ=MONTHLY;BYMONTHDAY=31", "2026-01-01", nil)
	if s.Matches(d("2026-04-30")) || s.Matches(d("2026-02-28")) {
		t.Error("a month without the 31st must have no occurrence")
	}
	if !s.Matches(d("2026-05-31")) {
		t.Error("31 May expected")
	}
}

func TestScheduleEndDate(t *testing.T) {
	end := d("2026-11-25")
	s := mustSchedule(t, "FREQ=DAILY", "2026-11-20", &end)
	if !s.Matches(d("2026-11-25")) || s.Matches(d("2026-11-26")) {
		t.Error("end_date is inclusive and final")
	}
	if got, ok := s.LatestUpTo(nil, d("2026-12-31")); !ok || got.String() != "2026-11-25" {
		t.Errorf("latest up to after the end: %v %v", got, ok)
	}
}

func TestScheduleDSTDay(t *testing.T) {
	// 2026-03-29 is the spring-forward day in Warsaw; 06:00 exists on it.
	s := mustSchedule(t, "FREQ=DAILY", "2026-03-27", nil)
	for _, day := range []string{"2026-03-28", "2026-03-29", "2026-03-30"} {
		if !s.Matches(d(day)) {
			t.Errorf("%s should match", day)
		}
	}
}

func TestScheduleLatestUpTo(t *testing.T) {
	s := mustSchedule(t, "FREQ=WEEKLY;BYDAY=MO,FR", "2026-01-01", nil)
	got, ok := s.LatestUpTo(nil, d("2026-11-28")) // Saturday
	if !ok || got.String() != "2026-11-27" {
		t.Fatalf("got %v %v", got, ok)
	}
	after := d("2026-11-27")
	if _, ok := s.LatestUpTo(&after, d("2026-11-28")); ok {
		t.Error("nothing after the last processed date")
	}
}

func TestScheduleRejects(t *testing.T) {
	loc := warsaw(t)
	for _, rule := range []string{
		"", "nonsense", "FREQ=HOURLY", "FREQ=MINUTELY", "FREQ=DAILY;COUNT=3",
		"FREQ=DAILY;UNTIL=20261231T000000Z", "DTSTART:20260101T000000Z\nRRULE:FREQ=DAILY",
		"RRULE:FREQ=DAILY", "FREQ=DAILY;BYDAY=XX",
	} {
		if _, err := NewSchedule(rule, d("2026-01-01"), nil, core.TimeOfDay{Hour: 6}, loc); err == nil {
			t.Errorf("%q must be rejected", rule)
		}
	}
	end := d("2025-12-31")
	if _, err := NewSchedule("FREQ=DAILY", d("2026-01-01"), &end, core.TimeOfDay{Hour: 6}, loc); err == nil {
		t.Error("end before start must be rejected")
	}
}

func TestLoadLocationFallback(t *testing.T) {
	if LoadLocation("Nowhere/Land") != time.UTC || LoadLocation("") != time.UTC {
		t.Error("an invalid timezone falls back to UTC")
	}
}
