package core

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/pressly/goose/v3"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"oikoboard/server/migrations"
)

func OpenDB(dsn string) (*gorm.DB, error) {
	return gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger:         logger.Default.LogMode(logger.Warn),
		TranslateError: true,
	})
}

func Migrate(db *gorm.DB) error {
	sqlDB, err := db.DB()
	if err != nil {
		return err
	}
	goose.SetBaseFS(migrations.FS)
	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}
	return goose.Up(sqlDB, ".")
}

// Actor is the signed-in account and (if any) its selected family member.
// Household data endpoints (modules, views, WS) require HouseholdID.
type Actor struct {
	UserID      uuid.UUID
	MemberID    uuid.UUID
	HouseholdID uuid.UUID
	// Delegated: a member acting through an OAuth client (e.g. ChatGPT);
	// limited to module data (ToolAllowed).
	Delegated bool
}

// Restricted: an OAuth client, not the app.
func (a Actor) Restricted() bool { return a.Delegated }

func (a Actor) InHousehold() bool { return a.HouseholdID != uuid.Nil }

// Write runs a write in a transaction, recording who makes the change and as
// part of which client operation — the oiko_capture trigger stores both in changes.
func Write(ctx context.Context, db *gorm.DB, actor Actor, mutationID string, fn func(tx *gorm.DB) error) error {
	if _, err := uuid.Parse(mutationID); err != nil {
		mutationID = ""
	}
	actorID := "" // background writes (e.g. calendar sync) have no actor
	if actor.MemberID != uuid.Nil {
		actorID = actor.MemberID.String()
	}
	return db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		err := tx.Exec(
			"SELECT set_config('oiko.actor', ?, true), set_config('oiko.mutation', ?, true)",
			actorID, mutationID,
		).Error
		if err != nil {
			return fmt.Errorf("set_config: %w", err)
		}
		return fn(tx)
	})
}
