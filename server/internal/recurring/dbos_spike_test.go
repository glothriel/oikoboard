//go:build dbos

package recurring

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dbos-inc/dbos-transact-golang/dbos"

	"oikoboard/server/internal/core"
)

// Spike: DBOS database-backed schedules can be created, applied and deleted
// after Launch, fire in a timezone, and are stored in Postgres. Run with
// `go test -tags dbos ./internal/recurring/`.
func TestDBOSSchedulesSpike(t *testing.T) {
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

	ctx, err := dbos.NewContext(context.Background(), dbos.Config{AppName: "oikoboard-test", DatabaseURL: u.String(),
		SchedulerPollingInterval: 300 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	var fired atomic.Int32
	wf := func(_ dbos.Context, in dbos.ScheduledWorkflowInput) (any, error) {
		fired.Add(1)
		return nil, nil
	}
	dbos.RegisterWorkflow(ctx, wf)
	if err := dbos.Launch(ctx); err != nil {
		t.Fatal(err)
	}
	defer dbos.Shutdown(ctx, 10*time.Second)

	spec := dbos.ScheduleSpec{ScheduleName: "recurring-test", Schedule: "* * * * * *",
		Workflow: wf, CronTimezone: "Europe/Warsaw"}
	if err := dbos.CreateSchedule(ctx, spec); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return fired.Load() > 0 }, "schedule fires")

	// idempotent re-apply (the boot reconcile)
	if err := dbos.ApplySchedules(ctx, []dbos.ScheduleSpec{spec}); err != nil {
		t.Fatal(err)
	}

	if err := dbos.DeleteSchedule(ctx, "recurring-test"); err != nil {
		t.Fatal(err)
	}
	time.Sleep(1500 * time.Millisecond) // the reconciler (polling interval) drops the entry
	n := fired.Load()
	time.Sleep(2500 * time.Millisecond)
	if fired.Load() > n+1 {
		t.Fatalf("schedule kept firing after DeleteSchedule: %d -> %d", n, fired.Load())
	}
}

func waitFor(t *testing.T, ok func() bool, what string) {
	t.Helper()
	for end := time.Now().Add(45 * time.Second); time.Now().Before(end); time.Sleep(200 * time.Millisecond) {
		if ok() {
			return
		}
	}
	t.Fatalf("timeout: %s", what)
}
