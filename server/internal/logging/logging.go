// Package logging builds the process-wide slog logger: a decorator handler that keeps the console
// output and also exports every record as an OTLP/HTTP JSON log record (otlp.go).
package logging

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"time"
)

// Config selects the log destinations. Without OTLPURL it is a plain console logger.
type Config struct {
	OTLPURL      string // OTLP/HTTP logs endpoint, e.g. https://otlp.example.com/v1/logs
	OTLPUser     string // basic auth; empty = no Authorization header
	OTLPPassword string

	Console       slog.Handler  // default: text handler on stderr
	FlushInterval time.Duration // default 5 s
	BatchSize     int           // flush as soon as this many records are queued; default 100
	QueueSize     int           // bounded queue, records beyond it are dropped; default 2000
}

// Setup builds the logger, installs it as the slog default and returns it together with a func
// that flushes pending OTLP records (call it before exit).
func Setup(cfg Config) (*slog.Logger, func()) {
	console := cfg.Console
	if console == nil {
		console = slog.NewTextHandler(os.Stderr, nil)
	}
	var h slog.Handler = console
	closeFn := func() {}
	if cfg.OTLPURL != "" {
		exp := newExporter(cfg)
		h = fanout{console, &otlpHandler{exp: exp}}
		closeFn = exp.close
	}
	l := slog.New(h)
	slog.SetDefault(l)
	return l, closeFn
}

// fanout sends every record to all handlers.
type fanout []slog.Handler

func (f fanout) Enabled(ctx context.Context, l slog.Level) bool {
	for _, h := range f {
		if h.Enabled(ctx, l) {
			return true
		}
	}
	return false
}

func (f fanout) Handle(ctx context.Context, r slog.Record) error {
	var errs []error
	for _, h := range f {
		if h.Enabled(ctx, r.Level) {
			errs = append(errs, h.Handle(ctx, r.Clone()))
		}
	}
	return errors.Join(errs...)
}

func (f fanout) WithAttrs(attrs []slog.Attr) slog.Handler {
	out := make(fanout, len(f))
	for i, h := range f {
		out[i] = h.WithAttrs(attrs)
	}
	return out
}

func (f fanout) WithGroup(name string) slog.Handler {
	if name == "" {
		return f
	}
	out := make(fanout, len(f))
	for i, h := range f {
		out[i] = h.WithGroup(name)
	}
	return out
}
