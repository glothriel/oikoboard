package todo

import (
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/teambition/rrule-go"

	"oikoboard/server/internal/core"
)

// Schedule is a validated recurrence: an RFC 5545 rule whose DTSTART is the
// template's start date at its creation time in the household timezone.
type Schedule struct {
	rule  *rrule.RRule
	loc   *time.Location
	start core.Date
	end   *core.Date
}

// LoadLocation returns the household timezone; an unknown name falls back to UTC.
func LoadLocation(name string) *time.Location {
	if loc, err := time.LoadLocation(name); err == nil && name != "" {
		return loc
	}
	return time.UTC
}

// LocalDate is the calendar date of an instant in loc — the one place dates
// are derived from instants.
func LocalDate(t time.Time, loc *time.Location) core.Date {
	return core.DateOf(t.In(loc))
}

// NewSchedule validates the rule and binds it to the start, end and creation time.
func NewSchedule(rule string, start core.Date, end *core.Date, at core.TimeOfDay, loc *time.Location) (*Schedule, error) {
	rule = strings.TrimSpace(rule)
	upper := strings.ToUpper(rule)
	if rule == "" || strings.ContainsAny(rule, "\r\n") {
		return nil, errors.New("rrule must be a single RRULE value, e.g. FREQ=WEEKLY;BYDAY=MO,FR")
	}
	for _, banned := range []string{"DTSTART", "COUNT=", "UNTIL=", "RRULE:", "EXDATE", "RDATE"} {
		if strings.Contains(upper, banned) {
			return nil, fmt.Errorf("rrule must not contain %s (start, end and time are separate fields)", strings.TrimSuffix(banned, "="))
		}
	}
	opt, err := rrule.StrToROptionInLocation(rule, loc)
	if err != nil {
		return nil, fmt.Errorf("invalid rrule: %w", err)
	}
	switch opt.Freq {
	case rrule.DAILY, rrule.WEEKLY, rrule.MONTHLY, rrule.YEARLY:
	default:
		return nil, errors.New("rrule frequency must be DAILY, WEEKLY, MONTHLY or YEARLY")
	}
	if end != nil && end.Before(start.Time) {
		return nil, errors.New("end_date is before start_date")
	}
	opt.Dtstart = at.On(start, loc)
	r, err := rrule.NewRRule(*opt)
	if err != nil {
		return nil, fmt.Errorf("invalid rrule: %w", err)
	}
	return &Schedule{rule: r, loc: loc, start: start, end: end}, nil
}

func (s *Schedule) inRange(d core.Date) bool {
	return !d.Before(s.start.Time) && (s.end == nil || !d.After(s.end.Time))
}

func (s *Schedule) dayBounds(d core.Date) (time.Time, time.Time) {
	from := time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, s.loc)
	return from, from.AddDate(0, 0, 1).Add(-time.Nanosecond)
}

// Matches says whether the schedule has an occurrence on the local date d.
func (s *Schedule) Matches(d core.Date) bool {
	if !s.inRange(d) {
		return false
	}
	from, to := s.dayBounds(d)
	return len(s.rule.Between(from, to, true)) > 0
}

// LatestUpTo is the latest occurrence date in (after, upTo]; after may be nil.
func (s *Schedule) LatestUpTo(after *core.Date, upTo core.Date) (core.Date, bool) {
	if s.end != nil && upTo.After(s.end.Time) {
		upTo = *s.end
	}
	if upTo.Before(s.start.Time) {
		return core.Date{}, false
	}
	_, to := s.dayBounds(upTo)
	last := s.rule.Before(to, true)
	if last.IsZero() {
		return core.Date{}, false
	}
	d := LocalDate(last, s.loc)
	if after != nil && !d.After(after.Time) {
		return core.Date{}, false
	}
	return d, true
}

// Next lists up to count occurrence dates on or after from.
func (s *Schedule) Next(from core.Date, count int) []core.Date {
	out := []core.Date{}
	if from.Before(s.start.Time) {
		from = s.start
	}
	it := s.rule.Iterator()
	for len(out) < count {
		t, ok := it()
		if !ok {
			break
		}
		d := LocalDate(t, s.loc)
		if s.end != nil && d.After(s.end.Time) {
			break
		}
		if d.Before(from.Time) {
			continue
		}
		if t.After(time.Date(from.Year()+30, 1, 1, 0, 0, 0, 0, s.loc)) {
			break
		}
		out = append(out, d)
	}
	return out
}
