package calendar

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// Provider is an external calendar service (Google today, CalDAV later).
// The model is iCalendar-shaped: a series master carries RRULE/EXDATE lines,
// an exception points at its master and the start it replaces.
type Provider interface {
	ListCalendars(ctx context.Context) ([]RemoteCalendar, error)
	// Changes since token; an empty token means a full listing (Full=true).
	// ErrSyncReset: the token is no longer valid — call again with "".
	Changes(ctx context.Context, calID, token string) (ChangeSet, error)
	// Put creates (create=true) or updates an event and returns it as stored
	// by the provider. Updating an instance id (see InstanceID) of a series
	// creates or updates an exception.
	Put(ctx context.Context, calID string, ev RemoteEvent, create bool) (RemoteEvent, error)
	// Delete removes an event; deleting an instance id cancels that occurrence.
	// Deleting something already gone is not an error.
	Delete(ctx context.Context, calID, remoteID string) error
}

var (
	ErrSyncReset = errors.New("sync token expired")
	ErrRevoked   = errors.New("calendar access revoked")
)

type RemoteCalendar struct {
	RemoteID string `json:"remote_id"`
	Name     string `json:"name"`
	Color    int64  `json:"color"`
	Writable bool   `json:"writable"`
	TimeZone string `json:"timezone"`
}

type RemoteEvent struct {
	RemoteID    string
	ETag        string
	Updated     time.Time
	Status      string // confirmed | tentative | cancelled
	Title       string
	Description string
	Location    string
	// All-day events: midnight UTC of the first day; End is exclusive.
	Start, End time.Time
	AllDay     bool
	TimeZone   string // IANA; empty = calendar default
	Recurrence []string
	// Exceptions: the master's remote id and the start of the replaced instance.
	SeriesRemoteID string
	OriginalStart  *time.Time
	MemberIDs      []uuid.UUID
	AttendeeEmails []string
	// Kind of an event managed by Oikoboard (see KindTodoDay); empty otherwise.
	Kind string
}

func (e RemoteEvent) cancelled() bool { return e.Status == "cancelled" }

type ChangeSet struct {
	Events []RemoteEvent
	Full   bool // Events is the complete calendar
	Token  string
}

// InstanceID is the id of one occurrence of a series (Google's format, also
// used by the mock).
func InstanceID(seriesID string, originalStart time.Time, allDay bool) string {
	if allDay {
		return seriesID + "_" + originalStart.UTC().Format("20060102")
	}
	return seriesID + "_" + originalStart.UTC().Format("20060102T150405Z")
}

// RemoteIDFor: the provider id of an event we create with a client-chosen
// uuid (hex — valid in Google's base32hex alphabet).
func RemoteIDFor(id uuid.UUID) string {
	b, _ := id.MarshalText()
	out := make([]byte, 0, 32)
	for _, c := range b {
		if c != '-' {
			out = append(out, c)
		}
	}
	return string(out)
}

// Connection is a row of calendar_connections.
type Connection struct {
	ID          uuid.UUID  `json:"id" gorm:"type:uuid;default:gen_random_uuid()"`
	UserID      *uuid.UUID `json:"-"`
	Provider    string     `json:"provider"`
	Account     string     `json:"account"`
	Credentials string     `json:"-"`
	Status      string     `json:"status" gorm:"default:ok"`
	CreatedAt   time.Time  `json:"created_at"`
}

func (Connection) TableName() string { return "calendar_connections" }

// Providers builds the Provider for a connection.
type Providers struct {
	DB *gorm.DB
	// GoogleClient returns an authorized client for sealed credentials; nil
	// when Google isn't configured.
	GoogleClient func(ctx context.Context, credentials string) (*http.Client, error)
	// GoogleAPI overrides the Calendar API base URL (tests).
	GoogleAPI string

	mu      sync.Mutex
	clients map[string]*http.Client // credentials → client (keeps access tokens)
}

func (p *Providers) For(ctx context.Context, db *gorm.DB, conn Connection) (Provider, error) {
	if conn.Status == "revoked" {
		return nil, ErrRevoked
	}
	switch conn.Provider {
	case "mock":
		return mockProvider{db: db, conn: conn.ID}, nil
	case "google":
		if p.GoogleClient == nil {
			return nil, errors.New("google is not configured")
		}
		p.mu.Lock()
		defer p.mu.Unlock()
		hc := p.clients[conn.Credentials]
		if hc == nil {
			var err error
			if hc, err = p.GoogleClient(ctx, conn.Credentials); err != nil {
				return nil, err
			}
			if p.clients == nil {
				p.clients = map[string]*http.Client{}
			}
			p.clients[conn.Credentials] = hc
		}
		base := p.GoogleAPI
		if base == "" {
			base = "https://www.googleapis.com/calendar/v3"
		}
		return googleProvider{http: hc, base: base}, nil
	}
	return nil, fmt.Errorf("unknown provider %q", conn.Provider)
}
