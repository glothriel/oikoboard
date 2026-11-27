// Package fitness: body measurements (weight and composition) and the
// per-member profile used to compute composition on the device.
package fitness

import (
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"oikoboard/server/internal/core"
)

// Measurement is one weigh-in. Composition columns are null when the scale gave
// no impedance or the member has no profile.
type Measurement struct {
	ID          uuid.UUID `json:"id" gorm:"type:uuid;primaryKey"`
	HouseholdID uuid.UUID `json:"household_id"`
	MemberID    uuid.UUID `json:"member_id"`
	MeasuredAt  time.Time `json:"measured_at"`
	WeightKg    float64   `json:"weight_kg"`
	Impedance   *int      `json:"impedance"`
	LbmKg       *float64  `json:"lbm_kg"`
	FatPct      *float64  `json:"fat_pct"`
	WaterPct    *float64  `json:"water_pct"`
	ProteinPct  *float64  `json:"protein_pct"`
	BoneKg      *float64  `json:"bone_kg"`
	MuscleKg    *float64  `json:"muscle_kg"`
	BmrKcal     *float64  `json:"bmr_kcal"`
	VisceralFat *float64  `json:"visceral_fat"`
	Bmi         *float64  `json:"bmi"`
	Source      string    `json:"source"` // scale | manual
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	Version     int       `json:"version" gorm:"default:1"`
}

func (Measurement) TableName() string { return "measurements" }

// Profile is a member's data for the composition formulas; ID is the member id.
type Profile struct {
	ID          uuid.UUID `json:"id" gorm:"type:uuid;primaryKey"`
	HouseholdID uuid.UUID `json:"household_id"`
	Sex         string    `json:"sex"` // male | female
	BirthDate   core.Date `json:"birth_date"`
	HeightCm    float64   `json:"height_cm"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	Version     int       `json:"version" gorm:"default:1"`
}

func (Profile) TableName() string { return "fitness_profiles" }

const (
	entityMeasurements = "measurements"
	entityProfiles     = "fitness_profiles"
)

type Module struct {
	DB *gorm.DB
}

func (Module) Name() string { return "fitness" }

func (m Module) Routes(r *gin.RouterGroup) {
	r.POST("/fitness/measurements", m.createMeasurement)
	r.DELETE("/fitness/measurements/:id", m.deleteMeasurement)
	r.POST("/fitness/profiles", m.upsertProfile)
}

func invalid(c *gin.Context, msg string) {
	core.Fail(c, http.StatusBadRequest, "invalid", msg)
}

// inRange: nil is fine (optional value), otherwise lo <= v <= hi.
func inRange(v *float64, lo, hi float64) bool { return v == nil || (*v >= lo && *v <= hi) }

func (m Module) createMeasurement(c *gin.Context) {
	var req struct {
		ID          uuid.UUID `json:"id"`
		MemberID    uuid.UUID `json:"member_id" binding:"required"`
		MeasuredAt  time.Time `json:"measured_at" binding:"required"`
		WeightKg    float64   `json:"weight_kg"`
		Impedance   *int      `json:"impedance"`
		LbmKg       *float64  `json:"lbm_kg"`
		FatPct      *float64  `json:"fat_pct"`
		WaterPct    *float64  `json:"water_pct"`
		ProteinPct  *float64  `json:"protein_pct"`
		BoneKg      *float64  `json:"bone_kg"`
		MuscleKg    *float64  `json:"muscle_kg"`
		BmrKcal     *float64  `json:"bmr_kcal"`
		VisceralFat *float64  `json:"visceral_fat"`
		Bmi         *float64  `json:"bmi"`
		Source      string    `json:"source" binding:"required"`
	}
	if !core.Bind(c, &req) {
		return
	}
	switch {
	case req.WeightKg < 2 || req.WeightKg > 500:
		invalid(c, "weight_kg must be between 2 and 500")
		return
	case req.Source != "scale" && req.Source != "manual":
		invalid(c, "source must be scale or manual")
		return
	case req.Impedance != nil && (*req.Impedance < 0 || *req.Impedance > 100000):
		invalid(c, "impedance is out of range")
		return
	case !inRange(req.FatPct, 0, 100) || !inRange(req.WaterPct, 0, 100) || !inRange(req.ProteinPct, 0, 100):
		invalid(c, "percentages must be between 0 and 100")
		return
	case !inRange(req.LbmKg, 0, 500) || !inRange(req.BoneKg, 0, 500) || !inRange(req.MuscleKg, 0, 500):
		invalid(c, "composition masses must be between 0 and 500 kg")
		return
	case !inRange(req.BmrKcal, 0, 10000) || !inRange(req.VisceralFat, 0, 100) || !inRange(req.Bmi, 0, 200):
		invalid(c, "composition values are out of range")
		return
	}
	if req.ID == uuid.Nil {
		req.ID = uuid.New()
	}
	actor := core.ActorOf(c)
	row := Measurement{ID: req.ID, HouseholdID: actor.HouseholdID, MemberID: req.MemberID,
		MeasuredAt: req.MeasuredAt, WeightKg: req.WeightKg, Impedance: req.Impedance,
		LbmKg: req.LbmKg, FatPct: req.FatPct, WaterPct: req.WaterPct, ProteinPct: req.ProteinPct,
		BoneKg: req.BoneKg, MuscleKg: req.MuscleKg, BmrKcal: req.BmrKcal,
		VisceralFat: req.VisceralFat, Bmi: req.Bmi, Source: req.Source}
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		if err := core.CheckMembers(tx, actor.HouseholdID, []uuid.UUID{req.MemberID}); err != nil {
			return err
		}
		_, err := core.CreateIdempotentNew(tx, &row, actor.HouseholdID, row.ID)
		return err
	})
	respond(c, http.StatusCreated, &row, err)
}

func (m Module) deleteMeasurement(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	actor := core.ActorOf(c)
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		res := tx.Where("household_id = ? AND id = ?", actor.HouseholdID, id).Delete(&Measurement{})
		if res.Error == nil && res.RowsAffected == 0 {
			return gorm.ErrRecordNotFound
		}
		return res.Error
	})
	if err != nil {
		core.FailErr(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// upsertProfile writes the caller's own profile (the id is the member id).
func (m Module) upsertProfile(c *gin.Context) {
	var req struct {
		Sex       string    `json:"sex"`
		BirthDate core.Date `json:"birth_date"`
		HeightCm  float64   `json:"height_cm"`
	}
	if !core.Bind(c, &req) {
		return
	}
	actor := core.ActorOf(c)
	if actor.MemberID == uuid.Nil {
		core.Fail(c, http.StatusForbidden, "forbidden", "select a household member first")
		return
	}
	now := time.Now()
	switch {
	case req.Sex != "male" && req.Sex != "female":
		invalid(c, "sex must be male or female")
		return
	case req.BirthDate.IsZero() || req.BirthDate.After(now) || req.BirthDate.Year() < 1900:
		invalid(c, "birth_date must be a past date")
		return
	case req.HeightCm < 50 || req.HeightCm > 260:
		invalid(c, "height_cm must be between 50 and 260")
		return
	}
	row := Profile{ID: actor.MemberID, HouseholdID: actor.HouseholdID,
		Sex: req.Sex, BirthDate: req.BirthDate, HeightCm: req.HeightCm}
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "id"}},
			DoUpdates: clause.AssignmentColumns([]string{"sex", "birth_date", "height_cm"}),
			Where:     clause.Where{Exprs: []clause.Expression{clause.Expr{SQL: "fitness_profiles.household_id = ?", Vars: []any{actor.HouseholdID}}}},
		}).Create(&row).Error; err != nil {
			return err
		}
		return tx.Where("household_id = ? AND id = ?", actor.HouseholdID, row.ID).First(&row).Error
	})
	respond(c, http.StatusOK, &row, err)
}

func respond(c *gin.Context, status int, row any, err error) {
	switch {
	case errors.Is(err, core.ErrIDConflict):
		core.Fail(c, http.StatusConflict, "id_conflict", "the id is already taken")
	case err != nil:
		core.FailErr(c, err)
	default:
		c.JSON(status, row)
	}
}
