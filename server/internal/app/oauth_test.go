package app_test

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"testing"
)

// oauthClient walks the MCP authorization flow the way ChatGPT does:
// discovery, dynamic registration, authorize (sign-in + consent), token.
type oauthTokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
}

func (e *env) get(path string, cookies []*http.Cookie) *http.Response {
	e.t.Helper()
	req, _ := http.NewRequest("GET", e.srv.URL+path, nil)
	for _, c := range cookies {
		req.AddCookie(c)
	}
	res, err := noRedirect.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	return res
}

func location(t *testing.T, res *http.Response) *url.URL {
	t.Helper()
	if res.StatusCode != http.StatusFound {
		t.Fatalf("expected a redirect, got %s", res.Status)
	}
	u, err := url.Parse(res.Header.Get("Location"))
	if err != nil {
		t.Fatal(err)
	}
	return u
}

func pathQuery(u *url.URL) string { return u.Path + "?" + u.RawQuery }

func s256(v string) string {
	h := sha256.Sum256([]byte(v))
	return base64.RawURLEncoding.EncodeToString(h[:])
}

// authorize returns the redirect back to the client after consent (decision: allow|deny).
func (e *env) authorize(clientID, redirect, userID, decision string) *url.URL {
	t := e.t
	t.Helper()
	q := url.Values{"response_type": {"code"}, "client_id": {clientID}, "redirect_uri": {redirect},
		"code_challenge": {s256("verifier-0123456789-0123456789-0123456789")}, "code_challenge_method": {"S256"},
		"state": {"xyz"}, "scope": {"oikoboard"}, "resource": {e.srv.URL + "/mcp"}}
	// → sign-in start → (mock Google) → callback → /oauth/continue
	start := location(t, e.get("/oauth/authorize?"+q.Encode(), nil))
	res := e.get(pathQuery(start), nil)
	mock := location(t, res)
	cookies := res.Cookies()
	cb := e.srv.URL + "/api/v1/auth/google/callback?" + url.Values{"state": {mock.Query().Get("state")}, "user": {userID}}.Encode()
	req, _ := http.NewRequest("GET", cb, nil)
	for _, c := range cookies {
		req.AddCookie(c)
	}
	res, err := noRedirect.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	cont := location(t, res)
	if cont.Path != "/oauth/continue" {
		t.Fatalf("continue: %s", cont)
	}
	res = e.get(pathQuery(cont), nil)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("consent page: %s", res.Status)
	}
	var page strings.Builder
	buf := make([]byte, 64<<10)
	n, _ := res.Body.Read(buf)
	page.Write(buf[:n])
	res.Body.Close()
	field := func(name string) string {
		m := regexp.MustCompile(`name="` + name + `" value="([^"]+)"`).FindStringSubmatch(page.String())
		if m == nil {
			t.Fatalf("no %s in consent page", name)
		}
		return m[1]
	}
	form := url.Values{"req": {field("req")}, "csrf": {field("csrf")}, "member": {field("member")}, "decision": {decision}}
	req, _ = http.NewRequest("POST", e.srv.URL+"/oauth/consent", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	for _, c := range res.Cookies() {
		req.AddCookie(c)
	}
	res, err = noRedirect.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return location(t, res)
}

func (e *env) token(form url.Values) (int, oauthTokens) {
	e.t.Helper()
	res, err := http.PostForm(e.srv.URL+"/oauth/token", form)
	if err != nil {
		e.t.Fatal(err)
	}
	defer res.Body.Close()
	var tok oauthTokens
	json.NewDecoder(res.Body).Decode(&tok)
	return res.StatusCode, tok
}

func TestOAuthMCP(t *testing.T) {
	e := setup(t, withSealer, mockCalendars)
	a := e.newFamily("Kowalscy")
	var me struct {
		User     struct{ ID string }
		MemberID string `json:"member_id"`
	}
	a.do("GET", "/me", nil, &me)

	// Unauthenticated MCP → where to authorize.
	res, _ := http.Post(e.srv.URL+"/mcp", "application/json", strings.NewReader(`{}`))
	if res.StatusCode != http.StatusUnauthorized || !strings.Contains(res.Header.Get("WWW-Authenticate"), "/.well-known/oauth-protected-resource/mcp") {
		t.Fatalf("401: %s %q", res.Status, res.Header.Get("WWW-Authenticate"))
	}
	var prm struct {
		Resource             string
		AuthorizationServers []string `json:"authorization_servers"`
	}
	r2, _ := http.Get(e.srv.URL + "/.well-known/oauth-protected-resource/mcp")
	json.NewDecoder(r2.Body).Decode(&prm)
	if prm.Resource != e.srv.URL+"/mcp" || len(prm.AuthorizationServers) != 1 {
		t.Fatalf("resource metadata: %+v", prm)
	}
	var asm struct {
		RegistrationEndpoint string   `json:"registration_endpoint"`
		TokenEndpoint        string   `json:"token_endpoint"`
		Methods              []string `json:"code_challenge_methods_supported"`
	}
	r3, _ := http.Get(prm.AuthorizationServers[0] + "/.well-known/oauth-authorization-server")
	json.NewDecoder(r3.Body).Decode(&asm)
	if asm.RegistrationEndpoint == "" || asm.Methods[0] != "S256" {
		t.Fatalf("server metadata: %+v", asm)
	}

	// Dynamic registration (a confidential client, like ChatGPT may register).
	redirect := "https://chatgpt.example.test/connector/oauth/callback"
	body, _ := json.Marshal(map[string]any{"client_name": "ChatGPT", "redirect_uris": []string{redirect},
		"token_endpoint_auth_method": "client_secret_post"})
	r4, _ := http.Post(asm.RegistrationEndpoint, "application/json", strings.NewReader(string(body)))
	var reg struct {
		ClientID     string `json:"client_id"`
		ClientSecret string `json:"client_secret"`
	}
	json.NewDecoder(r4.Body).Decode(&reg)
	if r4.StatusCode != http.StatusCreated || reg.ClientID == "" || reg.ClientSecret == "" {
		t.Fatalf("register: %s %+v", r4.Status, reg)
	}
	bad, _ := json.Marshal(map[string]any{"redirect_uris": []string{"http://evil.example/cb"}})
	if r, _ := http.Post(asm.RegistrationEndpoint, "application/json", strings.NewReader(string(bad))); r.StatusCode != http.StatusBadRequest {
		t.Fatalf("plain http redirect accepted: %s", r.Status)
	}

	// Deny → error back to the client.
	if back := e.authorize(reg.ClientID, redirect, me.User.ID, "deny"); back.Query().Get("error") != "access_denied" {
		t.Fatalf("deny: %s", back)
	}
	back := e.authorize(reg.ClientID, redirect, me.User.ID, "allow")
	code := back.Query().Get("code")
	if code == "" || back.Query().Get("state") != "xyz" || !strings.HasPrefix(back.String(), redirect) {
		t.Fatalf("allow: %s", back)
	}

	form := url.Values{"grant_type": {"authorization_code"}, "code": {code}, "redirect_uri": {redirect},
		"client_id": {reg.ClientID}, "client_secret": {reg.ClientSecret},
		"code_verifier": {"verifier-0123456789-0123456789-0123456789"}}
	bad1 := url.Values{}
	for k, v := range form {
		bad1[k] = v
	}
	bad1.Set("client_secret", "wrong")
	if st, _ := e.token(bad1); st != http.StatusUnauthorized {
		t.Fatalf("wrong secret: %d", st)
	}
	st, tok := e.token(form)
	if st != http.StatusOK || tok.AccessToken == "" || tok.RefreshToken == "" || tok.TokenType != "Bearer" {
		t.Fatalf("token: %d %+v", st, tok)
	}
	if st, _ := e.token(form); st != http.StatusBadRequest {
		t.Fatalf("code reused: %d", st)
	}

	// MCP as the member: "me" is them, writes are theirs.
	s := e.mcpSession(tok.AccessToken)
	var fam struct{ Me string }
	tool(t, s, "family", nil, &fam)
	if fam.Me != "Tata" {
		t.Fatalf("me: %+v", fam)
	}
	var added struct{ ID, Assignee string }
	tool(t, s, "add_todo", map[string]any{"list": "Zakupy", "title": "Kawa", "assignee": fam.Me}, &added)
	var actor string
	e.db.Raw("SELECT actor_id::text FROM changes WHERE entity_id = ? ORDER BY seq DESC LIMIT 1", added.ID).Scan(&actor)
	if actor != me.MemberID {
		t.Fatalf("actor %q, member %q", actor, me.MemberID)
	}
	// Limited to module data.
	agent := &client{e: e, token: tok.AccessToken}
	if st := agent.do("POST", "/invites", map[string]any{}, nil); st != http.StatusForbidden {
		t.Fatalf("invites via oauth: %d", st)
	}

	// Refresh rotates.
	st, tok2 := e.token(url.Values{"grant_type": {"refresh_token"}, "refresh_token": {tok.RefreshToken},
		"client_id": {reg.ClientID}, "client_secret": {reg.ClientSecret}})
	if st != http.StatusOK || tok2.AccessToken == tok.AccessToken {
		t.Fatalf("refresh: %d", st)
	}
	if st, _ := e.token(url.Values{"grant_type": {"refresh_token"}, "refresh_token": {tok.RefreshToken},
		"client_id": {reg.ClientID}, "client_secret": {reg.ClientSecret}}); st != http.StatusBadRequest {
		t.Fatalf("old refresh token reused: %d", st)
	}

	// The member sees and disconnects the app; its tokens stop working.
	var grants []struct{ ID, Client string }
	a.do("GET", "/oauth/grants", nil, &grants)
	if len(grants) != 1 || grants[0].Client != "ChatGPT" {
		t.Fatalf("grants: %+v", grants)
	}
	if st := a.do("DELETE", "/oauth/grants/"+grants[0].ID, nil, nil); st != http.StatusNoContent {
		t.Fatalf("disconnect: %d", st)
	}
	if st := (&client{e: e, token: tok2.AccessToken}).do("GET", "/views/todo.lists", nil, nil); st != http.StatusUnauthorized {
		t.Fatalf("revoked token: %d", st)
	}
}
