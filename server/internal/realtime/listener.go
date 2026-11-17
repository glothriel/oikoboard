package realtime

import (
	"context"
	"log/slog"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const channel = "oiko_changes"

// Listen trzyma jedno połączenie LISTEN do Postgresa i szturcha dispatchery
// gospodarstw, w których coś się zmieniło. Po zerwaniu łączy się ponownie
// i każe wszystkim dispatcherom dociągnąć zmiany z tabeli changes — dzięki
// temu przerwa w LISTEN nie gubi danych.
func (h *Hub) Listen(ctx context.Context, dsn string) {
	backoff := 500 * time.Millisecond
	for ctx.Err() == nil {
		err := h.listenOnce(ctx, dsn, func() { backoff = 500 * time.Millisecond })
		if ctx.Err() != nil {
			return
		}
		slog.Warn("realtime: LISTEN przerwany, ponawiam", "err", err, "za", backoff)
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
		backoff = min(backoff*2, 30*time.Second)
	}
}

func (h *Hub) listenOnce(ctx context.Context, dsn string, connected func()) error {
	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		return err
	}
	defer conn.Close(context.Background())
	if _, err := conn.Exec(ctx, "LISTEN "+channel); err != nil {
		return err
	}
	connected()
	slog.Info("realtime: nasłuchuję", "channel", channel)
	// Mogliśmy coś przegapić, zanim LISTEN zaczął działać.
	h.PokeAll()
	for {
		n, err := conn.WaitForNotification(ctx)
		if err != nil {
			return err
		}
		hhStr, _, _ := strings.Cut(n.Payload, ":")
		if hh, err := uuid.Parse(hhStr); err == nil {
			h.Poke(hh)
		}
	}
}
