package app_test

import (
	"net/http"
	"slices"
	"testing"
	"time"
)

// presenceOf waits for the next presence message and returns its online set.
func (w *wsClient) presenceOf() []string {
	w.t.Helper()
	select {
	case m := <-w.presence:
		return m.Online
	case <-time.After(5 * time.Second):
		w.t.Fatal("timeout: no presence message")
	}
	return nil
}

func (w *wsClient) expectNoPresence(d time.Duration) {
	w.t.Helper()
	select {
	case m := <-w.presence:
		w.t.Fatalf("unexpected presence: %+v", m)
	case <-time.After(d):
	}
}

func TestPresence(t *testing.T) {
	e := setup(t)
	const grace = 400 * time.Millisecond
	e.app.Hub.SetPresenceGrace(grace)
	a := e.newFamily("Kowalscy")
	other := e.newFamily("Nowakowie")

	var inv struct{ Token, ID string }
	if st := a.do("POST", "/invites", map[string]any{}, &inv); st != http.StatusCreated {
		t.Fatalf("invite: %d", st)
	}
	b := e.devLogin("bpresence@example.com")
	if st := b.do("POST", "/invites/"+inv.Token+"/accept", map[string]any{"name": "Bea"}, nil); st != http.StatusOK {
		t.Fatalf("accept: %d", st)
	}
	var meA, meB meRes
	a.do("GET", "/me", nil, &meA)
	b.do("GET", "/me", nil, &meB)
	if meA.MemberID == nil || meB.MemberID == nil || *meA.MemberID == *meB.MemberID {
		t.Fatalf("member ids: %v %v", meA.MemberID, meB.MemberID)
	}
	idA, idB := *meA.MemberID, *meB.MemberID

	// B connects first: sees only itself.
	wb := b.ws()
	if got := wb.presenceOf(); !slices.Equal(got, []string{idB}) {
		t.Fatalf("B initial: %v", got)
	}
	// A connects -> B sees A online; A's first message lists both.
	wa := a.ws()
	if got := wa.presenceOf(); len(got) != 2 {
		t.Fatalf("A initial: %v", got)
	}
	if got := wb.presenceOf(); len(got) != 2 || !slices.Contains(got, idA) {
		t.Fatalf("B after A: %v", got)
	}
	// Another household is unaffected.
	wo := other.ws()
	if got := wo.presenceOf(); len(got) != 1 {
		t.Fatalf("other household: %v", got)
	}
	wo.expectNoPresence(100 * time.Millisecond)

	// A second connection of the same account counts once, no broadcast.
	wa2 := a.ws()
	if got := wa2.presenceOf(); len(got) != 2 {
		t.Fatalf("A second conn: %v", got)
	}
	wb.expectNoPresence(100 * time.Millisecond)

	// Closing one of two connections changes nothing.
	wa2.conn.CloseNow()
	wb.expectNoPresence(grace + 200*time.Millisecond)

	// Reconnect within the grace: no offline broadcast.
	wa.conn.CloseNow()
	time.Sleep(grace / 4)
	wa3 := a.ws()
	wa3.presenceOf()
	wb.expectNoPresence(grace + 200*time.Millisecond)

	// Leaving for good: offline only after the grace.
	wa3.conn.CloseNow()
	wb.expectNoPresence(grace / 4)
	if got := wb.presenceOf(); !slices.Equal(got, []string{idB}) {
		t.Fatalf("after A left: %v", got)
	}
	wo.expectNoPresence(100 * time.Millisecond)
}
