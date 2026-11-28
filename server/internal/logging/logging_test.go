package logging

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

type collector struct {
	mu      sync.Mutex
	auth    []string
	batches []exportRequest
	srv     *httptest.Server
}

func newCollector(t *testing.T) *collector {
	c := &collector{}
	c.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		var req exportRequest
		if err := json.Unmarshal(b, &req); err != nil {
			t.Errorf("bad payload: %v", err)
		}
		c.mu.Lock()
		c.auth = append(c.auth, r.Header.Get("Authorization")+"|"+r.Header.Get("Content-Type"))
		c.batches = append(c.batches, req)
		c.mu.Unlock()
	}))
	t.Cleanup(c.srv.Close)
	return c
}

func (c *collector) records() []logRecord {
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []logRecord
	for _, b := range c.batches {
		out = append(out, b.ResourceLogs[0].ScopeLogs[0].LogRecords...)
	}
	return out
}

func attrMap(r logRecord) map[string]anyValue {
	m := map[string]anyValue{}
	for _, a := range r.Attributes {
		m[a.Key] = a.Value
	}
	return m
}

func TestOTLPPayloadAndAuth(t *testing.T) {
	c := newCollector(t)
	var console bytes.Buffer
	l, closeFn := Setup(Config{OTLPURL: c.srv.URL, OTLPUser: "u", OTLPPassword: "p",
		Console: slog.NewTextHandler(&console, nil)})
	l.Warn("hello", "n", 3, "ok", true, "f", 1.5, "s", "x", slog.Group("g", "k", "v"))
	slog.Info("via default")
	closeFn()

	recs := c.records()
	if len(recs) != 2 {
		t.Fatalf("records: %d", len(recs))
	}
	r := recs[0]
	if *r.Body.String != "hello" || r.SeverityNumber != 13 || r.SeverityText != "WARN" {
		t.Fatalf("record: %+v", r)
	}
	a := attrMap(r)
	if *a["n"].Int != "3" || !*a["ok"].Bool || *a["f"].Double != 1.5 || *a["s"].String != "x" || *a["g.k"].String != "v" {
		t.Fatalf("attrs: %+v", r.Attributes)
	}
	res := c.batches[0].ResourceLogs[0].Resource["attributes"]
	if res[0].Key != "service.name" || *res[0].Value.String != "oikoboard" {
		t.Fatalf("resource: %+v", res)
	}
	if c.auth[0] != "Basic dTpw|application/json" {
		t.Fatalf("auth: %q", c.auth[0])
	}
	if !strings.Contains(console.String(), "hello") {
		t.Fatalf("console lost the record: %q", console.String())
	}
}

func TestBatching(t *testing.T) {
	c := newCollector(t)
	l, closeFn := Setup(Config{OTLPURL: c.srv.URL, BatchSize: 10, FlushInterval: time.Hour,
		Console: slog.NewTextHandler(io.Discard, nil)})
	for i := 0; i < 10; i++ {
		l.Info("m")
	}
	deadline := time.Now().Add(3 * time.Second)
	for len(c.records()) < 10 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if n := len(c.records()); n != 10 {
		t.Fatalf("size-triggered flush: %d records", n)
	}
	l.Info("last")
	closeFn()
	if n := len(c.records()); n != 11 {
		t.Fatalf("close flush: %d records", n)
	}
}

func TestOverflowDrops(t *testing.T) {
	c := newCollector(t)
	l, closeFn := Setup(Config{OTLPURL: c.srv.URL, QueueSize: 5, BatchSize: 100, FlushInterval: time.Hour,
		Console: slog.NewTextHandler(io.Discard, nil)})
	for i := 0; i < 20; i++ {
		l.Info("m")
	}
	closeFn()
	if n := len(c.records()); n != 5 {
		t.Fatalf("records after overflow: %d", n)
	}
}

func TestNoURLIsConsoleOnly(t *testing.T) {
	var console bytes.Buffer
	l, closeFn := Setup(Config{Console: slog.NewTextHandler(&console, nil)})
	l.Info("plain")
	closeFn()
	if !strings.Contains(console.String(), "plain") {
		t.Fatalf("console: %q", console.String())
	}
	if _, ok := l.Handler().(fanout); ok {
		t.Fatal("no exporter expected without a URL")
	}
}

func TestWithAttrsAndGroups(t *testing.T) {
	c := newCollector(t)
	l, closeFn := Setup(Config{OTLPURL: c.srv.URL, Console: slog.NewTextHandler(io.Discard, nil)})
	l.With("household", "h1").WithGroup("req").With("id", "r1").Info("m", "x", 1)
	closeFn()
	recs := c.records()
	if len(recs) != 1 {
		t.Fatalf("records: %d", len(recs))
	}
	a := attrMap(recs[0])
	if *a["household"].String != "h1" || *a["req.id"].String != "r1" || *a["req.x"].Int != "1" {
		t.Fatalf("attrs: %+v", recs[0].Attributes)
	}
}
