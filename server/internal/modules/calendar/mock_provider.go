package calendar

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// mockProvider stands in for Google in dev and tests (OIKO_MOCK_OAUTH, seed
// data). It keeps its "remote" calendars in Postgres so they survive server
// restarts, and mimics Google's semantics: sync tokens, instance ids,
// cancelled exceptions.
type mockProvider struct {
	db   *gorm.DB
	conn uuid.UUID
}

// MockCalendars created for every new mock connection.
var MockCalendars = []RemoteCalendar{
	{RemoteID: "family", Name: "Rodzina (mock)", Color: 0xFF5C6BC0, Writable: true, TimeZone: "Europe/Warsaw"},
	{RemoteID: "school", Name: "Szkoła (mock)", Color: 0xFF26A69A, Writable: true, TimeZone: "Europe/Warsaw"},
	{RemoteID: "holidays", Name: "Święta (mock, tylko odczyt)", Color: 0xFFE57373, Writable: false, TimeZone: "Europe/Warsaw"},
}

// CreateMockCalendars sets up the mock "server side" of a new mock connection.
func CreateMockCalendars(tx *gorm.DB, conn uuid.UUID) error {
	for _, c := range MockCalendars {
		if err := tx.Exec(`
			INSERT INTO mock_provider_calendars (connection_id, remote_id, name, color)
			VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING`, conn, c.RemoteID, c.Name, c.Color).Error; err != nil {
			return err
		}
	}
	return nil
}

func (m mockProvider) ListCalendars(ctx context.Context) ([]RemoteCalendar, error) {
	var rows []struct {
		RemoteID string
		Name     string
		Color    int64
	}
	if err := m.db.WithContext(ctx).Raw(`
		SELECT remote_id, name, color FROM mock_provider_calendars
		WHERE connection_id = ? ORDER BY name`, m.conn).Scan(&rows).Error; err != nil {
		return nil, err
	}
	out := make([]RemoteCalendar, len(rows))
	for i, r := range rows {
		out[i] = RemoteCalendar{RemoteID: r.RemoteID, Name: r.Name, Color: r.Color,
			Writable: r.RemoteID != "holidays", TimeZone: "Europe/Warsaw"}
	}
	return out, nil
}

func (m mockProvider) Changes(ctx context.Context, calID, token string) (ChangeSet, error) {
	var since int64
	full := token == ""
	if !full {
		var err error
		if since, err = strconv.ParseInt(token, 10, 64); err != nil {
			return ChangeSet{}, ErrSyncReset
		}
	}
	var rows []struct {
		Seq     int64
		Data    []byte
		Deleted bool
	}
	q := `SELECT seq, data, deleted FROM mock_provider_events
	      WHERE connection_id = ? AND calendar_id = ? AND seq > ?`
	if full {
		q += " AND NOT deleted"
	}
	if err := m.db.WithContext(ctx).Raw(q+" ORDER BY seq", m.conn, calID, since).Scan(&rows).Error; err != nil {
		return ChangeSet{}, err
	}
	cs := ChangeSet{Full: full, Token: strconv.FormatInt(since, 10)}
	if full {
		// The token of a full listing is the newest seq overall.
		var max *int64
		m.db.WithContext(ctx).Raw(`SELECT max(seq) FROM mock_provider_events
			WHERE connection_id = ? AND calendar_id = ?`, m.conn, calID).Scan(&max)
		cs.Token = "0"
		if max != nil {
			cs.Token = strconv.FormatInt(*max, 10)
		}
	}
	for _, r := range rows {
		var ev RemoteEvent
		if err := json.Unmarshal(r.Data, &ev); err != nil {
			return ChangeSet{}, err
		}
		if r.Deleted {
			ev.Status = "cancelled"
		}
		if full && ev.cancelled() && ev.SeriesRemoteID == "" {
			continue
		}
		cs.Events = append(cs.Events, ev)
		if !full {
			cs.Token = strconv.FormatInt(r.Seq, 10)
		}
	}
	return cs, nil
}

func (m mockProvider) store(ctx context.Context, calID string, ev RemoteEvent, deleted bool) (RemoteEvent, error) {
	var seq int64
	if err := m.db.WithContext(ctx).Raw("SELECT nextval('mock_provider_events_seq_seq')").Scan(&seq).Error; err != nil {
		return ev, err
	}
	ev.ETag = `"` + strconv.FormatInt(seq, 10) + `"`
	ev.Updated = time.Now().UTC().Truncate(time.Millisecond)
	data, _ := json.Marshal(ev)
	err := m.db.WithContext(ctx).Exec(`
		INSERT INTO mock_provider_events (connection_id, calendar_id, remote_id, seq, data, deleted)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT (connection_id, calendar_id, remote_id)
		DO UPDATE SET seq = EXCLUDED.seq, data = EXCLUDED.data, deleted = EXCLUDED.deleted`,
		m.conn, calID, ev.RemoteID, seq, data, deleted).Error
	return ev, err
}

func (m mockProvider) get(ctx context.Context, calID, remoteID string) (*RemoteEvent, error) {
	var row struct {
		Data    []byte
		Deleted bool
	}
	err := m.db.WithContext(ctx).Raw(`SELECT data, deleted FROM mock_provider_events
		WHERE connection_id = ? AND calendar_id = ? AND remote_id = ?`, m.conn, calID, remoteID).Scan(&row).Error
	if err != nil || row.Data == nil || row.Deleted {
		return nil, err
	}
	var ev RemoteEvent
	return &ev, json.Unmarshal(row.Data, &ev)
}

func (m mockProvider) writable(calID string) error {
	if calID == "holidays" {
		return errors.New("calendar is read-only")
	}
	return nil
}

func (m mockProvider) Put(ctx context.Context, calID string, ev RemoteEvent, create bool) (RemoteEvent, error) {
	if err := m.writable(calID); err != nil {
		return ev, err
	}
	if ev.Status == "" {
		ev.Status = "confirmed"
	}
	if series, start, ok := m.parseInstance(ctx, calID, ev.RemoteID); ok && ev.SeriesRemoteID == "" {
		ev.SeriesRemoteID, ev.OriginalStart = series, &start
	}
	return m.store(ctx, calID, ev, false)
}

// parseInstance recognizes "<series>_<start>" ids of existing series.
func (m mockProvider) parseInstance(ctx context.Context, calID, id string) (string, time.Time, bool) {
	i := strings.LastIndexByte(id, '_')
	if i <= 0 {
		return "", time.Time{}, false
	}
	series, ts := id[:i], id[i+1:]
	t, err := time.Parse("20060102T150405Z", ts)
	if err != nil {
		if t, err = time.Parse("20060102", ts); err != nil {
			return "", time.Time{}, false
		}
	}
	if master, _ := m.get(ctx, calID, series); master == nil {
		return "", time.Time{}, false
	}
	return series, t, true
}

func (m mockProvider) Delete(ctx context.Context, calID, remoteID string) error {
	if err := m.writable(calID); err != nil {
		return err
	}
	ev, err := m.get(ctx, calID, remoteID)
	if err != nil {
		return err
	}
	if ev == nil {
		// An instance of a series that has no exception yet → cancelled exception.
		if series, start, ok := m.parseInstance(ctx, calID, remoteID); ok {
			_, err := m.store(ctx, calID, RemoteEvent{RemoteID: remoteID, Status: "cancelled",
				SeriesRemoteID: series, OriginalStart: &start}, false)
			return err
		}
		return nil
	}
	if ev.SeriesRemoteID != "" {
		ev.Status = "cancelled"
		_, err := m.store(ctx, calID, *ev, false)
		return err
	}
	// A master or single event: it and its exceptions are gone.
	var ids []string
	m.db.WithContext(ctx).Raw(`SELECT remote_id FROM mock_provider_events
		WHERE connection_id = ? AND calendar_id = ? AND data->>'SeriesRemoteID' = ?`,
		m.conn, calID, remoteID).Scan(&ids)
	for _, id := range append(ids, remoteID) {
		if _, err := m.store(ctx, calID, RemoteEvent{RemoteID: id, Status: "cancelled"}, true); err != nil {
			return err
		}
	}
	return nil
}

// SeedMock gives a household mock calendars filled with events (sample
// data): remote calendar id → events. Runs inside tx, including the first
// sync, so the occurrences exist when it returns.
func SeedMock(tx *gorm.DB, hh uuid.UUID, events map[string][]RemoteEvent) error {
	conn := Connection{Provider: "mock", Account: "sample data"}
	if err := tx.Create(&conn).Error; err != nil {
		return err
	}
	if err := CreateMockCalendars(tx, conn.ID); err != nil {
		return err
	}
	p := mockProvider{db: tx, conn: conn.ID}
	ctx := tx.Statement.Context
	for _, rc := range MockCalendars {
		evs, ok := events[rc.RemoteID]
		if !ok {
			continue
		}
		for _, ev := range evs {
			if ev.RemoteID == "" {
				ev.RemoteID = RemoteIDFor(uuid.New())
			}
			if _, err := p.store(ctx, rc.RemoteID, ev, false); err != nil {
				return err
			}
		}
		cal := Calendar{HouseholdID: hh, ConnectionID: conn.ID, RemoteID: rc.RemoteID, Name: rc.Name,
			Color: rc.Color, Writable: rc.Writable, Timezone: rc.TimeZone, Account: conn.Account}
		if err := tx.Create(&cal).Error; err != nil {
			return err
		}
		cs, err := p.Changes(ctx, rc.RemoteID, "")
		if err != nil {
			return err
		}
		if err := applyRemote(tx, &cal, cs.Events, true); err != nil {
			return err
		}
		if err := tx.Exec("INSERT INTO calendar_sync_state (calendar_id, sync_token, synced_at) VALUES (?, ?, now())",
			cal.ID, cs.Token).Error; err != nil {
			return err
		}
	}
	return ensureTodoTarget(tx, hh)
}
