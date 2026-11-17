package core

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

const actorKey = "oiko.actor"

func ActorOf(c *gin.Context) Actor { return c.MustGet(actorKey).(Actor) }

func MutationID(c *gin.Context) string { return c.GetHeader("X-Mutation-Id") }

func Fail(c *gin.Context, status int, code, msg string) {
	c.AbortWithStatusJSON(status, gin.H{"error": code, "message": msg})
}

// FailErr mapuje typowe błędy bazy na kody HTTP.
func FailErr(c *gin.Context, err error) {
	switch {
	case errors.Is(err, gorm.ErrRecordNotFound):
		Fail(c, http.StatusNotFound, "not_found", "nie znaleziono")
	case errors.Is(err, gorm.ErrForeignKeyViolated):
		Fail(c, http.StatusBadRequest, "bad_reference", "odwołanie do nieistniejącego rekordu")
	case errors.Is(err, gorm.ErrCheckConstraintViolated):
		Fail(c, http.StatusBadRequest, "invalid", err.Error())
	default:
		_ = c.Error(err)
		Fail(c, http.StatusInternalServerError, "internal", "błąd serwera")
	}
}

func ParamUUID(c *gin.Context, name string) (uuid.UUID, bool) {
	id, err := uuid.Parse(c.Param(name))
	if err != nil {
		Fail(c, http.StatusBadRequest, "bad_id", "niepoprawny identyfikator")
		return uuid.Nil, false
	}
	return id, true
}

// Bind dekoduje JSON body; przy błędzie odpowiada 400 i zwraca false.
func Bind(c *gin.Context, dst any) bool {
	if err := c.ShouldBindJSON(dst); err != nil {
		Fail(c, http.StatusBadRequest, "bad_request", err.Error())
		return false
	}
	return true
}

// CheckMembers sprawdza, czy wszystkie id należą do członków gospodarstwa.
func CheckMembers(tx *gorm.DB, hh uuid.UUID, ids []uuid.UUID) error {
	if len(ids) == 0 {
		return nil
	}
	var n int64
	if err := tx.Model(&Member{}).Where("household_id = ? AND id IN ?", hh, ids).Count(&n).Error; err != nil {
		return err
	}
	if int(n) != len(uniq(ids)) {
		return gorm.ErrForeignKeyViolated
	}
	return nil
}

func uniq(ids []uuid.UUID) map[uuid.UUID]struct{} {
	m := make(map[uuid.UUID]struct{}, len(ids))
	for _, id := range ids {
		m[id] = struct{}{}
	}
	return m
}
