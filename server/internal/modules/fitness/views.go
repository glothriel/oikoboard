package fitness

import (
	"encoding/json"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

// ViewPrefix: every view name of this module; body data is never readable by
// delegated (OAuth/MCP) clients, see Restricted checks in the realtime hub.
const ViewPrefix = "fitness."

func (Module) Views() []core.View { return []core.View{measurementsView{}, profilesView{}} }

// fitness.measurements — all measurements of the household, newest first.
type measurementsView struct{}

func (measurementsView) Name() string                               { return ViewPrefix + "measurements" }
func (measurementsView) ParseParams(r json.RawMessage) (any, error) { return core.NoParams(r) }

func (measurementsView) Snapshot(tx *gorm.DB, hh uuid.UUID, _ any) (core.Entities, error) {
	rows := []Measurement{}
	err := tx.Where("household_id = ?", hh).Order("measured_at DESC, id").Find(&rows).Error
	return core.Entities{entityMeasurements: rows}, err
}

func (measurementsView) Matches(_ any, entity string, _ json.RawMessage) bool {
	return entity == entityMeasurements
}

// fitness.profiles — the fitness profiles of the household's members.
type profilesView struct{}

func (profilesView) Name() string                               { return ViewPrefix + "profiles" }
func (profilesView) ParseParams(r json.RawMessage) (any, error) { return core.NoParams(r) }

func (profilesView) Snapshot(tx *gorm.DB, hh uuid.UUID, _ any) (core.Entities, error) {
	rows := []Profile{}
	err := tx.Where("household_id = ?", hh).Order("created_at, id").Find(&rows).Error
	return core.Entities{entityProfiles: rows}, err
}

func (profilesView) Matches(_ any, entity string, _ json.RawMessage) bool {
	return entity == entityProfiles
}
