package realtime

import (
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"
)

// presenceGrace is how long a member stays online after their last
// connection closes, so reconnect blips don't flicker. Tests shorten it
// through Hub.SetPresenceGrace.
const presenceGrace = 5 * time.Second

type presenceMsg struct {
	T      string      `json:"t"`
	Online []uuid.UUID `json:"online"`
}

// presence tracks which members of each household are online: a member is
// online while at least one connection of theirs is open, and until the grace
// period after the last one closes. In memory, single server instance.
type presence struct {
	mu    sync.Mutex
	grace time.Duration
	hh    map[uuid.UUID]*hhPresence
}

type hhPresence struct {
	conns  map[*Conn]struct{}
	count  map[uuid.UUID]int // member -> open connections
	online map[uuid.UUID]bool
	timers map[uuid.UUID]*time.Timer // pending offline per member
}

func newPresence() *presence {
	return &presence{grace: presenceGrace, hh: map[uuid.UUID]*hhPresence{}}
}

func (p *presence) setGrace(d time.Duration) {
	p.mu.Lock()
	p.grace = d
	p.mu.Unlock()
}

// add registers an authenticated connection, sends it the current set and
// tells the household when the member just came online.
func (p *presence) add(c *Conn) {
	hh, m := c.actor.HouseholdID, c.actor.MemberID
	p.mu.Lock()
	defer p.mu.Unlock()
	h := p.hh[hh]
	if h == nil {
		h = &hhPresence{conns: map[*Conn]struct{}{}, count: map[uuid.UUID]int{},
			online: map[uuid.UUID]bool{}, timers: map[uuid.UUID]*time.Timer{}}
		p.hh[hh] = h
	}
	h.conns[c] = struct{}{}
	h.count[m]++
	if t := h.timers[m]; t != nil { // came back within the grace period
		t.Stop()
		delete(h.timers, m)
	}
	if !h.online[m] {
		h.online[m] = true
		p.broadcast(h)
		return
	}
	c.send(h.msg())
}

// remove deregisters a connection; the member goes offline after the grace
// period unless another connection of theirs opens.
func (p *presence) remove(c *Conn) {
	hh, m := c.actor.HouseholdID, c.actor.MemberID
	p.mu.Lock()
	defer p.mu.Unlock()
	h := p.hh[hh]
	if h == nil {
		return
	}
	delete(h.conns, c)
	if h.count[m]--; h.count[m] > 0 {
		return
	}
	delete(h.count, m)
	var t *time.Timer
	t = time.AfterFunc(p.grace, func() {
		p.mu.Lock()
		defer p.mu.Unlock()
		if h.timers[m] != t { // superseded
			return
		}
		delete(h.timers, m)
		delete(h.online, m)
		p.broadcast(h)
		p.gc(hh, h)
	})
	h.timers[m] = t
}

func (p *presence) gc(hh uuid.UUID, h *hhPresence) {
	if len(h.conns) == 0 && len(h.online) == 0 && p.hh[hh] == h {
		delete(p.hh, hh)
	}
}

func (h *hhPresence) msg() presenceMsg {
	ids := make([]uuid.UUID, 0, len(h.online))
	for id := range h.online {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i].String() < ids[j].String() })
	return presenceMsg{T: "presence", Online: ids}
}

// broadcast: p.mu held.
func (p *presence) broadcast(h *hhPresence) {
	m := h.msg()
	for c := range h.conns {
		c.send(m)
	}
}
