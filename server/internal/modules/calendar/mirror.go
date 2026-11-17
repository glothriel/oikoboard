package calendar

import (
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/teambition/rrule-go"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"oikoboard/server/internal/core"
)

// The mirror (calendar_remote_events) holds provider events as they are;
// calendar_events holds their occurrences, which is what everybody reads.
// Both are only written here, in one transaction.

type remoteRow struct {
	ID             uuid.UUID `gorm:"type:uuid;primaryKey"`
	HouseholdID    uuid.UUID `gorm:"type:uuid"`
	CalendarID     uuid.UUID `gorm:"type:uuid"`
	RemoteID       string
	ETag           string `gorm:"column:etag"`
	RemoteUpdated  time.Time
	Status         string
	Title          string
	Description    string
	Location       string
	StartsAt       *time.Time
	EndsAt         *time.Time
	AllDay         bool
	Timezone       string
	Recurrence     core.JSONStrings `gorm:"type:jsonb"`
	SeriesRemoteID *string
	OriginalStart  *time.Time
	MemberIDs      core.UUIDArray   `gorm:"type:uuid[]"`
	AttendeeEmails core.JSONStrings `gorm:"type:jsonb"`
	Kind           string
}

func (remoteRow) TableName() string { return "calendar_remote_events" }

func (r remoteRow) event() RemoteEvent {
	ev := RemoteEvent{
		RemoteID: r.RemoteID, ETag: r.ETag, Updated: r.RemoteUpdated, Status: r.Status,
		Title: r.Title, Description: r.Description, Location: r.Location,
		AllDay: r.AllDay, TimeZone: r.Timezone, Recurrence: r.Recurrence,
		OriginalStart: r.OriginalStart, MemberIDs: r.MemberIDs, AttendeeEmails: r.AttendeeEmails,
		Kind: r.Kind,
	}
	if r.StartsAt != nil {
		ev.Start, ev.End = *r.StartsAt, *r.EndsAt
	}
	if r.SeriesRemoteID != nil {
		ev.SeriesRemoteID = *r.SeriesRemoteID
	}
	return ev
}

var idSpace = uuid.MustParse("6f0c5f5e-3c39-4a0e-9a3b-0b1c2d3e4f50")

// mirrorID: the stable id of a provider event in a calendar.
func mirrorID(cal uuid.UUID, remoteID string) uuid.UUID {
	return uuid.NewSHA1(idSpace, []byte(cal.String()+"/"+remoteID))
}

// occurrenceID: the stable id of one occurrence of a series.
func occurrenceID(event uuid.UUID, originalStart time.Time) uuid.UUID {
	return uuid.NewSHA1(idSpace, []byte(event.String()+"@"+originalStart.UTC().Format(time.RFC3339)))
}

// applyRemote stores provider events in the mirror and refreshes the
// affected occurrences. full: evs is the whole calendar — everything else is
// removed. Mirror ids derive from (calendar, remote id), so a mirror rebuilt
// from the provider gets the same ids.
func applyRemote(tx *gorm.DB, cal *Calendar, evs []RemoteEvent, full bool) error {
	keys := map[string]bool{}
	seen := make([]string, 0, len(evs))
	for _, ev := range evs {
		seen = append(seen, ev.RemoteID)
		key := ev.RemoteID
		if ev.SeriesRemoteID != "" {
			key = ev.SeriesRemoteID
		}
		keys[key] = true
		if ev.cancelled() && ev.SeriesRemoteID == "" {
			// A deleted event (for a series also its exceptions).
			if err := tx.Where("calendar_id = ? AND (remote_id = ? OR series_remote_id = ?)",
				cal.ID, ev.RemoteID, ev.RemoteID).Delete(&remoteRow{}).Error; err != nil {
				return err
			}
			continue
		}
		if err := upsertRemote(tx, cal, ev); err != nil {
			return err
		}
	}
	if full {
		var gone []remoteRow
		q := tx.Where("calendar_id = ?", cal.ID)
		if len(seen) > 0 {
			q = q.Where("remote_id NOT IN ?", seen)
		}
		if err := q.Clauses(clause.Returning{}).Delete(&gone).Error; err != nil {
			return err
		}
		for _, r := range gone {
			keys[r.key()] = true
		}
		// Occurrences whose mirror rows were lost some other way.
		var stale []string
		tx.Raw(`SELECT DISTINCT remote_key FROM calendar_events WHERE calendar_id = ?`, cal.ID).Scan(&stale)
		for _, k := range stale {
			keys[k] = true
		}
	}
	return materialize(tx, cal, keys)
}

func (r remoteRow) key() string {
	if r.SeriesRemoteID != nil {
		return *r.SeriesRemoteID
	}
	return r.RemoteID
}

func upsertRemote(tx *gorm.DB, cal *Calendar, ev RemoteEvent) error {
	id := mirrorID(cal.ID, ev.RemoteID)
	row := remoteRow{
		ID: id, HouseholdID: cal.HouseholdID, CalendarID: cal.ID, RemoteID: ev.RemoteID,
		ETag: ev.ETag, RemoteUpdated: ev.Updated, Status: ev.Status,
		Title: ev.Title, Description: ev.Description, Location: ev.Location,
		AllDay: ev.AllDay, Timezone: ev.TimeZone, Recurrence: ev.Recurrence,
		OriginalStart: ev.OriginalStart, MemberIDs: ev.MemberIDs, AttendeeEmails: ev.AttendeeEmails,
		Kind: ev.Kind,
	}
	if row.Recurrence == nil {
		row.Recurrence = core.JSONStrings{}
	}
	if row.MemberIDs == nil {
		row.MemberIDs = core.UUIDArray{}
	}
	if row.AttendeeEmails == nil {
		row.AttendeeEmails = core.JSONStrings{}
	}
	if !ev.cancelled() {
		s, e := ev.Start, ev.End
		if e.Before(s) {
			e = s
		}
		row.StartsAt, row.EndsAt = &s, &e
	}
	if ev.SeriesRemoteID != "" {
		row.SeriesRemoteID = &ev.SeriesRemoteID
	}
	// Last write wins, but never let an older version (e.g. a sync that
	// fetched before our own write) overwrite a newer one.
	return tx.Clauses(clause.OnConflict{
		Columns: []clause.Column{{Name: "calendar_id"}, {Name: "remote_id"}},
		DoUpdates: clause.AssignmentColumns([]string{"etag", "remote_updated", "status", "title",
			"description", "location", "starts_at", "ends_at", "all_day", "timezone", "recurrence",
			"series_remote_id", "original_start", "member_ids", "attendee_emails", "kind"}),
		Where: clause.Where{Exprs: []clause.Expression{
			clause.Expr{SQL: "calendar_remote_events.remote_updated <= EXCLUDED.remote_updated"},
		}},
	}).Create(&row).Error
}

// removeRemote drops a series/single event and its exceptions locally.
func removeRemote(tx *gorm.DB, cal *Calendar, key string) error {
	if err := tx.Where("calendar_id = ? AND (remote_id = ? OR series_remote_id = ?)", cal.ID, key, key).
		Delete(&remoteRow{}).Error; err != nil {
		return err
	}
	return materialize(tx, cal, map[string]bool{key: true})
}

// Occurrences of series are kept from a year back to two years ahead (the
// window moves forward daily, see Syncer).
const (
	windowBack   = 365 * 24 * time.Hour
	windowAhead  = 2 * 365 * 24 * time.Hour
	maxInstances = 3000
)

// materialize recomputes occurrences of the given series/single events and
// writes only the differences (so the change feed carries real changes only).
func materialize(tx *gorm.DB, cal *Calendar, keys map[string]bool) error {
	if len(keys) == 0 {
		return nil
	}
	emails, err := memberEmails(tx, cal.HouseholdID)
	if err != nil {
		return err
	}
	now := time.Now()
	for key := range keys {
		var rows []remoteRow
		if err := tx.Where("calendar_id = ? AND (remote_id = ? OR series_remote_id = ?)", cal.ID, key, key).
			Find(&rows).Error; err != nil {
			return err
		}
		want, err := occurrences(cal, key, rows, emails, now)
		if err != nil {
			return err
		}
		var have []Event
		if err := tx.Where("calendar_id = ? AND remote_key = ?", cal.ID, key).Find(&have).Error; err != nil {
			return err
		}
		byID := make(map[uuid.UUID]Event, len(have))
		for _, h := range have {
			byID[h.ID] = h
		}
		for _, w := range want {
			h, ok := byID[w.ID]
			delete(byID, w.ID)
			switch {
			case !ok:
				if err := tx.Create(&w).Error; err != nil {
					return err
				}
			case !sameOccurrence(h, w):
				if err := tx.Model(&Event{}).Where("id = ?", w.ID).Updates(map[string]any{
					"event_id": w.EventID, "title": w.Title, "description": w.Description,
					"location": w.Location, "starts_at": w.StartsAt, "ends_at": w.EndsAt,
					"all_day": w.AllDay, "member_ids": w.MemberIDs, "recurrence": w.Recurrence,
					"original_start": w.OriginalStart, "kind": w.Kind,
				}).Error; err != nil {
					return err
				}
			}
		}
		for id := range byID {
			if err := tx.Delete(&Event{}, "id = ?", id).Error; err != nil {
				return err
			}
		}
	}
	return nil
}

func sameTime(a, b *time.Time) bool {
	if a == nil || b == nil {
		return a == b
	}
	return a.Equal(*b)
}

func sameOccurrence(a, b Event) bool {
	return a.EventID == b.EventID && a.Title == b.Title && a.Description == b.Description &&
		a.Location == b.Location && a.StartsAt.Equal(b.StartsAt) && a.EndsAt.Equal(b.EndsAt) &&
		a.AllDay == b.AllDay && slices.Equal(a.MemberIDs, b.MemberIDs) &&
		slices.Equal(a.Recurrence, b.Recurrence) && sameTime(a.OriginalStart, b.OriginalStart) &&
		a.Kind == b.Kind
}

// memberEmails: account e-mail → member, to recognize members among a
// provider event's attendees.
func memberEmails(tx *gorm.DB, hh uuid.UUID) (map[string]uuid.UUID, error) {
	var rows []struct {
		ID    uuid.UUID
		Email string
	}
	err := tx.Raw(`SELECT m.id, lower(u.email) AS email FROM members m JOIN users u ON u.id = m.user_id
		WHERE m.household_id = ?`, hh).Scan(&rows).Error
	out := make(map[string]uuid.UUID, len(rows))
	for _, r := range rows {
		out[r.Email] = r.ID
	}
	return out, err
}

func membersOf(r remoteRow, emails map[string]uuid.UUID) core.UUIDArray {
	if len(r.MemberIDs) > 0 {
		return r.MemberIDs
	}
	out := core.UUIDArray{}
	for _, e := range r.AttendeeEmails {
		if id, ok := emails[e]; ok && !slices.Contains(out, id) {
			out = append(out, id)
		}
	}
	return out
}

func (c *Calendar) location(tz string) *time.Location {
	for _, name := range []string{tz, c.Timezone} {
		if name == "" {
			continue
		}
		if loc, err := time.LoadLocation(name); err == nil {
			return loc
		}
	}
	return time.UTC
}

// occurrences computes what calendar_events should hold for one key.
func occurrences(cal *Calendar, key string, rows []remoteRow, emails map[string]uuid.UUID, now time.Time) ([]Event, error) {
	var master *remoteRow
	var exceptions []remoteRow
	for i := range rows {
		if rows[i].SeriesRemoteID == nil {
			master = &rows[i]
		} else {
			exceptions = append(exceptions, rows[i])
		}
	}
	base := func(r remoteRow, id, eventID uuid.UUID) Event {
		return Event{
			ID: id, HouseholdID: cal.HouseholdID, CalendarID: cal.ID, EventID: eventID, RemoteKey: key,
			Title: r.Title, Description: r.Description, Location: r.Location,
			StartsAt: *r.StartsAt, EndsAt: *r.EndsAt, AllDay: r.AllDay,
			MemberIDs: membersOf(r, emails), Recurrence: core.JSONStrings{}, Kind: r.Kind,
		}
	}
	var out []Event
	if master != nil && master.StartsAt != nil && master.Status != "cancelled" {
		if len(master.Recurrence) == 0 {
			out = append(out, base(*master, master.ID, master.ID))
		} else {
			starts, err := expand(cal, *master, now)
			if err != nil {
				return nil, fmt.Errorf("event %s: %w", master.RemoteID, err)
			}
			replaced := map[int64]bool{}
			for _, ex := range exceptions {
				if ex.OriginalStart != nil {
					replaced[ex.OriginalStart.Unix()] = true
				}
			}
			dur := master.EndsAt.Sub(*master.StartsAt)
			for _, s := range starts {
				if replaced[s.Unix()] {
					continue
				}
				o := base(*master, occurrenceID(master.ID, s), master.ID)
				o.StartsAt, o.EndsAt = s, s.Add(dur)
				st := s
				o.OriginalStart = &st
				o.Recurrence = master.Recurrence
				out = append(out, o)
			}
		}
	}
	for _, ex := range exceptions {
		if ex.Status == "cancelled" || ex.StartsAt == nil {
			continue
		}
		if master == nil || master.Status == "cancelled" {
			// An instance whose series isn't in this calendar: show it alone.
			out = append(out, base(ex, ex.ID, ex.ID))
			continue
		}
		o := base(ex, occurrenceID(master.ID, *ex.OriginalStart), master.ID)
		o.OriginalStart = ex.OriginalStart
		o.Recurrence = master.Recurrence
		if len(ex.MemberIDs) == 0 && len(ex.AttendeeEmails) == 0 {
			o.MemberIDs = membersOf(*master, emails)
		}
		out = append(out, o)
	}
	return out, nil
}

// expand returns the starts of a series' instances within the window.
func expand(cal *Calendar, m remoteRow, now time.Time) ([]time.Time, error) {
	loc := time.UTC // all-day events are stored at UTC midnight
	if !m.AllDay {
		loc = cal.location(m.Timezone)
	}
	set, err := rrule.StrSliceToRRuleSetInLoc(recurrenceLines(m.Recurrence), loc)
	if err != nil {
		return nil, err
	}
	set.DTStart(m.StartsAt.In(loc))
	dur := m.EndsAt.Sub(*m.StartsAt)
	from, to := now.Add(-windowBack-dur), now.Add(windowAhead)
	var out []time.Time
	next := set.Iterator()
	for t, ok := next(); ok && len(out) < maxInstances; t, ok = next() {
		if t.After(to) {
			break
		}
		if t.After(from) {
			out = append(out, t.UTC())
		}
	}
	return out, nil
}

// recurrenceLines keeps the lines rrule-go understands.
func recurrenceLines(lines []string) []string {
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		u := strings.ToUpper(l)
		if strings.HasPrefix(u, "RRULE:") || strings.HasPrefix(u, "EXDATE") || strings.HasPrefix(u, "RDATE") {
			out = append(out, l)
		}
	}
	return out
}

// ValidRecurrence checks recurrence lines coming from clients.
func ValidRecurrence(lines []string) error {
	for _, l := range lines {
		if len(recurrenceLines([]string{l})) != 1 {
			return fmt.Errorf("unsupported recurrence line %q", l)
		}
	}
	_, err := rrule.StrSliceToRRuleSetInLoc(lines, time.UTC)
	return err
}
