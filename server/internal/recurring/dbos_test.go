//go:build dbos

package recurring

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/dbos-inc/dbos-transact-golang/dbos"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
	"oikoboard/server/internal/modules/todo"
	"oikoboard/server/internal/seed"
)

func testDB(t *testing.T) (*gorm.DB, string) {
	t.Helper()
	admin := os.Getenv("OIKO_TEST_DATABASE_URL")
	if admin == "" {
		admin = "postgres://oiko:oiko@localhost:5433/oiko?sslmode=disable"
	}
	adb, err := core.OpenDB(admin)
	if err != nil || adb.Exec("SELECT 1").Error != nil {
		t.Skip("no Postgres")
	}
	name := fmt.Sprintf("oiko_dbos_%d", time.Now().UnixNano())
	if err := adb.Exec("CREATE DATABASE " + name).Error; err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { adb.Exec("DROP DATABASE IF EXISTS " + name + " WITH (FORCE)") })
	u, _ := url.Parse(admin)
	u.Path = "/" + name
	db, err := core.OpenDB(u.String())
	if err != nil {
		t.Fatal(err)
	}
	if err := core.Migrate(db); err != nil {
		t.Fatal(err)
	}
	return db, u.String()
}

// End to end on a real DBOS: Sync/Remove/Reconcile keep the schedules in line
// with the table, and a tick creates the task exactly once.
func TestDBOSScheduler(t *testing.T) {
	db, dsn := testDB(t)
	ctx := context.Background()
	if err := seed.Family(ctx, db, "Kowalscy"); err != nil {
		t.Fatal(err)
	}
	var hhs, lists []uuid.UUID
	db.Raw("SELECT id FROM households LIMIT 1").Scan(&hhs)
	db.Raw("SELECT id FROM todo_lists WHERE household_id = ? LIMIT 1", hhs[0]).Scan(&lists)
	hh, list := hhs[0], lists[0]
	loc := todo.HouseholdLocation(db, hh)

	d, err := New(ctx, db, dsn, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer d.Shutdown(10 * time.Second)

	// a template whose creation time is the coming minute
	fire := time.Now().In(loc).Truncate(time.Minute).Add(time.Minute)
	if fire.Sub(time.Now()) < 10*time.Second {
		fire = fire.Add(time.Minute)
	}
	rec := todo.Recurring{
		ID: uuid.New(), HouseholdID: hh, ListID: list, Title: "Tick", RRule: "FREQ=DAILY",
		StartDate: core.DateOf(fire).AddDays(-1), CreateTime: core.TimeOfDay{Hour: fire.Hour(), Minute: fire.Minute()},
		Active: true,
	}
	if err := db.Create(&rec).Error; err != nil {
		t.Fatal(err)
	}

	// Reconcile creates the schedule for the active template and drops orphans
	orphan := todo.Recurring{ID: uuid.New()}
	if err := dbos.CreateSchedule(d.ctx, d.spec(todo.Recurring{ID: orphan.ID, CreateTime: core.TimeOfDay{Hour: 5}}, loc)); err != nil {
		t.Fatal(err)
	}
	if err := d.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := dbos.GetSchedule(d.ctx, scheduleName(rec.ID)); err != nil {
		t.Fatalf("schedule of the template: %v", err)
	}
	if _, err := dbos.GetSchedule(d.ctx, scheduleName(orphan.ID)); err == nil {
		t.Fatal("orphan schedule must be removed")
	}

	// the tick creates the task once
	deadline := time.Now().Add(fire.Sub(time.Now()) + 40*time.Second)
	var n int64
	for time.Now().Before(deadline) {
		db.Model(&todo.Item{}).Where("recurring_id = ?", rec.ID).Count(&n)
		if n > 0 {
			break
		}
		time.Sleep(500 * time.Millisecond)
	}
	if n != 1 {
		t.Fatalf("expected 1 generated task after the tick, got %d", n)
	}

	// pausing removes the schedule; Remove is idempotent
	rec.Active = false
	if err := d.Sync(ctx, rec, loc); err != nil {
		t.Fatal(err)
	}
	if _, err := dbos.GetSchedule(d.ctx, scheduleName(rec.ID)); err == nil {
		t.Fatal("paused template must have no schedule")
	}
	if err := d.Remove(ctx, rec.ID); err != nil {
		t.Fatal(err)
	}
}
