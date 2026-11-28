package logging

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"
)

// otlpHandler is a slog.Handler that queues records for the exporter.
type otlpHandler struct {
	exp    *exporter
	attrs  []kv   // already prefixed with the groups open at WithAttrs time
	groups string // current group prefix, "a.b."
}

func (h *otlpHandler) Enabled(context.Context, slog.Level) bool { return true }

func (h *otlpHandler) Handle(_ context.Context, r slog.Record) error {
	rec := logRecord{
		TimeUnixNano:   strconv.FormatInt(nonZero(r.Time).UnixNano(), 10),
		ObservedNano:   strconv.FormatInt(time.Now().UnixNano(), 10),
		SeverityNumber: severity(r.Level),
		SeverityText:   r.Level.String(),
		Body:           anyValue{String: &r.Message},
		Attributes:     append([]kv(nil), h.attrs...),
	}
	r.Attrs(func(a slog.Attr) bool {
		rec.Attributes = appendAttr(rec.Attributes, h.groups, a)
		return true
	})
	h.exp.enqueue(rec)
	return nil
}

func (h *otlpHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	n := *h
	n.attrs = append([]kv(nil), h.attrs...)
	for _, a := range attrs {
		n.attrs = appendAttr(n.attrs, h.groups, a)
	}
	return &n
}

func (h *otlpHandler) WithGroup(name string) slog.Handler {
	if name == "" {
		return h
	}
	n := *h
	n.groups = h.groups + name + "."
	return &n
}

func nonZero(t time.Time) time.Time {
	if t.IsZero() {
		return time.Now()
	}
	return t
}

func severity(l slog.Level) int {
	switch {
	case l >= slog.LevelError:
		return 17
	case l >= slog.LevelWarn:
		return 13
	case l >= slog.LevelInfo:
		return 9
	default:
		return 5
	}
}

func appendAttr(dst []kv, prefix string, a slog.Attr) []kv {
	a.Value = a.Value.Resolve()
	if a.Equal(slog.Attr{}) {
		return dst
	}
	if a.Value.Kind() == slog.KindGroup {
		p := prefix
		if a.Key != "" {
			p += a.Key + "."
		}
		for _, g := range a.Value.Group() {
			dst = appendAttr(dst, p, g)
		}
		return dst
	}
	return append(dst, kv{Key: prefix + a.Key, Value: toValue(a.Value)})
}

func toValue(v slog.Value) anyValue {
	switch v.Kind() {
	case slog.KindInt64:
		s := strconv.FormatInt(v.Int64(), 10)
		return anyValue{Int: &s}
	case slog.KindUint64:
		s := strconv.FormatUint(v.Uint64(), 10)
		return anyValue{Int: &s}
	case slog.KindBool:
		b := v.Bool()
		return anyValue{Bool: &b}
	case slog.KindFloat64:
		f := v.Float64()
		return anyValue{Double: &f}
	default:
		s := v.String()
		if e, ok := v.Any().(error); ok {
			s = e.Error()
		}
		return anyValue{String: &s}
	}
}

// --- OTLP/HTTP JSON payload (the subset we use) ---

type anyValue struct {
	String *string  `json:"stringValue,omitempty"`
	Int    *string  `json:"intValue,omitempty"` // int64 is a string in OTLP JSON
	Bool   *bool    `json:"boolValue,omitempty"`
	Double *float64 `json:"doubleValue,omitempty"`
}

type kv struct {
	Key   string   `json:"key"`
	Value anyValue `json:"value"`
}

type logRecord struct {
	TimeUnixNano   string   `json:"timeUnixNano"`
	ObservedNano   string   `json:"observedTimeUnixNano"`
	SeverityNumber int      `json:"severityNumber"`
	SeverityText   string   `json:"severityText"`
	Body           anyValue `json:"body"`
	Attributes     []kv     `json:"attributes,omitempty"`
}

type scopeLogs struct {
	Scope      map[string]string `json:"scope"`
	LogRecords []logRecord       `json:"logRecords"`
}

type resourceLogs struct {
	Resource  map[string][]kv `json:"resource"`
	ScopeLogs []scopeLogs     `json:"scopeLogs"`
}

type exportRequest struct {
	ResourceLogs []resourceLogs `json:"resourceLogs"`
}

// --- exporter ---

type exporter struct {
	cfg    Config
	client *http.Client
	queue  chan logRecord
	wake   chan struct{}
	done   chan struct{}
	stop   chan struct{}
	once   sync.Once
}

func newExporter(cfg Config) *exporter {
	if cfg.FlushInterval <= 0 {
		cfg.FlushInterval = 5 * time.Second
	}
	if cfg.BatchSize <= 0 {
		cfg.BatchSize = 100
	}
	if cfg.QueueSize <= 0 {
		cfg.QueueSize = 2000
	}
	e := &exporter{
		cfg:    cfg,
		client: &http.Client{Timeout: 10 * time.Second},
		queue:  make(chan logRecord, cfg.QueueSize),
		wake:   make(chan struct{}, 1),
		done:   make(chan struct{}),
		stop:   make(chan struct{}),
	}
	go e.run()
	return e
}

// enqueue never blocks: when the queue is full the record is dropped.
func (e *exporter) enqueue(r logRecord) {
	select {
	case e.queue <- r:
		if len(e.queue) >= e.cfg.BatchSize {
			select {
			case e.wake <- struct{}{}:
			default:
			}
		}
	default:
	}
}

func (e *exporter) run() {
	defer close(e.done)
	t := time.NewTicker(e.cfg.FlushInterval)
	defer t.Stop()
	for {
		select {
		case <-t.C:
			e.flush()
		case <-e.wake:
			e.flush()
		case <-e.stop:
			e.flush()
			return
		}
	}
}

// flush sends everything queued right now, in batches of BatchSize.
func (e *exporter) flush() {
	for {
		batch := make([]logRecord, 0, e.cfg.BatchSize)
	fill:
		for len(batch) < e.cfg.BatchSize {
			select {
			case r := <-e.queue:
				batch = append(batch, r)
			default:
				break fill
			}
		}
		if len(batch) == 0 {
			return
		}
		e.send(batch)
	}
}

func (e *exporter) send(batch []logRecord) {
	svc := "oikoboard"
	body, err := json.Marshal(exportRequest{ResourceLogs: []resourceLogs{{
		Resource:  map[string][]kv{"attributes": {{Key: "service.name", Value: anyValue{String: &svc}}}},
		ScopeLogs: []scopeLogs{{Scope: map[string]string{"name": "oikoboard"}, LogRecords: batch}},
	}}})
	if err != nil {
		return
	}
	req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, e.cfg.OTLPURL, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if e.cfg.OTLPUser != "" {
		req.SetBasicAuth(e.cfg.OTLPUser, e.cfg.OTLPPassword)
	}
	resp, err := e.client.Do(req)
	if err != nil {
		fmt.Fprintln(os.Stderr, "logging: OTLP export failed:", err) // not slog: would loop back here
		return
	}
	resp.Body.Close()
	if resp.StatusCode >= 300 {
		fmt.Fprintln(os.Stderr, "logging: OTLP export failed:", resp.Status)
	}
}

// close flushes the queue and stops the background goroutine.
func (e *exporter) close() {
	e.once.Do(func() { close(e.stop) })
	<-e.done
}
