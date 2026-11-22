package todo

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"oikoboard/server/internal/core"
)

// GET /todo/search?q= — lists and tasks whose name/title or description
// contains q; open tasks first, then the most recently changed.
func (m Module) search(c *gin.Context) {
	lists, items := []List{}, []Item{}
	q := strings.TrimSpace(c.Query("q"))
	if q != "" {
		hh := core.ActorOf(c).HouseholdID
		pat := core.LikePattern(q)
		db := m.DB.WithContext(c.Request.Context())
		err := db.Where("household_id = ? AND (name ILIKE ? OR description ILIKE ?)", hh, pat, pat).
			Order("name").Limit(20).Find(&lists).Error
		if err == nil {
			err = db.Where("household_id = ? AND (title ILIKE ? OR description ILIKE ?)", hh, pat, pat).
				Order("done, updated_at DESC").Limit(30).Find(&items).Error
		}
		if err != nil {
			core.FailErr(c, err)
			return
		}
	}
	c.JSON(http.StatusOK, gin.H{"lists": lists, "items": items})
}
