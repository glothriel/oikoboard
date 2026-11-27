package todo

import (
	"context"
	"log/slog"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

// CleanupDone deletes tasks completed more than days days ago, unless marked
// keep_forever. Comments, attachments and inbox entries go with them via
// ON DELETE CASCADE; clients learn through the change feed. days <= 0 is a
// no-op. onChanged is called for each affected household (may be nil).
func CleanupDone(ctx context.Context, db *gorm.DB, days int, onChanged func(uuid.UUID)) error {
	if days <= 0 {
		return nil
	}
	var households []uuid.UUID
	err := core.Write(ctx, db, core.Actor{}, "", func(tx *gorm.DB) error {
		const cond = "done AND NOT keep_forever AND done_at < now() - make_interval(days => ?)"
		if err := tx.Raw("SELECT DISTINCT household_id FROM todo_items WHERE "+cond, days).
			Scan(&households).Error; err != nil {
			return err
		}
		if len(households) == 0 {
			return nil
		}
		return tx.Exec("DELETE FROM todo_items WHERE "+cond, days).Error
	})
	if err != nil {
		return err
	}
	if len(households) > 0 {
		slog.Info("completed tasks cleaned up", "households", len(households), "days", days)
	}
	if onChanged != nil {
		for _, hh := range households {
			onChanged(hh)
		}
	}
	return nil
}
