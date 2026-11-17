// Package calendar: the family calendar — a mirror of external calendars
// (Google; CalDAV later) with two-way sync. See docs/calendar.md.
package calendar

import (
	"encoding/json"
	"errors"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

// Event is one occurrence (a single event, or one instance of a series).
type Event struct {
	ID            uuid.UUID        `json:"id" gorm:"type:uuid;primaryKey"`
	HouseholdID   uuid.UUID        `json:"household_id"`
	CalendarID    uuid.UUID        `json:"calendar_id"`
	EventID       uuid.UUID        `json:"event_id"`
	Title         string           `json:"title"`
	Description   string           `json:"description"`
	Location      string           `json:"location"`
	StartsAt      time.Time        `json:"starts_at"`
	EndsAt        time.Time        `json:"ends_at"`
	AllDay        bool             `json:"all_day"`
	MemberIDs     core.UUIDArray   `json:"member_ids" gorm:"type:uuid[]"`
	Recurrence    core.JSONStrings `json:"recurrence" gorm:"type:jsonb"`
	OriginalStart *time.Time       `json:"original_start"`
	// Kind marks events managed by Oikoboard ("todo-day"); empty otherwise.
	Kind      string    `json:"kind"`
	RemoteKey string    `json:"-"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
	Version   int       `json:"version" gorm:"default:1"`
}

func (Event) TableName() string { return "calendar_events" }

// Calendar is a provider calendar linked to a household.
type Calendar struct {
	ID           uuid.UUID `json:"id" gorm:"type:uuid;default:gen_random_uuid()"`
	HouseholdID  uuid.UUID `json:"household_id"`
	ConnectionID uuid.UUID `json:"connection_id"`
	RemoteID     string    `json:"remote_id"`
	Name         string    `json:"name"`
	Color        int64     `json:"color"`
	Writable     bool      `json:"writable"`
	Timezone     string    `json:"timezone"`
	Account      string    `json:"account"`
	SyncError    string    `json:"sync_error"`
	// TodoTarget: due tasks are put into this calendar (one per household).
	TodoTarget bool      `json:"todo_target"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
	Version    int       `json:"version" gorm:"default:1"`
}

func (Calendar) TableName() string { return "calendars" }

const (
	entityEvents    = "calendar_events"
	entityCalendars = "calendars"
)

type Module struct {
	DB        *gorm.DB
	Auth      *core.Auth
	Providers *Providers
	Syncer    *Syncer
}

func (Module) Name() string { return "calendar" }

func (m Module) Views() []core.View { return []core.View{rangeView{}, calendarsView{}} }

func (m Module) Routes(r *gin.RouterGroup) {
	r.POST("/calendar/events", m.createEvent)
	r.PATCH("/calendar/events/:id", m.updateEvent)
	r.DELETE("/calendar/events/:id", m.deleteEvent)

	r.GET("/calendar/preferences", m.getPreferences)
	r.PATCH("/calendar/preferences", m.updatePreferences)

	r.GET("/calendar/connections", m.listConnections)
	r.POST("/calendar/connections", m.startConnect)
	r.POST("/calendar/connections/complete", m.completeConnect)
	r.DELETE("/calendar/connections/:id", m.deleteConnection)
	r.GET("/calendar/connections/:id/calendars", m.remoteCalendars)

	r.POST("/calendars", m.linkCalendar)
	r.PATCH("/calendars/:id", m.updateCalendar)
	r.DELETE("/calendars/:id", m.unlinkCalendar)
	r.POST("/calendars/:id/sync", m.syncCalendar)
}

// calendar.range{from, to} — occurrences overlapping [from, to).
type rangeView struct{}

type rangeParams struct {
	From time.Time `json:"from"`
	To   time.Time `json:"to"`
}

func (rangeView) Name() string { return "calendar.range" }

func (rangeView) ParseParams(raw json.RawMessage) (any, error) {
	var p rangeParams
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, errors.New("from and to are required (RFC 3339)")
	}
	if !p.To.After(p.From) || p.To.Sub(p.From) > 400*24*time.Hour {
		return nil, errors.New("invalid range (max 400 days)")
	}
	return p, nil
}

func (rangeView) Snapshot(tx *gorm.DB, hh uuid.UUID, params any) (core.Entities, error) {
	p := params.(rangeParams)
	events := []Event{}
	err := tx.Where("household_id = ? AND starts_at < ? AND (ends_at > ? OR starts_at = ?)",
		hh, p.To, p.From, p.From).Order("starts_at").Find(&events).Error
	return core.Entities{entityEvents: events}, err
}

func (rangeView) Matches(params any, entity string, row json.RawMessage) bool {
	if entity != entityEvents {
		return false
	}
	p := params.(rangeParams)
	e, ok := core.DecodeRow[Event](row)
	return ok && e.StartsAt.Before(p.To) && (e.EndsAt.After(p.From) || e.StartsAt.Equal(p.From))
}

// calendar.calendars — the household's linked calendars.
type calendarsView struct{}

func (calendarsView) Name() string                                 { return "calendar.calendars" }
func (calendarsView) ParseParams(raw json.RawMessage) (any, error) { return core.NoParams(raw) }

func (calendarsView) Snapshot(tx *gorm.DB, hh uuid.UUID, _ any) (core.Entities, error) {
	cals := []Calendar{}
	err := tx.Where("household_id = ?", hh).Order("created_at").Find(&cals).Error
	return core.Entities{entityCalendars: cals}, err
}

func (calendarsView) Matches(_ any, entity string, _ json.RawMessage) bool {
	return entity == entityCalendars
}
