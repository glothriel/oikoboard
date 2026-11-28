package app_test

import (
	"context"
	"log/slog"
	"strings"
	"sync"
	"testing"
	"time"
)

type recordedLog struct {
	Level slog.Level
	Msg   string
	Time  time.Time
	Attrs map[string]slog.Value
}

// fakeLogHandler collects the records the hub re-emits.
type fakeLogHandler struct {
	mu   sync.Mutex
	recs []recordedLog
}

func (f *fakeLogHandler) Enabled(context.Context, slog.Level) bool { return true }
func (f *fakeLogHandler) WithAttrs([]slog.Attr) slog.Handler       { return f }
func (f *fakeLogHandler) WithGroup(string) slog.Handler            { return f }
func (f *fakeLogHandler) Handle(_ context.Context, r slog.Record) error {
	rec := recordedLog{Level: r.Level, Msg: r.Message, Time: r.Time, Attrs: map[string]slog.Value{}}
	r.Attrs(func(a slog.Attr) bool { rec.Attrs[a.Key] = a.Value; return true })
	f.mu.Lock()
	f.recs = append(f.recs, rec)
	f.mu.Unlock()
	return nil
}

func (f *fakeLogHandler) snapshot() []recordedLog {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]recordedLog(nil), f.recs...)
}

// stillOpen proves the socket survived: a subscription still gets its snapshot.
func (w *wsClient) stillOpen(id string) {
	w.t.Helper()
	w.sub(id, "todo.lists", map[string]any{})
}

func TestAppLogs(t *testing.T) {
	e := setup(t)
	fake := &fakeLogHandler{}
	e.app.Hub.SetLogHandler(fake)
	a := e.newFamily("Kowalscy")
	var me meRes
	a.do("GET", "/me", nil, &me)
	w := a.ws()

	ts := time.Date(2026, 11, 28, 10, 0, 0, 0, time.UTC)
	w.send(map[string]any{"t": "log", "logs": []map[string]any{
		{"ts": ts.Format(time.RFC3339Nano), "level": "warn", "msg": "ble: write", "attrs": map[string]any{"hex": "0a0b", "n": 3, "member_id": "spoofed"}},
		{"level": "bogus", "msg": "second"},
	}})
	w.stillOpen("s1")

	recs := fake.snapshot()
	if len(recs) != 2 {
		t.Fatalf("records: %+v", recs)
	}
	r := recs[0]
	if r.Msg != "ble: write" || r.Level != slog.LevelWarn || !r.Time.Equal(ts) {
		t.Fatalf("record: %+v", r)
	}
	if r.Attrs["source"].String() != "app" || r.Attrs["member_id"].String() != *me.MemberID ||
		r.Attrs["household_id"].String() == "" || r.Attrs["hex"].String() != "0a0b" {
		t.Fatalf("attrs: %+v", r.Attrs)
	}
	if recs[1].Level != slog.LevelInfo {
		t.Fatalf("default level: %v", recs[1].Level)
	}
}

func TestAppLogsLimits(t *testing.T) {
	e := setup(t)
	fake := &fakeLogHandler{}
	e.app.Hub.SetLogHandler(fake)
	w := e.newFamily("Nowakowie").ws()

	// Malformed payloads are dropped and the socket stays open.
	w.send(map[string]any{"t": "log", "logs": "nope"})
	w.send(map[string]any{"t": "log", "logs": []any{1, 2}})
	w.send(map[string]any{"t": "log"})
	w.stillOpen("s1")
	if n := len(fake.snapshot()); n != 0 {
		t.Fatalf("malformed produced %d records", n)
	}

	// A max-size message: 20 records, msg and attrs over their caps.
	var logs []map[string]any
	for i := 0; i < 20; i++ {
		attrs := map[string]any{}
		for k := 0; k < 8; k++ {
			attrs["k"+string(rune('a'+k))] = strings.Repeat("v", 80)
		}
		logs = append(logs, map[string]any{"level": "info", "msg": strings.Repeat("m", 600), "attrs": attrs})
	}
	w.send(map[string]any{"t": "log", "logs": logs}) // fits the 32 KiB read limit
	w.stillOpen("s2")
	recs := fake.snapshot()
	if len(recs) != 20 {
		t.Fatalf("records: %d", len(recs))
	}
	if len(recs[0].Msg) != maxMsg {
		t.Fatalf("msg length: %d", len(recs[0].Msg))
	}
	if recs[0].Attrs["attrs_dropped"].Int64() == 0 {
		t.Fatalf("attrs not truncated: %+v", recs[0].Attrs)
	}

	// More than 20 records: the surplus is dropped.
	var small []map[string]any
	for i := 0; i < 25; i++ {
		small = append(small, map[string]any{"msg": "x"})
	}
	w.send(map[string]any{"t": "log", "logs": small})
	w.stillOpen("s3")
	if n := len(fake.snapshot()); n != 40 {
		t.Fatalf("records after surplus: %d", n)
	}
}

const maxMsg = 512
