package core

import (
	"encoding/json"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

// Members is the cross-cutting module that publishes the household's members
// (the family) as the family.members view.
type Members struct{ DB *gorm.DB }

func (Members) Name() string            { return "members" }
func (Members) Routes(*gin.RouterGroup) {}
func (Members) Views() []View           { return []View{membersView{}} }

// membersView — all members of the household, in public form (no user_id or
// invite_email, has_account instead).
type membersView struct{}

func (membersView) Name() string                               { return "family.members" }
func (membersView) ParseParams(r json.RawMessage) (any, error) { return NoParams(r) }

func (membersView) Snapshot(tx *gorm.DB, hh uuid.UUID, _ any) (Entities, error) {
	rows := []memberOut{}
	err := tx.Raw(`SELECT id, household_id, name, color, created_at, picture, user_id IS NOT NULL AS has_account
		FROM members WHERE household_id = ? ORDER BY created_at, id`, hh).Scan(&rows).Error
	return Entities{"members": rows}, err
}

func (membersView) Matches(_ any, entity string, _ json.RawMessage) bool { return entity == "members" }

// Project sanitizes a raw members row from the change feed to the public shape.
func (membersView) Project(entity string, row json.RawMessage) json.RawMessage {
	if entity != "members" || row == nil {
		return row
	}
	var m map[string]json.RawMessage
	if json.Unmarshal(row, &m) != nil {
		return nil
	}
	uid := m["user_id"]
	m["has_account"] = json.RawMessage("false")
	if len(uid) > 0 && string(uid) != "null" {
		m["has_account"] = json.RawMessage("true")
	}
	delete(m, "user_id")
	delete(m, "invite_email")
	out, err := json.Marshal(m)
	if err != nil {
		return nil
	}
	return out
}
