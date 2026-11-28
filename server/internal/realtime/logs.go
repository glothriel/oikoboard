package realtime

import (
	"context"
	"encoding/json"
	"log/slog"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

// Limits keeping a max-size "log" message under the websocket read limit (32 KiB): about 1.2 KiB a
// record, so 20 records stay below 25 KiB. Surplus records are dropped.
const (
	maxLogRecords = 20
	maxLogMsg     = 512 // bytes
	maxLogAttrs   = 512 // bytes, serialized
)

type clientLog struct {
	Ts    string         `json:"ts"`
	Level string         `json:"level"`
	Msg   string         `json:"msg"`
	Attrs map[string]any `json:"attrs"`
}

// handleLogs re-emits the records an app sent through the server's logger, tagged with the
// household and member ids. The server never replies; malformed input is dropped.
func (c *Conn) handleLogs(raw json.RawMessage) {
	var logs []clientLog
	if err := json.Unmarshal(raw, &logs); err != nil {
		return
	}
	if len(logs) > maxLogRecords {
		logs = logs[:maxLogRecords]
	}
	h := c.hub.logHandler()
	for _, l := range logs {
		level := parseLevel(l.Level)
		if !h.Enabled(c.ctx, level) {
			continue
		}
		ts, err := time.Parse(time.RFC3339Nano, l.Ts)
		if err != nil {
			ts = time.Now()
		}
		r := slog.NewRecord(ts, level, truncate(l.Msg, maxLogMsg), 0)
		r.AddAttrs(slog.String("source", "app"),
			slog.String("household_id", c.actor.HouseholdID.String()),
			slog.String("member_id", c.actor.MemberID.String()))
		r.AddAttrs(clientAttrs(l.Attrs)...)
		_ = h.Handle(context.WithoutCancel(c.ctx), r)
	}
}

func parseLevel(s string) slog.Level {
	switch strings.ToLower(s) {
	case "debug", "trace", "fine":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error", "severe", "fatal":
		return slog.LevelError
	}
	return slog.LevelInfo
}

// clientAttrs keeps attributes in key order while their serialized size fits maxLogAttrs; the
// rest is dropped and counted in attrs_dropped. Keys of the server's own attributes are skipped.
func clientAttrs(m map[string]any) []slog.Attr {
	keys := make([]string, 0, len(m))
	for k := range m {
		switch k {
		case "source", "household_id", "member_id", "attrs_dropped":
			continue
		}
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var out []slog.Attr
	size, dropped := 2, 0
	for _, k := range keys {
		b, err := json.Marshal(map[string]any{k: m[k]})
		if err != nil || size+len(b) > maxLogAttrs {
			dropped++
			continue
		}
		size += len(b)
		out = append(out, slog.Any(truncate(k, 64), m[k]))
	}
	if dropped > 0 {
		out = append(out, slog.Int("attrs_dropped", dropped))
	}
	return out
}

// truncate cuts s to at most n bytes on a rune boundary.
func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	s = s[:n]
	for len(s) > 0 && !utf8.ValidString(s) {
		s = s[:len(s)-1]
	}
	return s
}
