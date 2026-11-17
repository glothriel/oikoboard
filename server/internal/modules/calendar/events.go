package calendar

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

// Writes go to the provider first; the event it returns is applied to the
// mirror in the same request, so the response and the realtime update
// already reflect the stored state.

var errReadOnly = errors.New("read-only calendar")

// target loads a household calendar with its provider, checking it can be written.
func (m Module) target(ctx context.Context, hh, calID uuid.UUID) (*Calendar, Provider, error) {
	var cal Calendar
	if err := m.DB.WithContext(ctx).First(&cal, "household_id = ? AND id = ?", hh, calID).Error; err != nil {
		return nil, nil, err
	}
	if !cal.Writable {
		return nil, nil, errReadOnly
	}
	var conn Connection
	if err := m.DB.WithContext(ctx).First(&conn, "id = ?", cal.ConnectionID).Error; err != nil {
		return nil, nil, err
	}
	p, err := m.Providers.For(ctx, m.DB, conn)
	return &cal, p, err
}

func fail(c *gin.Context, err error) {
	var ge *gError
	switch {
	case errors.Is(err, errReadOnly):
		core.Fail(c, http.StatusForbidden, "read_only", "this calendar is read-only")
	case errors.Is(err, ErrRevoked):
		core.Fail(c, http.StatusConflict, "calendar_revoked", "calendar access was revoked — reconnect the account")
	case errors.As(err, &ge):
		slog.Warn("calendar provider", "err", err)
		core.Fail(c, http.StatusBadGateway, "calendar_provider", "calendar provider error: "+ge.Message())
	default:
		core.FailErr(c, err)
	}
}

// allDayDate normalizes all-day boundaries to UTC midnight.
func allDayDate(t time.Time) time.Time {
	u := t.UTC()
	return time.Date(u.Year(), u.Month(), u.Day(), 0, 0, 0, 0, time.UTC)
}

func normalize(ev *RemoteEvent) error {
	if ev.AllDay {
		ev.Start, ev.End = allDayDate(ev.Start), allDayDate(ev.End)
		if !ev.End.After(ev.Start) {
			ev.End = ev.Start.AddDate(0, 0, 1)
		}
	}
	if ev.End.Before(ev.Start) {
		return errors.New("ends_at is before starts_at")
	}
	if strings.TrimSpace(ev.Title) == "" {
		return errors.New("title is required")
	}
	return ValidRecurrence(ev.Recurrence)
}

// write stores ev at the provider and applies the result to the mirror.
func (m Module) write(c *gin.Context, cal *Calendar, p Provider, ev RemoteEvent, create bool) error {
	ctx := c.Request.Context()
	defer m.Syncer.lock(cal.ID)()
	out, err := p.Put(ctx, cal.RemoteID, ev, create)
	if err != nil {
		return err
	}
	return core.Write(ctx, m.DB, core.ActorOf(c), core.MutationID(c), func(tx *gorm.DB) error {
		return applyRemote(tx, cal, []RemoteEvent{out}, false)
	})
}

func (m Module) createEvent(c *gin.Context) {
	var req struct {
		// Client-chosen id: makes a retried create idempotent (it becomes
		// the provider event id). The stored occurrence gets its own id.
		ID          uuid.UUID   `json:"id"`
		CalendarID  uuid.UUID   `json:"calendar_id" binding:"required"`
		Title       string      `json:"title" binding:"required"`
		Description string      `json:"description"`
		Location    string      `json:"location"`
		StartsAt    time.Time   `json:"starts_at" binding:"required"`
		EndsAt      time.Time   `json:"ends_at" binding:"required"`
		AllDay      bool        `json:"all_day"`
		Recurrence  []string    `json:"recurrence"`
		MemberIDs   []uuid.UUID `json:"member_ids"`
	}
	if !core.Bind(c, &req) {
		return
	}
	if req.ID == uuid.Nil {
		req.ID = uuid.New()
	}
	actor := core.ActorOf(c)
	ctx := c.Request.Context()
	if err := core.CheckMembers(m.DB.WithContext(ctx), actor.HouseholdID, req.MemberIDs); err != nil {
		core.FailErr(c, err)
		return
	}
	cal, p, err := m.target(ctx, actor.HouseholdID, req.CalendarID)
	if err != nil {
		fail(c, err)
		return
	}
	ev := RemoteEvent{
		RemoteID: RemoteIDFor(req.ID), Title: req.Title, Description: req.Description, Location: req.Location,
		Start: req.StartsAt, End: req.EndsAt, AllDay: req.AllDay, TimeZone: cal.Timezone,
		Recurrence: req.Recurrence, MemberIDs: req.MemberIDs,
	}
	if err := normalize(&ev); err != nil {
		core.Fail(c, http.StatusBadRequest, "bad_request", err.Error())
		return
	}
	if err := m.write(c, cal, p, ev, true); err != nil {
		fail(c, err)
		return
	}
	// The occurrence (for a series: the first one).
	eventID := mirrorID(cal.ID, ev.RemoteID)
	var occ Event
	err = m.DB.WithContext(ctx).Where("event_id = ?", eventID).Order("starts_at").First(&occ).Error
	if err != nil {
		c.JSON(http.StatusCreated, gin.H{"event_id": eventID})
		return
	}
	c.JSON(http.StatusCreated, occ)
}

// occurrence loads an occurrence and the mirror row of its series/event.
func (m Module) occurrence(c *gin.Context) (*Event, *remoteRow, bool) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return nil, nil, false
	}
	actor := core.ActorOf(c)
	db := m.DB.WithContext(c.Request.Context())
	var occ Event
	if err := db.First(&occ, "household_id = ? AND id = ?", actor.HouseholdID, id).Error; err != nil {
		core.FailErr(c, err)
		return nil, nil, false
	}
	if occ.Kind != "" {
		core.Fail(c, http.StatusConflict, "managed_event", "this event is managed by Oikoboard (e.g. due tasks) — change the tasks instead")
		return nil, nil, false
	}
	var row remoteRow
	if err := db.First(&row, "id = ?", occ.EventID).Error; err != nil {
		core.FailErr(c, err)
		return nil, nil, false
	}
	return &occ, &row, true
}

func scopeOf(c *gin.Context) (string, bool) {
	s := c.DefaultQuery("scope", "this")
	if s != "this" && s != "series" {
		core.Fail(c, http.StatusBadRequest, "bad_request", "scope must be this or series")
		return "", false
	}
	return s, true
}

// PATCH /calendar/events/:id?scope=this|series — :id is an occurrence. For
// an occurrence of a series, "this" changes only it (an exception) and
// "series" changes the whole series (a time change shifts every occurrence).
func (m Module) updateEvent(c *gin.Context) {
	scope, ok := scopeOf(c)
	if !ok {
		return
	}
	p, ok := core.BindPatch(c)
	if !ok {
		return
	}
	var (
		title, description, location string
		starts, ends                 time.Time
		allDay                       bool
		members                      core.UUIDArray
		recurrence                   []string
	)
	cols, err := p.Apply(map[string]any{
		"title": &title, "description": &description, "location": &location,
		"starts_at": &starts, "ends_at": &ends, "all_day": &allDay,
		"member_ids": &members, "recurrence": &recurrence,
	})
	if err != nil {
		core.Fail(c, http.StatusBadRequest, "bad_request", err.Error())
		return
	}
	occ, row, ok := m.occurrence(c)
	if !ok {
		return
	}
	actor := core.ActorOf(c)
	ctx := c.Request.Context()
	if err := core.CheckMembers(m.DB.WithContext(ctx), actor.HouseholdID, members); err != nil {
		core.FailErr(c, err)
		return
	}
	cal, prov, err := m.target(ctx, actor.HouseholdID, occ.CalendarID)
	if err != nil {
		fail(c, err)
		return
	}

	series := len(row.Recurrence) > 0 && row.SeriesRemoteID == nil
	var ev RemoteEvent
	moved := false // the series' instances move — its exceptions no longer line up
	switch {
	case series && scope == "this":
		if _, ok := cols["recurrence"]; ok {
			core.Fail(c, http.StatusBadRequest, "bad_request", "recurrence can only be changed for the whole series")
			return
		}
		ev = RemoteEvent{
			RemoteID: InstanceID(row.RemoteID, *occ.OriginalStart, row.AllDay),
			Title:    occ.Title, Description: occ.Description, Location: occ.Location,
			Start: occ.StartsAt, End: occ.EndsAt, AllDay: occ.AllDay, TimeZone: row.Timezone,
			MemberIDs: occ.MemberIDs, SeriesRemoteID: row.RemoteID, OriginalStart: occ.OriginalStart,
		}
	case series:
		ev = row.event()
		_, hasStart := cols["starts_at"]
		_, hasEnd := cols["ends_at"]
		if hasStart || hasEnd {
			newS, newE := occ.StartsAt, occ.EndsAt
			if v, ok := cols["starts_at"].(time.Time); ok {
				newS = v
			}
			if v, ok := cols["ends_at"].(time.Time); ok {
				newE = v
			}
			ev.Start = ev.Start.Add(newS.Sub(occ.StartsAt))
			ev.End = ev.Start.Add(newE.Sub(newS))
			moved = !newS.Equal(occ.StartsAt)
		}
		delete(cols, "starts_at")
		delete(cols, "ends_at")
	default: // single event, or an instance whose series isn't mirrored
		ev = row.event()
	}
	for k, v := range cols {
		switch k {
		case "title":
			ev.Title, _ = v.(string)
		case "description":
			ev.Description, _ = v.(string)
		case "location":
			ev.Location, _ = v.(string)
		case "starts_at":
			ev.Start, _ = v.(time.Time)
		case "ends_at":
			ev.End, _ = v.(time.Time)
		case "all_day":
			ev.AllDay, _ = v.(bool)
		case "member_ids":
			ev.MemberIDs, _ = v.(core.UUIDArray)
		case "recurrence":
			ev.Recurrence, _ = v.([]string)
		}
	}
	if !ev.AllDay && ev.TimeZone == "" {
		ev.TimeZone = cal.Timezone
	}
	if err := normalize(&ev); err != nil {
		core.Fail(c, http.StatusBadRequest, "bad_request", err.Error())
		return
	}
	if err := m.write(c, cal, prov, ev, false); err != nil {
		fail(c, err)
		return
	}
	if moved {
		if err := m.resetExceptions(c, cal, prov, row.RemoteID); err != nil {
			fail(c, err)
			return
		}
	}
	var out Event
	if err := m.DB.WithContext(ctx).First(&out, "id = ?", occ.ID).Error; err != nil {
		c.Status(http.StatusNoContent) // e.g. the series moved — occurrence ids changed
		return
	}
	c.JSON(http.StatusOK, out)
}

// DELETE /calendar/events/:id?scope=this|series
func (m Module) deleteEvent(c *gin.Context) {
	scope, ok := scopeOf(c)
	if !ok {
		return
	}
	occ, row, ok := m.occurrence(c)
	if !ok {
		return
	}
	actor := core.ActorOf(c)
	ctx := c.Request.Context()
	cal, prov, err := m.target(ctx, actor.HouseholdID, occ.CalendarID)
	if err != nil {
		fail(c, err)
		return
	}
	defer m.Syncer.lock(cal.ID)()
	series := len(row.Recurrence) > 0 && row.SeriesRemoteID == nil
	if series && scope == "this" {
		inst := InstanceID(row.RemoteID, *occ.OriginalStart, row.AllDay)
		if err := prov.Delete(ctx, cal.RemoteID, inst); err != nil {
			fail(c, err)
			return
		}
		cancelled := RemoteEvent{RemoteID: inst, Status: "cancelled", Updated: time.Now().UTC(),
			SeriesRemoteID: row.RemoteID, OriginalStart: occ.OriginalStart}
		err = core.Write(ctx, m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
			return applyRemote(tx, cal, []RemoteEvent{cancelled}, false)
		})
	} else {
		if err := prov.Delete(ctx, cal.RemoteID, row.RemoteID); err != nil {
			fail(c, err)
			return
		}
		err = core.Write(ctx, m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
			if row.SeriesRemoteID != nil { // an instance shown alone
				if err := tx.Delete(&remoteRow{}, "id = ?", row.ID).Error; err != nil {
					return err
				}
				return materialize(tx, cal, map[string]bool{row.key(): true})
			}
			return removeRemote(tx, cal, row.RemoteID)
		})
	}
	if err != nil {
		fail(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// resetExceptions drops changes of single occurrences of a series (after the
// whole series moved, they would no longer match its instances).
func (m Module) resetExceptions(c *gin.Context, cal *Calendar, prov Provider, seriesID string) error {
	ctx := c.Request.Context()
	defer m.Syncer.lock(cal.ID)()
	var exs []remoteRow
	if err := m.DB.WithContext(ctx).Where("calendar_id = ? AND series_remote_id = ?", cal.ID, seriesID).
		Find(&exs).Error; err != nil {
		return err
	}
	var gone []RemoteEvent
	for _, ex := range exs {
		if ex.Status != "cancelled" {
			if err := prov.Delete(ctx, cal.RemoteID, ex.RemoteID); err != nil {
				return err
			}
		}
		gone = append(gone, RemoteEvent{RemoteID: ex.RemoteID, Status: "cancelled", Updated: time.Now().UTC(),
			SeriesRemoteID: seriesID, OriginalStart: ex.OriginalStart})
	}
	return core.Write(ctx, m.DB, core.ActorOf(c), core.MutationID(c), func(tx *gorm.DB) error {
		return applyRemote(tx, cal, gone, false)
	})
}
