package calendar

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

// Due tasks in the calendar: one all-day event per day that has open tasks
// (or lists) due, in the household's todo target calendar. These events are owned by
// Oikoboard — they are derived from the tasks and reconciled against the
// mirror (desired vs. actual), so changes made to them elsewhere are undone.
// See docs/calendar.md.

// KindTodoDay marks the daily due-tasks event.
const KindTodoDay = "todo-day"

// Days around today kept in sync; older events are left alone (history).
const (
	todoDaysBack  = 30
	todoDaysAhead = 365
)

// todoState is the Syncer's bookkeeping for due-task reconciliation.
type todoState struct {
	mu     sync.Mutex
	timers map[uuid.UUID]*time.Timer
}

// TodosChanged schedules reconciliation of the household's due-task events
// (debounced: a burst of task edits makes one round of provider writes).
func (s *Syncer) TodosChanged(hh uuid.UUID) {
	s.todo.mu.Lock()
	defer s.todo.mu.Unlock()
	if t := s.todo.timers[hh]; t != nil {
		t.Reset(s.TodoDelay)
		return
	}
	if s.todo.timers == nil {
		s.todo.timers = map[uuid.UUID]*time.Timer{}
	}
	s.todo.timers[hh] = time.AfterFunc(s.TodoDelay, func() {
		ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
		defer cancel()
		if err := s.ReconcileTodos(ctx, hh); err != nil {
			slog.Warn("due tasks → calendar", "household", hh, "err", err)
		}
	})
}

// ReconcileAllTodos reconciles every household with a linked calendar.
func (s *Syncer) ReconcileAllTodos(ctx context.Context) {
	var hhs []uuid.UUID
	s.DB.WithContext(ctx).Raw(`SELECT DISTINCT household_id FROM calendars`).Scan(&hhs)
	for _, hh := range hhs {
		if err := s.ReconcileTodos(ctx, hh); err != nil {
			slog.Warn("due tasks → calendar", "household", hh, "err", err)
		}
	}
}

// ReconcileTodos makes the household's due-task events match its open tasks:
// the target calendar gets one event per day with tasks due (created or
// updated as needed), a day without tasks loses its event, and other
// calendars lose theirs (e.g. after the target changed).
func (s *Syncer) ReconcileTodos(ctx context.Context, hh uuid.UUID) error {
	defer s.lock(uuid.NewSHA1(idSpace, []byte("todo/"+hh.String())))()
	db := s.DB.WithContext(ctx)
	var cals []Calendar
	if err := db.Where("household_id = ?", hh).Order("created_at").Find(&cals).Error; err != nil {
		return err
	}
	var rows []remoteRow
	if err := db.Where("household_id = ? AND kind = ?", hh, KindTodoDay).Find(&rows).Error; err != nil {
		return err
	}
	have := map[uuid.UUID][]remoteRow{}
	for _, r := range rows {
		have[r.CalendarID] = append(have[r.CalendarID], r)
	}
	var errs []error
	for i := range cals {
		cal := &cals[i]
		var want map[string]RemoteEvent
		keep := func(remoteRow) bool { return false }
		if cal.TodoTarget && cal.Writable {
			from, to := todoWindow(cal)
			var err error
			if want, err = todoDays(db, hh, from, to); err != nil {
				return err
			}
			// Days outside the window aren't touched.
			keep = func(r remoteRow) bool {
				return r.StartsAt != nil && (r.StartsAt.Before(from.Time) || !r.StartsAt.Before(to.AddDays(1).Time))
			}
		}
		if len(want) == 0 && len(have[cal.ID]) == 0 {
			continue
		}
		if err := s.applyManaged(ctx, cal, have[cal.ID], want, keep); err != nil {
			errs = append(errs, fmt.Errorf("calendar %s: %w", cal.ID, err))
		}
	}
	return errors.Join(errs...)
}

// RemoveManaged deletes the due-task events of a calendar (before it is
// unlinked — afterwards there's no way to reach them).
func (s *Syncer) RemoveManaged(ctx context.Context, calID uuid.UUID) error {
	db := s.DB.WithContext(ctx)
	var cal Calendar
	if err := db.First(&cal, "id = ?", calID).Error; err != nil {
		return err
	}
	var rows []remoteRow
	if err := db.Where("calendar_id = ? AND kind <> ''", calID).Find(&rows).Error; err != nil {
		return err
	}
	if len(rows) == 0 {
		return nil
	}
	return s.applyManaged(ctx, &cal, rows, nil, func(remoteRow) bool { return false })
}

// todoWindow: the days kept in sync, in the calendar's time zone.
func todoWindow(cal *Calendar) (from, to core.Date) {
	today := core.DateOf(time.Now().In(cal.location("")))
	return today.AddDays(-todoDaysBack), today.AddDays(todoDaysAhead)
}

// todoDays computes the desired events: remote id → event. A day lists the
// lists due that day (unless all their tasks are done) and the open tasks due.
func todoDays(db *gorm.DB, hh uuid.UUID, from, to core.Date) (map[string]RemoteEvent, error) {
	// Reads the todo module's tables directly: the event is a projection of them.
	var entries []struct {
		IsList     bool
		Title      string
		Due        core.Date
		AssigneeID *uuid.UUID
		Assignee   string
	}
	if err := db.Raw(`SELECT true AS is_list, l.name AS title, l.due, NULL::uuid AS assignee_id, '' AS assignee,
			l.created_at, l.id
		FROM todo_lists l
		WHERE l.household_id = ? AND l.due BETWEEN ? AND ?
		  AND (EXISTS (SELECT 1 FROM todo_items i WHERE i.list_id = l.id AND NOT i.done)
		       OR NOT EXISTS (SELECT 1 FROM todo_items i WHERE i.list_id = l.id))
		UNION ALL
		SELECT false, i.title, i.due, i.assignee_id, coalesce(m.name, ''), i.created_at, i.id
		FROM todo_items i LEFT JOIN members m ON m.id = i.assignee_id
		WHERE i.household_id = ? AND NOT i.done AND i.due BETWEEN ? AND ?
		ORDER BY due, is_list DESC, created_at, id`, hh, from, to, hh, from, to).Scan(&entries).Error; err != nil {
		return nil, err
	}
	type day struct {
		date    core.Date
		titles  []string
		lines   []string
		members []uuid.UUID
	}
	var days []*day
	for _, t := range entries {
		if len(days) == 0 || !days[len(days)-1].date.Equal(t.Due.Time) {
			days = append(days, &day{date: t.Due})
		}
		d := days[len(days)-1]
		line := "• " + t.Title
		title := "Zadanie: " + t.Title
		if t.IsList {
			line += " (lista)"
			title = "Lista: " + t.Title
		}
		d.titles = append(d.titles, title)
		if t.Assignee != "" {
			line += " — " + t.Assignee
		}
		d.lines = append(d.lines, line)
		if t.AssigneeID != nil && !slices.Contains(d.members, *t.AssigneeID) {
			d.members = append(d.members, *t.AssigneeID)
		}
	}
	out := make(map[string]RemoteEvent, len(days))
	for _, d := range days {
		title := fmt.Sprintf("Zadania: %d", len(d.titles))
		if len(d.titles) == 1 {
			title = d.titles[0]
		}
		id := TodoDayRemoteID(hh, d.date)
		out[id] = RemoteEvent{
			RemoteID: id, Status: "confirmed", Kind: KindTodoDay,
			Title: title, Description: strings.Join(d.lines, "\n"),
			Start: d.date.Time, End: d.date.AddDays(1).Time, AllDay: true,
			MemberIDs: d.members,
		}
	}
	return out, nil
}

// TodoDayRemoteID: the provider id of a household's due-task event for a day
// (stable, so a retried or repeated create can't duplicate it).
func TodoDayRemoteID(hh uuid.UUID, d core.Date) string {
	return RemoteIDFor(uuid.NewSHA1(idSpace, []byte(hh.String()+"/"+KindTodoDay+"/"+d.String())))
}

func sameManaged(r remoteRow, w RemoteEvent) bool {
	return r.Status != "cancelled" && r.StartsAt != nil && r.Kind == w.Kind && r.Title == w.Title &&
		r.Description == w.Description && r.AllDay == w.AllDay &&
		r.StartsAt.Equal(w.Start) && r.EndsAt.Equal(w.End) &&
		len(r.Recurrence) == 0 && slices.Equal([]uuid.UUID(r.MemberIDs), w.MemberIDs)
}

// applyManaged writes the differences between have (mirror) and want to the
// provider and applies what the provider stored to the mirror. Rows for which
// keep is true are left alone even if not wanted.
func (s *Syncer) applyManaged(ctx context.Context, cal *Calendar, have []remoteRow, want map[string]RemoteEvent,
	keep func(remoteRow) bool) error {
	defer s.lock(cal.ID)()
	var conn Connection
	if err := s.DB.WithContext(ctx).First(&conn, "id = ?", cal.ConnectionID).Error; err != nil {
		return err
	}
	p, err := s.Providers.For(ctx, s.DB, conn)
	if err != nil {
		return err
	}
	byID := make(map[string]remoteRow, len(have))
	for _, r := range have {
		byID[r.RemoteID] = r
	}
	var stored []RemoteEvent
	err = func() error {
		for id, w := range want {
			r, ok := byID[id]
			if ok && sameManaged(r, w) {
				continue
			}
			w.TimeZone = cal.Timezone
			out, err := p.Put(ctx, cal.RemoteID, w, !ok)
			if err != nil {
				return err
			}
			stored = append(stored, out)
		}
		for _, r := range have {
			if _, ok := want[r.RemoteID]; ok || keep(r) {
				continue
			}
			if err := p.Delete(ctx, cal.RemoteID, r.RemoteID); err != nil {
				return err
			}
			stored = append(stored, RemoteEvent{RemoteID: r.RemoteID, Status: "cancelled", Updated: time.Now().UTC()})
		}
		return nil
	}()
	// Whatever reached the provider goes to the mirror, even after an error.
	if len(stored) > 0 {
		werr := core.Write(ctx, s.DB, core.Actor{}, "", func(tx *gorm.DB) error {
			return applyRemote(tx, cal, stored, false)
		})
		err = errors.Join(err, werr)
	}
	return err
}

// ensureTodoTarget: a household without a todo target calendar gets its
// oldest writable one.
func ensureTodoTarget(tx *gorm.DB, hh uuid.UUID) error {
	return tx.Exec(`UPDATE calendars SET todo_target = true
		WHERE id = (SELECT id FROM calendars WHERE household_id = ? AND writable ORDER BY created_at, id LIMIT 1)
		  AND NOT EXISTS (SELECT 1 FROM calendars WHERE household_id = ? AND todo_target)`, hh, hh).Error
}
