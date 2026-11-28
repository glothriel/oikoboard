package app_test

import (
	"net/http"
	"strings"
	"testing"
)

func TestFamilyMembersLive(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	b := e.newFamily("Nowakowie")

	assertPublic := func(r map[string]any) {
		t.Helper()
		for _, k := range []string{"user_id", "invite_email"} {
			if _, ok := r[k]; ok {
				t.Fatalf("leaked %s: %+v", k, r)
			}
		}
		for _, k := range []string{"id", "household_id", "name", "color", "created_at", "has_account", "picture"} {
			if _, ok := r[k]; !ok {
				t.Fatalf("missing %s: %+v", k, r)
			}
		}
	}

	w := a.ws()
	wb := b.ws()
	snap := w.sub("m", "family.members", nil)
	before := len(snap.Data["members"])
	if before == 0 {
		t.Fatalf("empty snapshot")
	}
	for _, r := range snap.Data["members"] {
		assertPublic(r)
	}
	wb.sub("m", "family.members", nil)

	// insert via invite accept
	var inv struct{ Token, ID string }
	if st := a.do("POST", "/invites", map[string]any{}, &inv); st != http.StatusCreated {
		t.Fatalf("invite: %d", st)
	}
	newbie := e.devLogin("newbie@example.com")
	if st := newbie.do("POST", "/invites/"+inv.Token+"/accept", map[string]any{"name": "Newbie"}, nil); st != http.StatusOK {
		t.Fatalf("accept: %d", st)
	}
	// the invite placeholder is inserted (and possibly updated): wait for the
	// upsert that carries the account
	var id string
	for i := 0; i < 5; i++ {
		m := w.next()
		if m.T != "upsert" || m.Entity != "members" {
			t.Fatalf("change: %+v", m)
		}
		assertPublic(m.Row)
		if m.Row["name"] == "Newbie" && m.Row["has_account"] == true {
			id = m.ID
			break
		}
	}
	if id == "" {
		t.Fatal("no upsert with account")
	}
	w.expectNone()

	// picture follows the account
	if err := e.db.Exec(`UPDATE users SET picture = 'https://pic.example/1.png' WHERE email = 'newbie@example.com'`).Error; err != nil {
		t.Fatal(err)
	}
	m := w.next()
	if m.ID != id || m.Row["picture"] != "https://pic.example/1.png" {
		t.Fatalf("picture: %+v", m)
	}
	assertPublic(m.Row)

	// rename via SQL
	if err := e.db.Exec(`UPDATE members SET name = 'Renamed' WHERE id = ?`, id).Error; err != nil {
		t.Fatal(err)
	}
	if m := w.next(); m.ID != id || m.Row["name"] != "Renamed" {
		t.Fatalf("rename: %+v", m)
	}

	// /me still returns picture
	var me struct {
		Members []struct {
			ID      string
			Picture *string
		}
	}
	a.do("GET", "/me", nil, &me)
	found := false
	for _, m := range me.Members {
		if m.ID == id {
			found = m.Picture != nil && strings.HasSuffix(*m.Picture, "1.png")
		}
	}
	if !found {
		t.Fatalf("/me picture: %+v", me)
	}

	// delete
	if err := e.db.Exec(`DELETE FROM members WHERE id = ?`, id).Error; err != nil {
		t.Fatal(err)
	}
	m = w.next()
	if m.T != "remove" || m.ID != id {
		t.Fatalf("delete: %+v", m)
	}
	assertPublic(m.Row)

	// the other household saw nothing
	wb.expectNone()
}
