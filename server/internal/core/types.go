package core

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

// RawJSON to surowy JSON (np. kolumna jsonb), przekazywany dalej bez dekodowania.
type RawJSON []byte

func (j *RawJSON) Scan(src any) error {
	switch v := src.(type) {
	case nil:
		*j = nil
	case []byte:
		*j = append((*j)[:0], v...)
	case string:
		*j = RawJSON(v)
	default:
		return fmt.Errorf("RawJSON: nieobsługiwany typ %T", src)
	}
	return nil
}

func (j RawJSON) MarshalJSON() ([]byte, error) {
	if j == nil {
		return []byte("null"), nil
	}
	return j, nil
}

// UUIDArray mapuje kolumnę uuid[].
type UUIDArray []uuid.UUID

func (a UUIDArray) Value() (driver.Value, error) {
	parts := make([]string, len(a))
	for i, id := range a {
		parts[i] = id.String()
	}
	return "{" + strings.Join(parts, ",") + "}", nil
}

func (a *UUIDArray) Scan(src any) error {
	var s string
	switch v := src.(type) {
	case nil:
		*a = nil
		return nil
	case []byte:
		s = string(v)
	case string:
		s = v
	default:
		return fmt.Errorf("UUIDArray: nieobsługiwany typ %T", src)
	}
	s = strings.Trim(s, "{}")
	out := UUIDArray{}
	if s != "" {
		for _, p := range strings.Split(s, ",") {
			id, err := uuid.Parse(strings.Trim(p, `"`))
			if err != nil {
				return err
			}
			out = append(out, id)
		}
	}
	*a = out
	return nil
}

// JSONStrings maps a jsonb column holding an array of strings.
type JSONStrings []string

func (s JSONStrings) Value() (driver.Value, error) {
	if s == nil {
		return []byte("[]"), nil
	}
	return json.Marshal([]string(s))
}

func (s *JSONStrings) Scan(src any) error {
	var b []byte
	switch v := src.(type) {
	case nil:
		*s = JSONStrings{}
		return nil
	case []byte:
		b = v
	case string:
		b = []byte(v)
	default:
		return fmt.Errorf("JSONStrings: unsupported type %T", src)
	}
	out := JSONStrings{}
	if err := json.Unmarshal(b, (*[]string)(&out)); err != nil {
		return err
	}
	*s = out
	return nil
}

func (s JSONStrings) MarshalJSON() ([]byte, error) {
	if s == nil {
		return []byte("[]"), nil
	}
	return json.Marshal([]string(s))
}

// Date is a calendar date (a `date` column): midnight UTC, "2006-01-02" in JSON.
type Date struct{ time.Time }

const dateLayout = "2006-01-02"

func NewDate(y int, m time.Month, d int) Date { return Date{time.Date(y, m, d, 0, 0, 0, 0, time.UTC)} }

// DateOf is the date of t in t's location.
func DateOf(t time.Time) Date { return NewDate(t.Date()) }

func ParseDate(s string) (Date, error) {
	t, err := time.Parse(dateLayout, s)
	return Date{t}, err
}

func (d Date) String() string { return d.Format(dateLayout) }

func (d Date) AddDays(n int) Date { return Date{d.AddDate(0, 0, n)} }

func (d Date) MarshalJSON() ([]byte, error) { return json.Marshal(d.String()) }

func (d *Date) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	p, err := ParseDate(s)
	if err != nil {
		return fmt.Errorf("expected a date (YYYY-MM-DD): %w", err)
	}
	*d = p
	return nil
}

func (d Date) Value() (driver.Value, error) { return d.String(), nil }

func (d *Date) Scan(src any) error {
	switch v := src.(type) {
	case time.Time:
		*d = NewDate(v.Date())
	case string:
		p, err := ParseDate(v)
		*d = p
		return err
	case []byte:
		p, err := ParseDate(string(v))
		*d = p
		return err
	default:
		return fmt.Errorf("Date: unsupported type %T", src)
	}
	return nil
}

// TimeOfDay is a wall-clock time (a `time` column): "15:04" in JSON.
type TimeOfDay struct{ Hour, Minute int }

func ParseTimeOfDay(s string) (TimeOfDay, error) {
	for _, layout := range []string{"15:04", "15:04:05"} {
		if t, err := time.Parse(layout, s); err == nil {
			return TimeOfDay{t.Hour(), t.Minute()}, nil
		}
	}
	return TimeOfDay{}, fmt.Errorf("expected a time (HH:MM): %q", s)
}

func (t TimeOfDay) String() string { return fmt.Sprintf("%02d:%02d", t.Hour, t.Minute) }

// On is the moment of t on date d in loc.
func (t TimeOfDay) On(d Date, loc *time.Location) time.Time {
	return time.Date(d.Year(), d.Month(), d.Day(), t.Hour, t.Minute, 0, 0, loc)
}

func (t TimeOfDay) MarshalJSON() ([]byte, error) { return json.Marshal(t.String()) }

func (t *TimeOfDay) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	p, err := ParseTimeOfDay(s)
	*t = p
	return err
}

func (t TimeOfDay) Value() (driver.Value, error) { return t.String() + ":00", nil }

func (t *TimeOfDay) Scan(src any) error {
	switch v := src.(type) {
	case time.Time:
		*t = TimeOfDay{v.Hour(), v.Minute()}
		return nil
	case string:
		p, err := ParseTimeOfDay(v)
		*t = p
		return err
	case []byte:
		p, err := ParseTimeOfDay(string(v))
		*t = p
		return err
	default:
		return fmt.Errorf("TimeOfDay: unsupported type %T", src)
	}
}
