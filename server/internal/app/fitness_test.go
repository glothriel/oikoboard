package app_test

import (
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
)

type meMembers struct {
	MemberID string `json:"member_id"`
	Members  []struct {
		ID   string
		Name string
	}
}

func (c *client) otherMember() (self, other string) {
	var me meMembers
	c.do("GET", "/me", nil, &me)
	for _, m := range me.Members {
		if m.ID != me.MemberID {
			return me.MemberID, m.ID
		}
	}
	c.e.t.Fatal("no other member")
	return
}

func measurement(member string, kg float64) map[string]any {
	return map[string]any{"id": uuid.NewString(), "member_id": member,
		"measured_at": time.Now().UTC().Format(time.RFC3339), "weight_kg": kg, "source": "manual"}
}

func TestFitnessMeasurements(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	self, other := a.otherMember()

	w := a.ws()
	if snap := w.sub("m", "fitness.measurements", nil); len(snap.Data["measurements"]) != 0 {
		t.Fatalf("snapshot: %+v", snap.Data)
	}

	// for another member; retried with the same id it is a no-op
	body := measurement(other, 70.5)
	body["impedance"] = 480
	body["fat_pct"] = 21.5
	var got struct {
		ID       string
		MemberID string `json:"member_id"`
	}
	if st := a.do("POST", "/fitness/measurements", body, &got); st != http.StatusCreated || got.MemberID != other {
		t.Fatalf("create: %d %+v", st, got)
	}
	if m := w.next(); m.Entity != "measurements" || m.ID != got.ID {
		t.Fatalf("change: %+v", m)
	}
	if st := a.do("POST", "/fitness/measurements", body, nil); st != http.StatusCreated {
		t.Fatalf("retry: %d", st)
	}
	w.expectNone()
	_, d := a.view("fitness.measurements", nil)
	if len(d["measurements"]) != 1 || d["measurements"][0]["fat_pct"] != 21.5 || d["measurements"][0]["bmi"] != nil {
		t.Fatalf("view: %+v", d)
	}

	// same id, other household: conflict; foreign member and bad values: rejected
	b := e.newFamily("Nowakowie")
	if st := b.do("POST", "/fitness/measurements", body, nil); st != http.StatusBadRequest && st != http.StatusConflict {
		t.Fatalf("foreign member/id: %d", st)
	}
	if st := a.do("POST", "/fitness/measurements", measurement(uuid.NewString(), 70), nil); st != http.StatusBadRequest {
		t.Fatalf("unknown member: %d", st)
	}
	bSelf, _ := b.otherMember()
	if st := a.do("POST", "/fitness/measurements", measurement(bSelf, 70), nil); st != http.StatusBadRequest {
		t.Fatalf("foreign household member: %d", st)
	}
	for _, kg := range []float64{0, -3, 1000} {
		if st := a.do("POST", "/fitness/measurements", measurement(self, kg), nil); st != http.StatusBadRequest {
			t.Fatalf("weight %v: %d", kg, st)
		}
	}
	bad := measurement(self, 70)
	bad["fat_pct"] = 150
	if st := a.do("POST", "/fitness/measurements", bad, nil); st != http.StatusBadRequest {
		t.Fatalf("fat_pct: %d", st)
	}
	bad = measurement(self, 70)
	bad["source"] = "other"
	if st := a.do("POST", "/fitness/measurements", bad, nil); st != http.StatusBadRequest {
		t.Fatalf("source: %d", st)
	}

	// another household can't see or delete it; any member of the household can
	if _, d := b.view("fitness.measurements", nil); len(d["measurements"]) != 0 {
		t.Fatalf("other household sees: %+v", d)
	}
	if st := b.do("DELETE", "/fitness/measurements/"+got.ID, nil, nil); st != http.StatusNotFound {
		t.Fatalf("other household delete: %d", st)
	}
	if st := a.do("DELETE", "/fitness/measurements/"+got.ID, nil, nil); st != http.StatusNoContent {
		t.Fatalf("delete: %d", st)
	}
	if m := w.next(); m.Entity != "measurements" || m.ID != got.ID {
		t.Fatalf("delete change: %+v", m)
	}
}

func TestFitnessProfiles(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	self, other := a.otherMember()
	profile := map[string]any{"sex": "male", "birth_date": "1985-04-12", "height_cm": 180}

	w := a.ws()
	w.sub("p", "fitness.profiles", nil)
	var got struct {
		ID       string
		HeightCm float64 `json:"height_cm"`
	}
	if st := a.do("POST", "/fitness/profiles", profile, &got); st != http.StatusOK || got.ID != self {
		t.Fatalf("create: %d %+v", st, got)
	}
	if m := w.next(); m.Entity != "fitness_profiles" || m.ID != self {
		t.Fatalf("change: %+v", m)
	}
	profile["height_cm"] = 181
	if st := a.do("POST", "/fitness/profiles", profile, &got); st != http.StatusOK || got.HeightCm != 181 {
		t.Fatalf("upsert: %d %+v", st, got)
	}
	if _, d := a.view("fitness.profiles", nil); len(d["fitness_profiles"]) != 1 {
		t.Fatalf("view: %+v", d)
	}

	// only the own profile: the body has no member id, so another member's is unreachable
	if st := a.do("POST", "/fitness/profiles", map[string]any{"id": other, "member_id": other,
		"sex": "female", "birth_date": "1990-01-01", "height_cm": 165}, nil); st != http.StatusOK {
		t.Fatalf("own with foreign id in body: %d", st)
	}
	if _, d := a.view("fitness.profiles", nil); len(d["fitness_profiles"]) != 1 || d["fitness_profiles"][0]["id"] != self {
		t.Fatalf("foreign id was honoured: %+v", d)
	}

	for _, bad := range []map[string]any{
		{"sex": "x", "birth_date": "1985-04-12", "height_cm": 180},
		{"sex": "male", "birth_date": "2999-01-01", "height_cm": 180},
		{"sex": "male", "birth_date": "1985-04-12", "height_cm": 10},
	} {
		if st := a.do("POST", "/fitness/profiles", bad, nil); st != http.StatusBadRequest {
			t.Fatalf("%+v: %d", bad, st)
		}
	}
}

func TestFitnessMemberDeleteCascades(t *testing.T) {
	e := setup(t)
	a := e.newFamily("Kowalscy")
	_, other := a.otherMember()
	if st := a.do("POST", "/fitness/measurements", measurement(other, 60), nil); st != http.StatusCreated {
		t.Fatalf("create: %d", st)
	}
	if err := e.db.Exec("INSERT INTO fitness_profiles (id, household_id, sex, birth_date, height_cm) "+
		"SELECT id, household_id, 'female', '1990-01-01', 165 FROM members WHERE id = ?", other).Error; err != nil {
		t.Fatal(err)
	}
	if err := e.db.Exec("DELETE FROM members WHERE id = ?", other).Error; err != nil {
		t.Fatal(err)
	}
	var n int64
	e.db.Raw("SELECT (SELECT count(*) FROM measurements WHERE member_id = ?) + "+
		"(SELECT count(*) FROM fitness_profiles WHERE id = ?)", other, other).Scan(&n)
	if n != 0 {
		t.Fatalf("rows left: %d", n)
	}
}

func TestFitnessDelegatedRefused(t *testing.T) {
	e := setup(t, withSealer, mockCalendars)
	a := e.newFamily("Kowalscy")
	self, _ := a.otherMember()
	token, _ := e.oauthToken(a)
	tc := &client{e: e, token: token}

	if st := tc.do("GET", "/views/todo.lists", nil, nil); st != http.StatusOK {
		t.Fatalf("other view: %d", st)
	}
	for _, v := range []string{"fitness.measurements", "fitness.profiles"} {
		if st := tc.do("GET", "/views/"+v, nil, nil); st != http.StatusForbidden {
			t.Fatalf("%s: %d", v, st)
		}
	}
	for _, c := range []struct{ method, path string }{
		{"POST", "/fitness/measurements"}, {"DELETE", "/fitness/measurements/" + uuid.NewString()}, {"POST", "/fitness/profiles"},
	} {
		if st := tc.do(c.method, c.path, measurement(self, 70), nil); st != http.StatusForbidden {
			t.Fatalf("%s %s: %d", c.method, c.path, st)
		}
	}
}
