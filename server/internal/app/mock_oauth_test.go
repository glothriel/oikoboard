package app_test

import (
	"context"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"testing"

	"oikoboard/server/internal/core"
	"oikoboard/server/internal/seed"
)

// mockLogin przechodzi udawane Google jak przeglądarka: start → strona
// wyboru → callback z wybranym parametrem → exchange.
func (e *env) mockLogin(pick func(page string) url.Values) *client {
	e.t.Helper()
	verifier, challenge := pkce()
	res, err := noRedirect.Get(e.srv.URL + "/api/v1/auth/google/start?" + url.Values{
		"return": {"http://localhost:5555/"}, "challenge": {challenge}}.Encode())
	if err != nil || res.StatusCode != http.StatusFound {
		e.t.Fatalf("start: %v %v", err, res.Status)
	}
	res.Body.Close()
	cookies := res.Cookies()
	get := func(path string) *http.Response {
		req, _ := http.NewRequest("GET", e.srv.URL+path, nil)
		for _, c := range cookies {
			req.AddCookie(c)
		}
		r, err := noRedirect.Do(req)
		if err != nil {
			e.t.Fatal(err)
		}
		return r
	}
	picker := res.Header.Get("Location")
	if !strings.HasPrefix(picker, "/api/v1/auth/google/mock?state=") {
		e.t.Fatalf("start nie prowadzi na mocka: %s", picker)
	}
	res = get(picker)
	body, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		e.t.Fatalf("strona mocka: %d", res.StatusCode)
	}
	q := pick(string(body))
	q.Set("state", strings.TrimPrefix(picker, "/api/v1/auth/google/mock?state="))
	q.Set("state", must(url.QueryUnescape(q.Get("state"))))
	res = get("/api/v1/auth/google/callback?" + q.Encode())
	res.Body.Close()
	back, _ := url.Parse(res.Header.Get("Location"))
	if back.Query().Get("code") == "" {
		e.t.Fatalf("callback: %d %s", res.StatusCode, back)
	}
	c := &client{e: e}
	var tok struct{ Token string }
	if st := c.do("POST", "/auth/exchange", map[string]any{"code": back.Query().Get("code"), "verifier": verifier}, &tok); st != http.StatusOK {
		e.t.Fatalf("exchange: %d", st)
	}
	c.token = tok.Token
	return c
}

func must[T any](v T, err error) T {
	if err != nil {
		panic(err)
	}
	return v
}

var memberLink = regexp.MustCompile(`(?s)member=([0-9a-f-]{36})"[^>]*>.*?<span>(\w+)`)

func TestMockOAuth(t *testing.T) {
	e := setup(t, func(c *core.AuthConfig) { c.MockOAuth = true; c.Google = nil })
	if err := seed.Family(context.Background(), e.db, "Nasza rodzina"); err != nil {
		t.Fatal(err)
	}
	var cfg struct{ Google bool }
	(&client{e: e}).do("GET", "/auth/config", nil, &cfg)
	if !cfg.Google {
		t.Fatal("aplikacja powinna widzieć przycisk Google")
	}

	// Członek bez konta → przejmuje go nowe konto.
	pickMember := func(name string) func(string) url.Values {
		return func(page string) url.Values {
			for _, m := range memberLink.FindAllStringSubmatch(page, -1) {
				if m[2] == name {
					return url.Values{"member": {m[1]}}
				}
			}
			t.Fatalf("brak %s na stronie:\n%s", name, page)
			return nil
		}
	}
	mama := e.mockLogin(pickMember("Mama"))
	var me meRes
	mama.do("GET", "/me", nil, &me)
	if me.Household == nil || me.Household.Name != "Nasza rodzina" || me.User.Name != "Mama" {
		t.Fatalf("mama: %+v", me)
	}

	// Mama ma już konto — ponownie wybierana jako konto (user=).
	var userID string
	e.db.Raw("SELECT user_id FROM members WHERE name = 'Mama'").Scan(&userID)
	again := e.mockLogin(func(page string) url.Values {
		if strings.Contains(page, "member="+userID) || !strings.Contains(page, "user="+userID) {
			t.Fatalf("mama powinna być na liście kont")
		}
		return url.Values{"user": {userID}}
	})
	me = meRes{}
	again.do("GET", "/me", nil, &me)
	if me.User.Name != "Mama" || me.Household == nil {
		t.Fatalf("ponownie mama: %+v", me)
	}

	// Nowa osoba (e-mail) przyjmuje zaproszenie.
	var inv struct{ Token string }
	if st := mama.do("POST", "/invites", map[string]any{}, &inv); st != http.StatusCreated {
		t.Fatalf("zaproszenie: %d", st)
	}
	babcia := e.mockLogin(func(string) url.Values { return url.Values{"email": {"Babcia@Example.com"}} })
	if st := babcia.do("POST", "/invites/"+inv.Token+"/accept", map[string]any{"name": "Babcia"}, nil); st != http.StatusOK {
		t.Fatalf("babcia dołącza: %d", st)
	}
	me = meRes{}
	babcia.do("GET", "/me", nil, &me)
	if me.User.Email != "babcia@example.com" || me.Household == nil || me.Household.Name != "Nasza rodzina" {
		t.Fatalf("babcia: %+v", me)
	}
}
