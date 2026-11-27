// Package recurring runs the triggers of recurring task templates on DBOS
// (durable, database-backed schedules). The todo_recurring table stays the
// source of truth: a schedule only decides when to wake up, todo.Generate
// decides whether an occurrence exists and creates the task idempotently.
package recurring

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/dbos-inc/dbos-transact-golang/dbos"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/modules/todo"
)

const schedulePrefix = "recurring-"

// pollInterval is how often DBOS re-reads the schedule table, i.e. how long an
// edit made on another instance takes to reach this one.
const pollInterval = 5 * time.Second

type scheduleContext struct {
	HouseholdID uuid.UUID `json:"household_id"`
	TemplateID  uuid.UUID `json:"template_id"`
}

// DBOS implements todo.Scheduler on top of DBOS schedules.
type DBOS struct {
	ctx       dbos.Context
	db        *gorm.DB
	onChanged func(uuid.UUID)
	workflow  func(dbos.Context, dbos.ScheduledWorkflowInput) (any, error)
	cleanup   func(context.Context) error
	cleanupWF func(dbos.Context, dbos.ScheduledWorkflowInput) (any, error)
}

const cleanupSchedule = "cleanup-done-tasks"

var _ todo.Scheduler = (*DBOS)(nil)

// New starts DBOS against dsn (its state lives in the "dbos" schema of that
// database). onChanged is called after a task was created (may be nil).
// cleanup is the daily completed-task cleanup (nil = none).
func New(parent context.Context, db *gorm.DB, dsn string, onChanged func(uuid.UUID), cleanup func(context.Context) error) (*DBOS, error) {
	ctx, err := dbos.NewContext(parent, dbos.Config{
		AppName:                  "oikoboard",
		DatabaseURL:              dsn,
		SchedulerPollingInterval: pollInterval,
	})
	if err != nil {
		return nil, fmt.Errorf("dbos: %w", err)
	}
	d := &DBOS{ctx: ctx, db: db, onChanged: onChanged, cleanup: cleanup}
	d.workflow = d.run
	d.cleanupWF = d.cleanupWorkflow
	dbos.RegisterWorkflow(ctx, d.cleanupWF, dbos.WithWorkflowName(cleanupSchedule))
	dbos.RegisterWorkflow(ctx, d.workflow, dbos.WithWorkflowName("generate-recurring-task"))
	if err := dbos.Launch(ctx); err != nil {
		return nil, fmt.Errorf("dbos launch: %w", err)
	}
	return d, nil
}

// Shutdown stops DBOS gracefully.
func (d *DBOS) Shutdown(timeout time.Duration) error { return dbos.Shutdown(d.ctx, timeout) }

// run is the scheduled workflow: derive the local date of the tick and let
// todo.Generate do the rest (a durable step, retried on failure).
func (d *DBOS) run(ctx dbos.Context, in dbos.ScheduledWorkflowInput) (any, error) {
	sc, err := dbos.DecodeScheduleContext[scheduleContext](in)
	if err != nil {
		return nil, err
	}
	_, err = dbos.RunAsStep(ctx, func(c context.Context) (bool, error) {
		occ := todo.LocalDate(in.ScheduledTime, todo.HouseholdLocation(d.db, sc.HouseholdID))
		return todo.Generate(c, d.db, d.onChanged, sc.HouseholdID, sc.TemplateID, occ)
	}, dbos.WithStepName("generate"))
	return nil, err
}

// cleanupWorkflow is the daily completed-task cleanup (a durable, retried step).
func (d *DBOS) cleanupWorkflow(ctx dbos.Context, _ dbos.ScheduledWorkflowInput) (any, error) {
	_, err := dbos.RunAsStep(ctx, func(c context.Context) (bool, error) {
		if d.cleanup == nil {
			return false, nil
		}
		return true, d.cleanup(c)
	}, dbos.WithStepName("cleanup"))
	return nil, err
}

// SyncCleanup schedules the daily cleanup (03:00 UTC) or removes the schedule.
func (d *DBOS) SyncCleanup(enabled bool) error {
	if enabled {
		return dbos.ApplySchedules(d.ctx, []dbos.ScheduleSpec{{
			ScheduleName: cleanupSchedule,
			Schedule:     "0 0 3 * * *",
			CronTimezone: "UTC",
			Workflow:     d.cleanupWF,
		}})
	}
	if err := dbos.DeleteSchedule(d.ctx, cleanupSchedule); err != nil && !isNotFound(err) {
		return err
	}
	return nil
}

func scheduleName(id uuid.UUID) string { return schedulePrefix + id.String() }

func (d *DBOS) spec(r todo.Recurring, loc *time.Location) dbos.ScheduleSpec {
	return dbos.ScheduleSpec{
		ScheduleName: scheduleName(r.ID),
		// seconds minutes hours: a daily tick at the template's creation time
		Schedule:     fmt.Sprintf("0 %d %d * * *", r.CreateTime.Minute, r.CreateTime.Hour),
		CronTimezone: loc.String(),
		Workflow:     d.workflow,
		Context:      scheduleContext{HouseholdID: r.HouseholdID, TemplateID: r.ID},
	}
}

// Sync creates or updates the schedule of an active template and removes the
// schedule of a paused one.
func (d *DBOS) Sync(_ context.Context, r todo.Recurring, loc *time.Location) error {
	if !r.Active {
		return d.Remove(context.Background(), r.ID)
	}
	return dbos.ApplySchedules(d.ctx, []dbos.ScheduleSpec{d.spec(r, loc)})
}

// Remove deletes the schedule of a template; a missing schedule is fine.
func (d *DBOS) Remove(_ context.Context, id uuid.UUID) error {
	err := dbos.DeleteSchedule(d.ctx, scheduleName(id))
	if err != nil && !isNotFound(err) {
		return err
	}
	return nil
}

func isNotFound(err error) bool {
	return err != nil && strings.Contains(strings.ToLower(err.Error()), "not found")
}

// Reconcile makes the schedules match the table: every active template has
// one, schedules of deleted or paused templates are removed. Call it at boot.
func (d *DBOS) Reconcile(ctx context.Context) error {
	var tpls []todo.Recurring
	if err := d.db.WithContext(ctx).Where("active").Find(&tpls).Error; err != nil {
		return err
	}
	want := map[string]bool{}
	var specs []dbos.ScheduleSpec
	for _, t := range tpls {
		want[scheduleName(t.ID)] = true
		specs = append(specs, d.spec(t, todo.HouseholdLocation(d.db, t.HouseholdID)))
	}
	if len(specs) > 0 {
		if err := dbos.ApplySchedules(d.ctx, specs); err != nil {
			return err
		}
	}
	existing, err := dbos.ListSchedules(d.ctx, dbos.WithScheduleNamePrefixes(schedulePrefix))
	if err != nil {
		return err
	}
	var errs []error
	for _, s := range existing {
		if !want[s.ScheduleName] {
			if err := dbos.DeleteSchedule(d.ctx, s.ScheduleName); err != nil && !isNotFound(err) {
				errs = append(errs, err)
			}
		}
	}
	slog.Info("recurring tasks: schedules reconciled", "active", len(specs), "orphans_removed", len(existing)-countWanted(existing, want))
	return errors.Join(errs...)
}

func countWanted(existing []dbos.WorkflowSchedule, want map[string]bool) int {
	n := 0
	for _, s := range existing {
		if want[s.ScheduleName] {
			n++
		}
	}
	return n
}
