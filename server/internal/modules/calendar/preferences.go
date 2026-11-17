package calendar

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"oikoboard/server/internal/core"
)

// Preferences are the signed-in member's calendar settings.
type Preferences struct {
	View string `json:"view"`
}

var views = map[string]bool{"day": true, "3days": true, "week": true, "month": true}

func (m Module) getPreferences(c *gin.Context) {
	p := Preferences{View: "month"}
	err := m.DB.WithContext(c.Request.Context()).Table("calendar_preferences").Select("view").
		Where("member_id = ?", core.ActorOf(c).MemberID).Limit(1).Scan(&p).Error
	if err != nil {
		core.FailErr(c, err)
		return
	}
	c.JSON(http.StatusOK, p)
}

func (m Module) updatePreferences(c *gin.Context) {
	var p Preferences
	if !core.Bind(c, &p) {
		return
	}
	if !views[p.View] {
		core.Fail(c, http.StatusBadRequest, "bad_request", "view must be day, 3days, week or month")
		return
	}
	a := core.ActorOf(c)
	err := m.DB.WithContext(c.Request.Context()).Exec(`
		INSERT INTO calendar_preferences (member_id, household_id, view) VALUES (?, ?, ?)
		ON CONFLICT (member_id) DO UPDATE SET view = EXCLUDED.view, updated_at = now()`,
		a.MemberID, a.HouseholdID, p.View).Error
	if err != nil {
		core.FailErr(c, err)
		return
	}
	c.JSON(http.StatusOK, p)
}
