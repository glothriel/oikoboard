package app_test

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"

	"oikoboard/server/internal/seed"
)

// fakeIDP udaje Google: discovery, klucze i endpoint tokenów (sprawdza
// PKCE). Endpoint autoryzacji nie jest potrzebny — test sam „wraca” z
// Google na callback.
type fakeIDP struct {
	t        *testing.T
	srv      *httptest.Server
	clientID string
	key      *rsa.PrivateKey

	mu    sync.Mutex
	codes map[string]idpGrant // code → co Google wie o logowaniu
}

type idpGrant struct {
	challenge, nonce string
	sub, email       string
	verified         bool
}

func newFakeIDP(t *testing.T) *fakeIDP {
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	f := &fakeIDP{t: t, clientID: "oiko-test.apps", key: key, codes: map[string]idpGrant{}}
	mux := http.NewServeMux()
	f.srv = httptest.NewServer(mux)
	t.Cleanup(f.srv.Close)
	mux.HandleFunc("/.well-known/openid-configuration", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"issuer": f.srv.URL, "authorization_endpoint": f.srv.URL + "/auth",
			"token_endpoint": f.srv.URL + "/token", "jwks_uri": f.srv.URL + "/keys",
			"id_token_signing_alg_values_supported": []string{"RS256"},
		})
	})
	mux.HandleFunc("/keys", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(jose.JSONWebKeySet{Keys: []jose.JSONWebKey{
			{Key: &key.PublicKey, KeyID: "k1", Algorithm: "RS256", Use: "sig"},
		}})
	})
	mux.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		r.ParseForm()
		f.mu.Lock()
		g, ok := f.codes[r.Form.Get("code")]
		delete(f.codes, r.Form.Get("code"))
		f.mu.Unlock()
		h := sha256.Sum256([]byte(r.Form.Get("code_verifier")))
		if !ok || base64.RawURLEncoding.EncodeToString(h[:]) != g.challenge {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{"error": "invalid_grant"})
			return
		}
		sig, _ := jose.NewSigner(jose.SigningKey{Algorithm: jose.RS256, Key: key},
			(&jose.SignerOptions{}).WithType("JWT").WithHeader("kid", "k1"))
		idt, _ := jwt.Signed(sig).Claims(map[string]any{
			"iss": f.srv.URL, "aud": f.clientID, "sub": g.sub, "email": g.email,
			"email_verified": g.verified, "nonce": g.nonce, "name": "Jan Testowy",
			"iat": time.Now().Unix(), "exp": time.Now().Add(time.Hour).Unix(),
		}).Serialize()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"access_token": "at", "token_type": "Bearer", "expires_in": 3600, "id_token": idt,
		})
	})
	return f
}

var noRedirect = &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error {
	return http.ErrUseLastResponse
}}

func pkce() (verifier, challenge string) {
	b := make([]byte, 32)
	rand.Read(b)
	verifier = base64.RawURLEncoding.EncodeToString(b)
	h := sha256.Sum256([]byte(verifier))
	return verifier, base64.RawURLEncoding.EncodeToString(h[:])
}

// googleLogin przechodzi cały flow jak przeglądarka i zwraca adres, na
// który backend odesłał na końcu (adres aplikacji z ?code= albo ?error=).
func (e *env) googleLogin(returnTo, appChallenge, sub, email string, verified bool) *url.URL {
	e.t.Helper()
	start := e.srv.URL + "/api/v1/auth/google/start?" + url.Values{
		"return": {returnTo}, "challenge": {appChallenge}}.Encode()
	res, err := noRedirect.Get(start)
	if err != nil {
		e.t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusFound {
		e.t.Fatalf("start: %d", res.StatusCode)
	}
	toGoogle, _ := url.Parse(res.Header.Get("Location"))
	q := toGoogle.Query()
	if q.Get("code_challenge_method") != "S256" || q.Get("nonce") == "" ||
		q.Get("redirect_uri") != "http://api.test/api/v1/auth/google/callback" {
		e.t.Fatalf("zły redirect do Google: %s", toGoogle)
	}
	// „Google”: użytkownik wybrał konto.
	code := "g-" + q.Get("state")[:8]
	e.idp.mu.Lock()
	e.idp.codes[code] = idpGrant{q.Get("code_challenge"), q.Get("nonce"), sub, email, verified}
	e.idp.mu.Unlock()

	req, _ := http.NewRequest("GET", e.srv.URL+"/api/v1/auth/google/callback?"+url.Values{
		"state": {q.Get("state")}, "code": {code}}.Encode(), nil)
	for _, c := range res.Cookies() {
		req.AddCookie(c)
	}
	res, err = noRedirect.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusFound {
		e.t.Fatalf("callback: %d", res.StatusCode)
	}
	back, _ := url.Parse(res.Header.Get("Location"))
	return back
}

type meRes struct {
	User struct {
		Email string
		Name  string
	}
	MemberID  *string `json:"member_id"`
	Household *struct{ Name string }
	Members   []struct {
		Name       string
		HasAccount bool `json:"has_account"`
	}
	Memberships []struct {
		MemberID string `json:"member_id"`
	}
}

func TestGoogleLogin(t *testing.T) {
	e := setup(t)
	if err := seed.Family(context.Background(), e.db, "Nasza rodzina"); err != nil {
		t.Fatal(err)
	}
	if err := seed.LinkEmail(context.Background(), e.db, "Nasza rodzina", "Tata", "Tata@Example.com"); err != nil {
		t.Fatal(err)
	}
	anon := &client{e: e}
	exchange := func(code, verifier string) (int, string) {
		var res struct{ Token string }
		st := anon.do("POST", "/auth/exchange", map[string]any{"code": code, "verifier": verifier}, &res)
		return st, res.Token
	}

	verifier, challenge := pkce()
	back := e.googleLogin("http://localhost:5555/", challenge, "google-sub-1", "tata@example.com", true)
	if back.Host != "localhost:5555" || back.Query().Get("code") == "" {
		t.Fatalf("powrót: %s", back)
	}
	code := back.Query().Get("code")

	// Kod bez właściwego verifiera jest bezużyteczny — i od razu spalony.
	if st, _ := exchange(code, "zly-verifier"); st != http.StatusBadRequest {
		t.Fatalf("zły verifier: %d", st)
	}
	if st, _ := exchange(code, verifier); st != http.StatusBadRequest {
		t.Fatalf("drugi raz ten sam kod: %d", st)
	}

	// Od nowa, poprawnie.
	verifier, challenge = pkce()
	back = e.googleLogin("http://localhost:5555/", challenge, "google-sub-1", "tata@example.com", true)
	st, token := exchange(back.Query().Get("code"), verifier)
	if st != http.StatusOK || token == "" {
		t.Fatalf("exchange: %d", st)
	}
	tata := &client{e: e, token: token}
	var me meRes
	tata.do("GET", "/me", nil, &me)
	if me.User.Email != "tata@example.com" || me.Household == nil || me.Household.Name != "Nasza rodzina" {
		t.Fatalf("e-mail nie przypiął Taty: %+v", me)
	}
	if st := tata.do("GET", "/views/todo.lists", nil, nil); st != http.StatusOK {
		t.Fatalf("widok: %d", st)
	}

	// Ponowne logowanie tym samym kontem Google = to samo konto, nawet po
	// zmianie e-maila.
	verifier, challenge = pkce()
	back = e.googleLogin("oikoboard://auth", challenge, "google-sub-1", "nowy@example.com", true)
	if back.Scheme != "oikoboard" {
		t.Fatalf("powrót android: %s", back)
	}
	_, token = exchange(back.Query().Get("code"), verifier)
	again := &client{e: e, token: token}
	me = meRes{}
	again.do("GET", "/me", nil, &me)
	if me.User.Email != "nowy@example.com" || me.Household == nil {
		t.Fatalf("drugie logowanie: %+v", me)
	}

	// Niezweryfikowany e-mail — odmowa.
	_, challenge = pkce()
	back = e.googleLogin("http://localhost:5555/", challenge, "google-sub-2", "x@example.com", false)
	if back.Query().Get("error") != "login_failed" {
		t.Fatalf("niezweryfikowany: %s", back)
	}

	// Niedozwolony adres powrotu.
	res, _ := noRedirect.Get(e.srv.URL + "/api/v1/auth/google/start?" + url.Values{
		"return": {"https://evil.example/"}, "challenge": {challenge}}.Encode())
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("evil return: %d", res.StatusCode)
	}

	// Callback bez ciasteczka (inna przeglądarka / CSRF).
	res, _ = noRedirect.Get(e.srv.URL + "/api/v1/auth/google/callback?state=abc&code=x")
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("callback bez ciasteczka: %d", res.StatusCode)
	}
}

func TestOnboardingAndInvites(t *testing.T) {
	e := setup(t)
	mama := e.devLogin("mama@example.com")
	var me meRes
	mama.do("GET", "/me", nil, &me)
	if me.Household != nil || me.MemberID != nil {
		t.Fatalf("nowe konto nie powinno mieć rodziny: %+v", me)
	}
	if st := mama.do("GET", "/views/todo.lists", nil, nil); st != http.StatusForbidden {
		t.Fatalf("bez rodziny: %d", st)
	}
	if st := mama.do("POST", "/households", map[string]any{"name": "Kowalscy", "member_name": "Mama"}, nil); st != http.StatusCreated {
		t.Fatalf("załóż rodzinę: %d", st)
	}
	mama.do("GET", "/me", nil, &me)
	if me.Household == nil || me.Household.Name != "Kowalscy" || len(me.Members) != 1 || !me.Members[0].HasAccount {
		t.Fatalf("po założeniu: %+v", me)
	}

	// Zaproszenie dla nowej osoby.
	var inv struct{ Token, ID string }
	if st := mama.do("POST", "/invites", map[string]any{}, &inv); st != http.StatusCreated || inv.Token == "" {
		t.Fatalf("zaproszenie: %d", st)
	}
	tata := e.devLogin("tata@example.com")
	var preview struct {
		HouseholdName string `json:"household_name"`
		InvitedBy     string `json:"invited_by"`
	}
	tata.do("GET", "/invites/"+inv.Token, nil, &preview)
	if preview.HouseholdName != "Kowalscy" || preview.InvitedBy != "Mama" {
		t.Fatalf("podgląd: %+v", preview)
	}
	if st := tata.do("POST", "/invites/"+inv.Token+"/accept", map[string]any{"name": "Tata"}, nil); st != http.StatusOK {
		t.Fatalf("dołącz: %d", st)
	}
	// Jednorazowe.
	ola := e.devLogin("ola@example.com")
	if st := ola.do("POST", "/invites/"+inv.Token+"/accept", nil, nil); st != http.StatusNotFound {
		t.Fatalf("drugie użycie: %d", st)
	}

	// Obie osoby widzą te same dane na żywo.
	w := tata.ws()
	w.sub("l", "todo.lists", nil)
	var list struct{ ID string }
	if st := mama.do("POST", "/todo/lists", map[string]any{"name": "Zakupy"}, &list); st != http.StatusCreated {
		t.Fatalf("lista: %d", st)
	}
	if m := w.next(); m.T != "upsert" || m.ID != list.ID {
		t.Fatalf("tata nie dostał listy mamy: %+v", m)
	}

	// Zaproszenie dla członka bez konta (Ola dodana „ręcznie”).
	mama.do("GET", "/me", nil, &me)
	var hhID string
	e.db.Raw("SELECT household_id FROM members WHERE name = 'Mama'").Scan(&hhID)
	e.db.Exec("INSERT INTO members (household_id, name) VALUES (?, 'Ola')", hhID)
	var olaID string
	e.db.Raw("SELECT id FROM members WHERE name = 'Ola'").Scan(&olaID)
	if st := mama.do("POST", "/invites", map[string]any{"member_id": olaID}, &inv); st != http.StatusCreated {
		t.Fatalf("zaproszenie dla Oli: %d", st)
	}
	if st := ola.do("POST", "/invites/"+inv.Token+"/accept", nil, nil); st != http.StatusOK {
		t.Fatalf("Ola dołącza: %d", st)
	}
	me = meRes{}
	ola.do("GET", "/me", nil, &me)
	if me.MemberID == nil || *me.MemberID != olaID {
		t.Fatalf("Ola powinna przejąć swojego członka: %+v", me)
	}

	// Zaproszenie z innej rodziny nie da dostępu do Kowalskich, a druga
	// rodzina jednego konta — przełączanie.
	other := e.newFamily("Nowakowie")
	other.do("POST", "/invites", map[string]any{}, &inv)
	ola.do("POST", "/invites/"+inv.Token+"/accept", nil, nil)
	me = meRes{}
	ola.do("GET", "/me", nil, &me)
	if me.Household.Name != "Nowakowie" || len(me.Memberships) != 2 {
		t.Fatalf("dwie rodziny: %+v", me)
	}
	if st := ola.do("POST", "/auth/switch", map[string]any{"member_id": olaID}, nil); st != http.StatusNoContent {
		t.Fatalf("switch: %d", st)
	}
	ola.do("GET", "/me", nil, &me)
	if me.Household.Name != "Kowalscy" {
		t.Fatalf("po przełączeniu: %+v", me)
	}
	// Nie da się przełączyć na cudzego członka.
	if st := mama.do("POST", "/auth/switch", map[string]any{"member_id": olaID}, nil); st != http.StatusNotFound {
		t.Fatalf("cudzy switch: %d", st)
	}

	// Wylogowanie unieważnia token.
	tata.do("POST", "/auth/logout", nil, nil)
	if st := tata.do("GET", "/me", nil, nil); st != http.StatusUnauthorized {
		t.Fatalf("po wylogowaniu: %d", st)
	}
}
