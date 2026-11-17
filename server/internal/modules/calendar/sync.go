package calendar

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

// Syncer pulls provider changes into the mirror. Our own writes go to the
// provider first and are applied to the mirror right away (see events.go),
// so polling only picks up changes made elsewhere. It also keeps the due-task
// events in sync with the tasks (todo_sync.go).
type Syncer struct {
	DB        *gorm.DB
	Providers *Providers
	Interval  time.Duration
	// TodoDelay debounces reconciliation after task changes.
	TodoDelay time.Duration

	locks sync.Map // calendar id (or other key) → *sync.Mutex
	todo  todoState
}

var errStale = errors.New("synced concurrently")

func (s *Syncer) lock(id uuid.UUID) func() {
	m, _ := s.locks.LoadOrStore(id, &sync.Mutex{})
	mu := m.(*sync.Mutex)
	mu.Lock()
	return mu.Unlock
}

// Run polls all calendars every Interval, then reconciles due-task events
// (fixes changes made to them elsewhere), and moves the window of
// materialized occurrences daily. Blocks until ctx is done.
func (s *Syncer) Run(ctx context.Context) {
	tick := time.NewTicker(s.Interval)
	defer tick.Stop()
	lastRefresh := time.Now()
	for {
		s.SyncAll(ctx)
		s.ReconcileAllTodos(ctx)
		if time.Since(lastRefresh) > 24*time.Hour {
			s.RefreshWindow(ctx)
			lastRefresh = time.Now()
		}
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
	}
}

func (s *Syncer) SyncAll(ctx context.Context) {
	var ids []uuid.UUID
	s.DB.WithContext(ctx).Raw(`SELECT c.id FROM calendars c
		JOIN calendar_connections cc ON cc.id = c.connection_id WHERE cc.status = 'ok'`).Scan(&ids)
	for _, id := range ids {
		cctx, cancel := context.WithTimeout(ctx, time.Minute)
		if err := s.SyncCalendar(cctx, id); err != nil {
			slog.Warn("calendar sync", "calendar", id, "err", err)
		}
		cancel()
	}
}

// SyncCalendar pulls changes of one calendar since the last sync.
func (s *Syncer) SyncCalendar(ctx context.Context, id uuid.UUID) error {
	defer s.lock(id)()
	db := s.DB.WithContext(ctx)
	var cal Calendar
	if err := db.First(&cal, "id = ?", id).Error; err != nil {
		return err
	}
	var conn Connection
	if err := db.First(&conn, "id = ?", cal.ConnectionID).Error; err != nil {
		return err
	}
	var token string
	db.Raw("SELECT sync_token FROM calendar_sync_state WHERE calendar_id = ?", id).Scan(&token)

	p, err := s.Providers.For(ctx, s.DB, conn)
	var cs ChangeSet
	if err == nil {
		cs, err = p.Changes(ctx, cal.RemoteID, token)
		if errors.Is(err, ErrSyncReset) {
			cs, err = p.Changes(ctx, cal.RemoteID, "")
		}
	}
	if err != nil {
		if errors.Is(err, ErrRevoked) {
			db.Model(&Connection{}).Where("id = ?", conn.ID).Update("status", "revoked")
		}
		s.setError(ctx, &cal, err)
		return err
	}
	err = core.Write(ctx, s.DB, core.Actor{}, "", func(tx *gorm.DB) error {
		var cur string
		if err := tx.Raw(`SELECT sync_token FROM calendar_sync_state WHERE calendar_id = ? FOR UPDATE`, id).
			Scan(&cur).Error; err != nil {
			return err
		}
		if cur != token {
			return errStale
		}
		if err := applyRemote(tx, &cal, cs.Events, cs.Full); err != nil {
			return err
		}
		if err := tx.Exec(`UPDATE calendar_sync_state SET sync_token = ?, synced_at = now() WHERE calendar_id = ?`,
			cs.Token, id).Error; err != nil {
			return err
		}
		if cal.SyncError != "" {
			return tx.Model(&Calendar{}).Where("id = ?", id).Update("sync_error", "").Error
		}
		return nil
	})
	if errors.Is(err, errStale) {
		return nil
	}
	if err != nil {
		s.setError(ctx, &cal, err)
	}
	return err
}

func (s *Syncer) setError(ctx context.Context, cal *Calendar, err error) {
	msg := "sync failed"
	if errors.Is(err, ErrRevoked) {
		msg = "access revoked — reconnect the account"
	}
	if cal.SyncError != msg {
		s.DB.WithContext(ctx).Model(&Calendar{}).Where("id = ?", cal.ID).Update("sync_error", msg)
	}
}

// RefreshWindow re-materializes all series (the window moved; member
// accounts may have changed).
func (s *Syncer) RefreshWindow(ctx context.Context) {
	var cals []Calendar
	s.DB.WithContext(ctx).Find(&cals)
	for i := range cals {
		cal := &cals[i]
		unlock := s.lock(cal.ID)
		err := core.Write(ctx, s.DB, core.Actor{}, "", func(tx *gorm.DB) error {
			var keys []string
			if err := tx.Raw(`SELECT remote_id FROM calendar_remote_events
				WHERE calendar_id = ? AND series_remote_id IS NULL`, cal.ID).Scan(&keys).Error; err != nil {
				return err
			}
			set := make(map[string]bool, len(keys))
			for _, k := range keys {
				set[k] = true
			}
			return materialize(tx, cal, set)
		})
		unlock()
		if err != nil {
			slog.Warn("calendar window refresh", "calendar", cal.ID, "err", err)
		}
	}
}
