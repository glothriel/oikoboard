package calendar

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"oikoboard/server/internal/core"
)

// GET /calendar/search?q= — events whose title, description or location
// contains q. A series is one hit: its next occurrence (or, if it's over,
// its last). Upcoming events first, soonest first; then past, latest first.
// Due-task days are left out (the tasks themselves are searchable).
func (m Module) search(c *gin.Context) {
	events := []Event{}
	q := strings.TrimSpace(c.Query("q"))
	if q != "" {
		pat := core.LikePattern(q)
		const order = `ends_at < now(), CASE WHEN ends_at >= now() THEN starts_at END, starts_at DESC`
		err := m.DB.WithContext(c.Request.Context()).Raw(`
SELECT * FROM (
  SELECT DISTINCT ON (event_id) * FROM calendar_events
  WHERE household_id = ? AND kind = '' AND (title ILIKE ? OR description ILIKE ? OR location ILIKE ?)
  ORDER BY event_id, `+order+`
) e ORDER BY `+order+` LIMIT 30`,
			core.ActorOf(c).HouseholdID, pat, pat, pat).Scan(&events).Error
		if err != nil {
			core.FailErr(c, err)
			return
		}
	}
	c.JSON(http.StatusOK, gin.H{"events": events})
}
