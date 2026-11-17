package realtime

import (
	"context"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

// Jak często dispatcher sprawdza changes nawet bez NOTIFY (bezpiecznik).
var safetyPollInterval = 10 * time.Second

const loadBatch = 500

// dispatcher obsługuje jedno gospodarstwo: po każdym NOTIFY doczytuje nowe
// wiersze z changes (seq > lastSeq) i rozdaje je subskrypcjom.
//
// Cały stan (lastSeq, subs, bufory subskrypcji) jest dotykany wyłącznie
// z goroutine run() — inne goroutines wysyłają do niej funkcje przez cmds.
type dispatcher struct {
	hh    uuid.UUID
	db    *gorm.DB
	views core.Views
	refs  int // chronione Hub.mu

	pokeCh chan struct{}
	cmds   chan func()
	ctx    context.Context
	cancel context.CancelFunc

	lastSeq int64
	subs    map[*subscription]struct{}
}

type subscription struct {
	id     string
	conn   *Conn
	view   core.View
	params any

	pending bool // czeka na snapshot — zmiany idą do bufora
	buf     []*core.Change
	snapSeq int64
}

const maxPendingBuffer = 5000

func startDispatcher(db *gorm.DB, views core.Views, hh uuid.UUID) (*dispatcher, error) {
	ctx, cancel := context.WithCancel(context.Background())
	d := &dispatcher{
		hh: hh, db: db, views: views,
		pokeCh: make(chan struct{}, 1),
		cmds:   make(chan func()),
		ctx:    ctx, cancel: cancel,
		subs: map[*subscription]struct{}{},
	}
	// Start od bieżącego seq: wcześniejsze zmiany nikogo tu nie interesują
	// (każda subskrypcja i tak zaczyna od snapshotu). Licznik jest
	// podbijany pod blokadą wiersza, więc wszystkie seq <= odczytanego są
	// już skommitowane.
	err := db.WithContext(ctx).Raw("SELECT seq FROM households WHERE id = ?", hh).Scan(&d.lastSeq).Error
	if err != nil {
		cancel()
		return nil, err
	}
	go d.run()
	return d, nil
}

func (d *dispatcher) stop() { d.cancel() }

func (d *dispatcher) poke() {
	select {
	case d.pokeCh <- struct{}{}:
	default: // już jest zaległe szturchnięcie — koalescencja
	}
}

// do wykonuje fn w goroutine dispatchera i czeka na wynik.
func (d *dispatcher) do(fn func()) bool {
	done := make(chan struct{})
	select {
	case d.cmds <- func() { fn(); close(done) }:
		<-done
		return true
	case <-d.ctx.Done():
		return false
	}
}

func (d *dispatcher) run() {
	t := time.NewTicker(safetyPollInterval)
	defer t.Stop()
	for {
		select {
		case <-d.ctx.Done():
			return
		case fn := <-d.cmds:
			fn()
		case <-d.pokeCh:
			d.load()
		case <-t.C:
			d.load()
		}
	}
}

func (d *dispatcher) load() {
	for {
		var rows []*core.Change
		err := d.db.WithContext(d.ctx).Raw(`
			SELECT household_id, seq, entity, entity_id, op, before, after, actor_id, mutation_id, created_at
			FROM changes WHERE household_id = ? AND seq > ? ORDER BY seq LIMIT ?`,
			d.hh, d.lastSeq, loadBatch).Scan(&rows).Error
		if err != nil {
			if d.ctx.Err() == nil {
				slog.Error("realtime: odczyt changes", "hh", d.hh, "err", err)
			}
			return
		}
		for _, ch := range rows {
			for s := range d.subs {
				d.deliver(s, ch)
			}
			d.lastSeq = ch.Seq
		}
		if len(rows) < loadBatch {
			return
		}
	}
}

func (d *dispatcher) deliver(s *subscription, ch *core.Change) {
	if s.pending {
		if len(s.buf) >= maxPendingBuffer {
			s.conn.closeSlow()
			return
		}
		s.buf = append(s.buf, ch)
		return
	}
	d.emit(s, ch)
}

func (d *dispatcher) emit(s *subscription, ch *core.Change) {
	if ch.Seq <= s.snapSeq {
		return // już zawarte w snapshocie
	}
	switch core.Classify(s.view, s.params, ch) {
	case core.Upsert:
		s.conn.send(changeMsg{
			T: "upsert", Sub: s.id, Op: ch.Op, Seq: ch.Seq, Entity: ch.Entity, ID: ch.EntityID,
			Row: ch.After, Actor: ch.ActorID, Mutation: ch.MutationID,
		})
	case core.Remove:
		s.conn.send(changeMsg{
			T: "remove", Sub: s.id, Op: ch.Op, Seq: ch.Seq, Entity: ch.Entity, ID: ch.EntityID,
			Row: ch.Before, Actor: ch.ActorID, Mutation: ch.MutationID,
		})
	}
}

// --- operacje wołane z goroutine połączenia ---

// register dodaje subskrypcję w stanie „pending”. Od tej chwili każda nowa
// zmiana trafia do jej bufora — snapshot robiony PO rejestracji nie może
// więc niczego przegapić.
func (d *dispatcher) register(s *subscription) bool {
	s.pending = true
	return d.do(func() { d.subs[s] = struct{}{} })
}

// activate: snapshot (stan na seq) został wysłany — wypuść z bufora tylko
// nowsze zmiany i przejdź w tryb na żywo.
func (d *dispatcher) activate(s *subscription, seq int64) {
	d.do(func() {
		if _, ok := d.subs[s]; !ok {
			return
		}
		s.snapSeq = seq
		s.pending = false
		for _, ch := range s.buf {
			d.emit(s, ch)
		}
		s.buf = nil
	})
}

func (d *dispatcher) unregister(s *subscription) {
	d.do(func() { delete(d.subs, s) })
}
