package todo

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"oikoboard/server/internal/core"
)

const (
	entityRecurring = "todo_recurring"
	// maxRecurring is the per-household limit of templates.
	maxRecurring = 100
	// defaultCreateTime is when a task is created if the template names no time.
	defaultCreateHour = 6
)

// Recurring is a template that creates a task on every date matching its schedule.
type Recurring struct {
	ID            uuid.UUID       `json:"id" gorm:"type:uuid;primaryKey"`
	HouseholdID   uuid.UUID       `json:"household_id"`
	ListID        uuid.UUID       `json:"list_id"`
	Title         string          `json:"title"`
	Description   string          `json:"description"` // markdown
	AssigneeID    *uuid.UUID      `json:"assignee_id"`
	RRule         string          `json:"rrule" gorm:"column:rrule"`
	StartDate     core.Date       `json:"start_date"`
	EndDate       *core.Date      `json:"end_date"`
	CreateTime    core.TimeOfDay  `json:"create_time"`
	DueOffsetDays *int            `json:"due_offset_days"`
	DueTime       *core.TimeOfDay `json:"due_time"`
	Active        bool            `json:"active"`
	LastRunDate   *core.Date      `json:"last_run_date"`
	CreatedAt     time.Time       `json:"created_at"`
	UpdatedAt     time.Time       `json:"updated_at"`
	Version       int             `json:"version" gorm:"default:1"`
}

func (Recurring) TableName() string { return "todo_recurring" }

// Scheduler keeps the time-based triggers of templates in sync with the table.
// The table is the source of truth; implementations only decide when to wake
// up (see internal/recurring).
type Scheduler interface {
	// Sync creates or updates the trigger of an active template, or removes it
	// when the template is paused.
	Sync(ctx context.Context, r Recurring, loc *time.Location) error
	// Remove drops the trigger of a deleted template.
	Remove(ctx context.Context, id uuid.UUID) error
}

// LateScheduler is a Scheduler whose implementation is attached after the
// module is built (DBOS needs the database and a running process); until then
// it does nothing.
type LateScheduler struct {
	mu sync.RWMutex
	s  Scheduler
}

// Set attaches the real scheduler.
func (l *LateScheduler) Set(s Scheduler) {
	l.mu.Lock()
	l.s = s
	l.mu.Unlock()
}

func (l *LateScheduler) get() Scheduler {
	l.mu.RLock()
	defer l.mu.RUnlock()
	if l.s == nil {
		return noScheduler{}
	}
	return l.s
}

func (l *LateScheduler) Sync(ctx context.Context, r Recurring, loc *time.Location) error {
	return l.get().Sync(ctx, r, loc)
}

func (l *LateScheduler) Remove(ctx context.Context, id uuid.UUID) error {
	return l.get().Remove(ctx, id)
}

type noScheduler struct{}

func (noScheduler) Sync(context.Context, Recurring, *time.Location) error { return nil }
func (noScheduler) Remove(context.Context, uuid.UUID) error               { return nil }

func (m Module) scheduler() Scheduler {
	if m.Scheduler != nil {
		return m.Scheduler
	}
	return noScheduler{}
}

// HouseholdLocation is the timezone of a household.
func HouseholdLocation(db *gorm.DB, hh uuid.UUID) *time.Location {
	var tz string
	db.Raw("SELECT timezone FROM households WHERE id = ?", hh).Scan(&tz)
	return LoadLocation(tz)
}

// Schedule validates the template's rule in loc.
func (r Recurring) Schedule(loc *time.Location) (*Schedule, error) {
	return NewSchedule(r.RRule, r.StartDate, r.EndDate, r.CreateTime, loc)
}

// resetRunDate sets last_run_date for a new or re-scheduled template so that
// it never produces retroactive tasks: today if its creation time has passed,
// otherwise yesterday.
func resetRunDate(r *Recurring, loc *time.Location, now time.Time) {
	local := now.In(loc)
	today := core.DateOf(local)
	d := today.AddDays(-1)
	if !r.CreateTime.On(today, loc).After(local) {
		d = today
	}
	r.LastRunDate = &d
}

// Generate creates the task of template id (of household hh) for occurrence date occ, if the
// template is active and its schedule matches occ. It is idempotent: a second
// call for the same occurrence changes nothing. It always advances
// last_run_date to occ. It reports whether a task was created.
func Generate(ctx context.Context, db *gorm.DB, onChanged func(uuid.UUID), hh, id uuid.UUID, occ core.Date) (bool, error) {
	var tpl Recurring
	if err := db.WithContext(ctx).Where("household_id = ? AND id = ?", hh, id).First(&tpl).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return false, nil // deleted meanwhile
		}
		return false, err
	}
	loc := HouseholdLocation(db, tpl.HouseholdID)
	created := false
	actor := core.Actor{HouseholdID: tpl.HouseholdID}
	err := core.Write(ctx, db, actor, "", func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("household_id = ? AND id = ?", hh, id).First(&tpl).Error; err != nil {
			return err
		}
		if tpl.LastRunDate == nil || occ.After(tpl.LastRunDate.Time) {
			if err := tx.Model(&Recurring{}).Where("household_id = ? AND id = ?", hh, id).
				UpdateColumn("last_run_date", occ).Error; err != nil {
				return err
			}
		}
		if !tpl.Active {
			return nil
		}
		sch, err := tpl.Schedule(loc)
		if err != nil || !sch.Matches(occ) {
			return nil // a broken rule never creates tasks
		}
		item := Item{
			ID: uuid.New(), HouseholdID: tpl.HouseholdID, ListID: tpl.ListID,
			Title: tpl.Title, Description: tpl.Description, AssigneeID: tpl.AssigneeID,
			Position:       -float64(time.Now().UnixMicro()) / 1e6,
			RecurringID:    &tpl.ID,
			OccurrenceDate: &occ,
		}
		if tpl.DueOffsetDays != nil {
			due := occ.AddDays(*tpl.DueOffsetDays)
			item.Due, item.DueTime = &due, tpl.DueTime
		}
		res := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&item)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return nil // already generated
		}
		created = true
		return notifyGenerated(tx, actor, item)
	})
	if err == nil && created && onChanged != nil {
		onChanged(tpl.HouseholdID)
	}
	return created, err
}

// notifyGenerated tells the assignee of a generated task. There is no human
// actor, so the entry is flagged instead of naming one; mentions in the copied description are
// not announced again on every occurrence.
func notifyGenerated(tx *gorm.DB, actor core.Actor, item Item) error {
	if item.AssigneeID == nil {
		return nil
	}
	var n notices
	n.add(*item.AssigneeID, kindAssigned)
	return n.save(tx, actor, InboxEntry{ListID: item.ListID, ItemID: &item.ID, Title: item.Title, Recurring: true})
}

// CatchUp creates, for every active template of the database, the latest
// occurrence it missed since last_run_date, and nothing older, then advances
// last_run_date to the last day that is due. A failing template does not stop
// the others; the errors are joined. now is injectable for tests.
func CatchUp(ctx context.Context, db *gorm.DB, onChanged func(uuid.UUID), now time.Time) error {
	var all []Recurring
	if err := db.WithContext(ctx).Where("active").Find(&all).Error; err != nil {
		return err
	}
	var errs []error
	for _, tpl := range all {
		if err := catchUpOne(ctx, db, onChanged, tpl, now); err != nil {
			errs = append(errs, fmt.Errorf("template %s: %w", tpl.ID, err))
		}
	}
	return errors.Join(errs...)
}

func catchUpOne(ctx context.Context, db *gorm.DB, onChanged func(uuid.UUID), tpl Recurring, now time.Time) error {
	loc := HouseholdLocation(db, tpl.HouseholdID)
	sch, err := tpl.Schedule(loc)
	if err != nil {
		return nil // a broken rule never creates tasks
	}
	local := now.In(loc)
	today := core.DateOf(local)
	upTo := today
	if tpl.CreateTime.On(today, loc).After(local) {
		upTo = today.AddDays(-1) // today's creation time has not come yet
	}
	if occ, ok := sch.LatestUpTo(tpl.LastRunDate, upTo); ok {
		_, err := Generate(ctx, db, onChanged, tpl.HouseholdID, tpl.ID, occ)
		return err
	}
	if tpl.LastRunDate == nil || upTo.After(tpl.LastRunDate.Time) {
		return db.WithContext(ctx).Model(&Recurring{}).Where("household_id = ? AND id = ?", tpl.HouseholdID, tpl.ID).
			UpdateColumn("last_run_date", upTo).Error // nothing due: keep the window short
	}
	return nil
}

// --- handlers ---

type recurringReq struct {
	ListID        uuid.UUID       `json:"list_id"`
	Title         string          `json:"title"`
	Description   string          `json:"description"`
	AssigneeID    *uuid.UUID      `json:"assignee_id"`
	RRule         string          `json:"rrule"`
	StartDate     core.Date       `json:"start_date"`
	EndDate       *core.Date      `json:"end_date"`
	CreateTime    *core.TimeOfDay `json:"create_time"`
	DueOffsetDays *int            `json:"due_offset_days"`
	DueTime       *core.TimeOfDay `json:"due_time"`
	Active        *bool           `json:"active"`
}

func (m Module) createRecurring(c *gin.Context) {
	var req struct {
		ID uuid.UUID `json:"id"`
		recurringReq
	}
	if !core.Bind(c, &req) {
		return
	}
	if req.ID == uuid.Nil {
		req.ID = uuid.New()
	}
	if req.ListID == uuid.Nil || req.Title == "" || req.RRule == "" || req.StartDate.IsZero() {
		core.Fail(c, http.StatusBadRequest, "bad_request", "list_id, title, rrule and start_date are required")
		return
	}
	actor := core.ActorOf(c)
	row := Recurring{
		ID: req.ID, HouseholdID: actor.HouseholdID, ListID: req.ListID, Title: req.Title,
		Description: req.Description, AssigneeID: req.AssigneeID, RRule: req.RRule,
		StartDate: req.StartDate, EndDate: req.EndDate, CreateTime: core.TimeOfDay{Hour: defaultCreateHour},
		DueOffsetDays: req.DueOffsetDays, DueTime: req.DueTime, Active: true,
	}
	if req.CreateTime != nil {
		row.CreateTime = *req.CreateTime
	}
	if req.Active != nil {
		row.Active = *req.Active
	}
	loc := HouseholdLocation(m.DB, actor.HouseholdID)
	if msg := validateRecurring(row, loc); msg != "" {
		core.Fail(c, http.StatusBadRequest, "bad_request", msg)
		return
	}
	resetRunDate(&row, loc, time.Now())
	errLimit := errors.New("limit")
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		var n int64
		if err := tx.Model(&Recurring{}).Where("household_id = ?", actor.HouseholdID).Count(&n).Error; err != nil {
			return err
		}
		if n >= maxRecurring {
			return errLimit
		}
		if err := core.CheckMembers(tx, actor.HouseholdID, assigneeIDs(row.AssigneeID)); err != nil {
			return err
		}
		_, err := core.CreateIdempotentNew(tx, &row, actor.HouseholdID, row.ID)
		return err
	})
	if errors.Is(err, errLimit) {
		core.Fail(c, http.StatusBadRequest, "limit", "too many recurring tasks")
		return
	}
	if err == nil {
		m.syncSchedule(c.Request.Context(), row, loc)
	}
	respond(c, http.StatusCreated, &row, err)
}

func (m Module) updateRecurring(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	p, ok := core.BindPatch(c)
	if !ok {
		return
	}
	var (
		listID      uuid.UUID
		title       string
		description string
		assignee    uuid.UUID
		rule        string
		start       core.Date
		end         core.Date
		at          core.TimeOfDay
		offset      int
		dueTime     core.TimeOfDay
		active      bool
	)
	cols, err := p.Apply(map[string]any{
		"list_id": &listID, "title": &title, "description": &description, "assignee_id": &assignee,
		"rrule": &rule, "start_date": &start, "end_date": &end, "create_time": &at,
		"due_offset_days": &offset, "due_time": &dueTime, "active": &active,
	})
	if err != nil {
		core.Fail(c, http.StatusBadRequest, "bad_request", err.Error())
		return
	}
	clearToEmpty(cols, "description")
	for _, col := range []string{"list_id", "title", "rrule", "start_date", "create_time", "active"} {
		if v, ok := cols[col]; ok && v == nil {
			core.Fail(c, http.StatusBadRequest, "bad_request", col+" can't be null")
			return
		}
	}
	if v, ok := cols["due_offset_days"]; ok && v == nil {
		cols["due_time"] = nil // no offset, no time
	}
	actor := core.ActorOf(c)
	loc := HouseholdLocation(m.DB, actor.HouseholdID)
	var row Recurring
	bad := ""
	err = core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		var before Recurring
		if err := tx.Where("household_id = ? AND id = ?", actor.HouseholdID, id).First(&before).Error; err != nil {
			return err
		}
		merged := before
		if len(cols) > 0 {
			if err := applyRecurring(&merged, cols); err != nil {
				return err
			}
		}
		if bad = validateRecurring(merged, loc); bad != "" {
			return errBadRecurring
		}
		if a, ok := cols["assignee_id"]; ok && a != nil {
			if err := core.CheckMembers(tx, actor.HouseholdID, assigneeIDs(merged.AssigneeID)); err != nil {
				return err
			}
		}
		if rescheduled(before, merged) || (!before.Active && merged.Active) { // resuming skips what the pause covered
			resetRunDate(&merged, loc, time.Now())
			cols["last_run_date"] = merged.LastRunDate
		}
		return update(tx, &row, actor.HouseholdID, id, cols)
	})
	if errors.Is(err, errBadRecurring) {
		core.Fail(c, http.StatusBadRequest, "bad_request", bad)
		return
	}
	if err == nil {
		m.syncSchedule(c.Request.Context(), row, loc)
	}
	respond(c, http.StatusOK, &row, err)
}

// syncSchedule updates the trigger after the row is committed. The table is the
// source of truth, so a failure is logged and healed by the next Reconcile
// instead of failing a request whose data was saved.
func (m Module) syncSchedule(ctx context.Context, r Recurring, loc *time.Location) {
	if err := m.scheduler().Sync(ctx, r, loc); err != nil {
		slog.Warn("recurring: syncing the schedule failed; the next reconcile fixes it", "template", r.ID, "err", err)
	}
}

func (m Module) deleteRecurring(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	actor := core.ActorOf(c)
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		res := tx.Where("household_id = ? AND id = ?", actor.HouseholdID, id).Delete(&Recurring{})
		if res.Error == nil && res.RowsAffected == 0 {
			return gorm.ErrRecordNotFound
		}
		return res.Error
	})
	if err != nil {
		core.FailErr(c, err)
		return
	}
	if err := m.scheduler().Remove(c.Request.Context(), id); err != nil {
		slog.Warn("recurring: removing the schedule failed; the next reconcile fixes it", "template", id, "err", err)
	}
	c.Status(http.StatusNoContent)
}

// previewRecurring: the next occurrence dates of a rule, for the editor.
func (m Module) previewRecurring(c *gin.Context) {
	var req struct {
		RRule     string     `json:"rrule"`
		StartDate core.Date  `json:"start_date"`
		EndDate   *core.Date `json:"end_date"`
		Count     int        `json:"count"`
	}
	if !core.Bind(c, &req) {
		return
	}
	if req.StartDate.IsZero() {
		core.Fail(c, http.StatusBadRequest, "bad_request", "start_date is required")
		return
	}
	if req.Count == 0 {
		req.Count = 5
	}
	if req.Count < 0 || req.Count > 20 {
		core.Fail(c, http.StatusBadRequest, "bad_request", "count must be between 1 and 20")
		return
	}
	actor := core.ActorOf(c)
	loc := HouseholdLocation(m.DB, actor.HouseholdID)
	sch, err := NewSchedule(req.RRule, req.StartDate, req.EndDate, core.TimeOfDay{Hour: defaultCreateHour}, loc)
	if err != nil {
		core.Fail(c, http.StatusBadRequest, "bad_request", err.Error())
		return
	}
	today := LocalDate(time.Now(), loc)
	c.JSON(http.StatusOK, gin.H{"dates": sch.Next(today, req.Count)})
}

var errBadRecurring = errors.New("invalid template")

func assigneeIDs(id *uuid.UUID) []uuid.UUID {
	if id == nil {
		return nil
	}
	return []uuid.UUID{*id}
}

// validateRecurring returns a message for an invalid template, "" when valid.
func validateRecurring(r Recurring, loc *time.Location) string {
	if r.Title == "" {
		return "title is empty"
	}
	if r.DueTime != nil && r.DueOffsetDays == nil {
		return "due_time needs due_offset_days"
	}
	if r.DueOffsetDays != nil && (*r.DueOffsetDays < 0 || *r.DueOffsetDays > 366) {
		return "due_offset_days must be between 0 and 366"
	}
	if _, err := r.Schedule(loc); err != nil {
		return err.Error()
	}
	return ""
}

// rescheduled: did the schedule itself change (not just the task fields)?
func rescheduled(a, b Recurring) bool {
	sameEnd := (a.EndDate == nil) == (b.EndDate == nil) && (a.EndDate == nil || a.EndDate.Equal(b.EndDate.Time))
	return a.RRule != b.RRule || !a.StartDate.Equal(b.StartDate.Time) || a.CreateTime != b.CreateTime || !sameEnd
}

// applyRecurring copies patched columns onto r (to validate the result).
func applyRecurring(r *Recurring, cols map[string]any) error {
	raw, err := json.Marshal(cols)
	if err != nil {
		return err
	}
	var patch recurringReq
	var all map[string]json.RawMessage
	if err := json.Unmarshal(raw, &all); err != nil {
		return err
	}
	if err := json.Unmarshal(raw, &patch); err != nil {
		return err
	}
	set := func(k string) bool { _, ok := all[k]; return ok }
	if set("list_id") {
		r.ListID = patch.ListID
	}
	if set("title") {
		r.Title = patch.Title
	}
	if set("description") {
		r.Description = patch.Description
	}
	if set("assignee_id") {
		r.AssigneeID = patch.AssigneeID
	}
	if set("rrule") {
		r.RRule = patch.RRule
	}
	if set("start_date") {
		r.StartDate = patch.StartDate
	}
	if set("end_date") {
		r.EndDate = patch.EndDate
	}
	if set("create_time") && patch.CreateTime != nil {
		r.CreateTime = *patch.CreateTime
	}
	if set("due_offset_days") {
		r.DueOffsetDays = patch.DueOffsetDays
	}
	if set("due_time") {
		r.DueTime = patch.DueTime
	}
	if set("active") && patch.Active != nil {
		r.Active = *patch.Active
	}
	return nil
}

// --- view ---

// todo.recurring — all templates of the household (editor drawers).
type recurringView struct{}

func (recurringView) Name() string                               { return "todo.recurring" }
func (recurringView) ParseParams(r json.RawMessage) (any, error) { return core.NoParams(r) }

func (recurringView) Snapshot(tx *gorm.DB, hh uuid.UUID, _ any) (core.Entities, error) {
	rows := []Recurring{}
	err := tx.Where("household_id = ?", hh).Order("created_at, id").Find(&rows).Error
	return core.Entities{entityRecurring: rows}, err
}

func (recurringView) Matches(_ any, entity string, _ json.RawMessage) bool {
	return entity == entityRecurring
}
