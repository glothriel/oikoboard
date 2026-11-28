// Package realtime: rozsyłanie zmian z Postgresa do otwartych widoków
// w aplikacjach (WebSocket). Opis w docs/backend-realtime.md.
package realtime

import (
	"log/slog"
	"sync"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

type Hub struct {
	db    *gorm.DB
	views core.Views
	auth  *core.Auth

	mu          sync.Mutex
	dispatchers map[uuid.UUID]*dispatcher

	presence *presence

	// appLogs receives the records the apps send as "log" messages; nil = the slog default handler.
	appLogs slog.Handler
}

func NewHub(db *gorm.DB, auth *core.Auth, views core.Views, appLogs slog.Handler) *Hub {
	return &Hub{db: db, auth: auth, views: views, dispatchers: map[uuid.UUID]*dispatcher{}, presence: newPresence(), appLogs: appLogs}
}

func (h *Hub) logHandler() slog.Handler {
	if h.appLogs != nil {
		return h.appLogs
	}
	return slog.Default().Handler()
}

// acquire zwraca (i w razie potrzeby uruchamia) dispatcher gospodarstwa.
// Każde acquire musi mieć swoje release.
func (h *Hub) acquire(hh uuid.UUID) (*dispatcher, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	d, ok := h.dispatchers[hh]
	if !ok {
		var err error
		d, err = startDispatcher(h.db, h.views, hh)
		if err != nil {
			return nil, err
		}
		h.dispatchers[hh] = d
	}
	d.refs++
	return d, nil
}

func (h *Hub) release(d *dispatcher) {
	h.mu.Lock()
	defer h.mu.Unlock()
	d.refs--
	if d.refs == 0 {
		delete(h.dispatchers, d.hh)
		d.stop()
	}
}

func (h *Hub) Poke(hh uuid.UUID) {
	h.mu.Lock()
	d := h.dispatchers[hh]
	h.mu.Unlock()
	if d != nil {
		d.poke()
	}
}

func (h *Hub) PokeAll() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, d := range h.dispatchers {
		d.poke()
	}
}

// SetPresenceGrace overrides the offline grace period (tests).
func (h *Hub) SetPresenceGrace(d time.Duration) { h.presence.setGrace(d) }

// SetLogHandler overrides where app logs go (tests).
func (h *Hub) SetLogHandler(l slog.Handler) { h.appLogs = l }
