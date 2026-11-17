package core

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"sync"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"golang.org/x/oauth2"
)

// Google sign-in (OIDC, authorization code + PKCE), done entirely by the
// backend; the app only opens a browser and finally trades a one-time code
// for a session:
//
//	app → GET /auth/google/start?return=<app url>&challenge=<S256>
//	    → Google → GET /auth/google/callback → <app url>?code=…
//	app → POST /auth/exchange {code, verifier} → {token}
//
// Connecting a Google Calendar uses the same callback with a "calendar" flow
// (extra scopes, offline access). It is started by the signed-in app
// (StartConnect) and finished by the same signed-in app (CompleteConnect), so
// a flow started by one account can't be completed into another.
//
// Details: docs/auth.md, docs/calendar.md.

type GoogleConfig struct {
	ClientID     string
	ClientSecret string
	// Public API URL, e.g. http://localhost:8090 or https://oiko.example.com.
	PublicURL string
	// Defaults to https://accounts.google.com; replaced in tests.
	Issuer string
}

func (g GoogleConfig) redirectURL() string {
	return strings.TrimRight(g.PublicURL, "/") + "/api/v1/auth/google/callback"
}

func (g GoogleConfig) issuer() string {
	if g.Issuer != "" {
		return g.Issuer
	}
	return "https://accounts.google.com"
}

const (
	stateCookie = "oiko_oauth_state"
	cookiePath  = "/api/v1/auth/google"

	purposeLogin    = "login"
	purposeCalendar = "calendar"
)

var calendarScopes = []string{
	oidc.ScopeOpenID, "email",
	"https://www.googleapis.com/auth/calendar.events",
	"https://www.googleapis.com/auth/calendar.calendarlist.readonly",
}

// googleClient: the provider is discovered lazily (needs network — the
// server must start offline too).
type googleClient struct {
	cfg      GoogleConfig
	mu       sync.Mutex
	oauth    *oauth2.Config
	verifier *oidc.IDTokenVerifier
}

func (g *googleClient) init(ctx context.Context) (*oauth2.Config, *oidc.IDTokenVerifier, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.oauth != nil {
		return g.oauth, g.verifier, nil
	}
	// The provider outlives the request (it refreshes keys) — don't give it
	// the request context.
	p, err := oidc.NewProvider(context.WithoutCancel(ctx), g.cfg.issuer())
	if err != nil {
		return nil, nil, fmt.Errorf("discovery %s: %w", g.cfg.issuer(), err)
	}
	g.oauth = &oauth2.Config{
		ClientID:     g.cfg.ClientID,
		ClientSecret: g.cfg.ClientSecret,
		Endpoint:     p.Endpoint(),
		RedirectURL:  g.cfg.redirectURL(),
		Scopes:       []string{oidc.ScopeOpenID, "email", "profile"},
	}
	g.verifier = p.Verifier(&oidc.Config{ClientID: g.cfg.ClientID})
	return g.oauth, g.verifier, nil
}

func (g *googleClient) config(ctx context.Context, purpose string) (*oauth2.Config, *oidc.IDTokenVerifier, error) {
	base, v, err := g.init(ctx)
	if err != nil || purpose != purposeCalendar {
		return base, v, err
	}
	c := *base
	c.Scopes = calendarScopes
	return &c, v, nil
}

// returnAllowed checks the return address against patterns
// ("http://localhost:*", "https://oiko.example.com", "oikoboard://auth").
func returnAllowed(raw string, patterns []string) bool {
	u, err := url.Parse(raw)
	if err != nil || u.User != nil || u.Scheme == "" || u.Host == "" {
		return false
	}
	for _, p := range patterns {
		pu, err := url.Parse(strings.Replace(p, ":*", "", 1))
		if err != nil {
			continue
		}
		anyPort := strings.HasSuffix(p, ":*")
		if strings.EqualFold(u.Scheme, pu.Scheme) && strings.EqualFold(u.Hostname(), pu.Hostname()) &&
			(anyPort || u.Port() == pu.Port()) {
			return true
		}
	}
	return false
}

// returnTo sends the browser back to where sign-in started. A web URL is a plain
// redirect; an app's custom scheme (oikoboard://auth) gets a page that opens it:
// a bare 302 to a custom scheme is sometimes not followed by Chrome Custom Tabs,
// which then show a dead "Found" link. On Android the button uses an intent://
// URL naming the app's package, which Chrome resolves reliably.
func returnTo(c *gin.Context, target string) {
	u, err := url.Parse(target)
	if err != nil || u.Scheme == "http" || u.Scheme == "https" || u.Scheme == "" {
		c.Redirect(http.StatusFound, target)
		return
	}
	intent := "intent://" + u.Host + u.EscapedPath() + "?" + u.RawQuery +
		"#Intent;scheme=" + u.Scheme + ";package=" + androidPackage + ";end"
	c.Header("Cache-Control", "no-store")
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(fmt.Sprintf(returnPage,
		jsString(target), html.EscapeString(intent), html.EscapeString(target))))
}

// androidPackage is the Android app's applicationId (intent:// links).
const androidPackage = "dev.oikoboard.oikoboard"

func jsString(s string) string { b, _ := json.Marshal(s); return string(b) }

const returnPage = `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Oikoboard</title>
<style>body{font-family:system-ui,sans-serif;text-align:center;padding:48px 16px;color:#1b1b1f}
a.b{display:inline-block;margin-top:16px;padding:12px 24px;border-radius:24px;background:#03347F;color:#fff;text-decoration:none}</style>
</head><body><p>Signed in. Returning to the app…</p>
<a class="b" id="open" href="%[2]s">Open Oikoboard</a>
<p><small><a href="%[3]s">alternative link</a></small></p>
<script>location.href=%[1]s;</script></body></html>`

func withQuery(raw string, kv ...string) string {
	u, _ := url.Parse(raw)
	q := u.Query()
	for i := 0; i+1 < len(kv); i += 2 {
		q.Set(kv[i], kv[i+1])
	}
	u.RawQuery = q.Encode()
	u.Fragment = ""
	return u.String()
}

func (a *Auth) secureCookies() bool {
	return a.google != nil && strings.HasPrefix(a.google.cfg.PublicURL, "https://")
}

// ConnectEnabled: whether a calendar account can be connected (real Google
// or the mock).
func (a *Auth) ConnectEnabled() bool { return a.google != nil || a.Config.MockOAuth }

type authFlow struct {
	PkceVerifier string
	Nonce        string
	ReturnTo     string
	Purpose      string
}

// ErrBadConnect: invalid return address or PKCE challenge.
var ErrBadConnect = errors.New("invalid return address or challenge")

func (a *Auth) createFlow(ctx context.Context, purpose string, userID *uuid.UUID, returnTo, challenge string) (string, error) {
	if !returnAllowed(returnTo, a.Config.ReturnURLs) {
		return "", ErrBadConnect
	}
	return a.newFlow(ctx, purpose, userID, returnTo, challenge)
}

// newFlow stores a flow; returnTo must already be trusted.
func (a *Auth) newFlow(ctx context.Context, purpose string, userID *uuid.UUID, returnTo, challenge string) (string, error) {
	if len(challenge) != 43 { // base64url(sha256), no padding
		return "", ErrBadConnect
	}
	state := randomToken()
	nonce, pkce := "", ""
	if !a.Config.MockOAuth {
		nonce, pkce = randomToken(), oauth2.GenerateVerifier()
	}
	err := a.DB.WithContext(ctx).Exec(`
		INSERT INTO auth_flows (state_hash, pkce_verifier, nonce, return_to, app_challenge, purpose, user_id)
		VALUES (?, ?, ?, ?, ?, ?, ?)`, hashToken(state), pkce, nonce, returnTo, challenge, purpose, userID).Error
	return state, err
}

// StartConnect begins connecting a calendar account for a signed-in user.
// Returns the path (on this API) to open in the browser.
func (a *Auth) StartConnect(ctx context.Context, userID uuid.UUID, returnTo, challenge string) (string, error) {
	if !a.ConnectEnabled() {
		return "", errors.New("no calendar provider configured")
	}
	if !a.Config.MockOAuth && a.Config.Sealer == nil {
		return "", ErrNoSecretKey
	}
	state, err := a.createFlow(ctx, purposeCalendar, &userID, returnTo, challenge)
	if err != nil {
		return "", err
	}
	return cookiePath + "/start?" + url.Values{"state": {state}}.Encode(), nil
}

// Grant: result of connecting a provider account.
type Grant struct {
	Provider    string `json:"provider"`    // "google" | "mock"
	Account     string `json:"account"`     // e.g. the Google e-mail
	Credentials string `json:"credentials"` // sealed provider credentials
}

// CompleteConnect trades the one-time code from the callback for the grant.
// Only the user who started the flow can complete it.
func (a *Auth) CompleteConnect(ctx context.Context, userID uuid.UUID, code, verifier string) (Grant, error) {
	var flow struct {
		UserID       *uuid.UUID
		AppChallenge string
		Result       *string
	}
	err := a.DB.WithContext(ctx).Raw(`
		DELETE FROM auth_flows
		WHERE code_hash = ? AND purpose = 'calendar' AND created_at > now() - interval '15 minutes'
		RETURNING user_id, app_challenge, result`, hashToken(code)).Scan(&flow).Error
	if err != nil {
		return Grant{}, err
	}
	bad := errors.New("invalid or expired connect code")
	if flow.UserID == nil || *flow.UserID != userID || flow.Result == nil || subtle.ConstantTimeCompare(
		[]byte(pkceChallenge(verifier)), []byte(flow.AppChallenge)) != 1 {
		return Grant{}, bad
	}
	var g Grant
	if err := json.Unmarshal([]byte(*flow.Result), &g); err != nil {
		return Grant{}, err
	}
	return g, nil
}

type googleCredentials struct {
	RefreshToken string `json:"refresh_token"`
}

// CalendarHTTPClient returns an HTTP client authorized with the sealed
// Google credentials of a calendar connection.
func (a *Auth) CalendarHTTPClient(ctx context.Context, sealed string) (*http.Client, error) {
	if a.google == nil {
		return nil, errors.New("google is not configured")
	}
	raw, err := a.Config.Sealer.Open(sealed)
	if err != nil {
		return nil, err
	}
	var cr googleCredentials
	if err := json.Unmarshal(raw, &cr); err != nil {
		return nil, err
	}
	cfg, _, err := a.google.config(ctx, purposeCalendar)
	if err != nil {
		return nil, err
	}
	// The client lives longer than the request.
	return cfg.Client(context.Background(), &oauth2.Token{RefreshToken: cr.RefreshToken}), nil
}

func (a *Auth) googleStart(c *gin.Context) {
	ctx := c.Request.Context()
	var state string
	var flow authFlow
	if s := c.Query("state"); s != "" {
		// A flow created by the server itself: a calendar connect (StartConnect)
		// or a sign-in for an OAuth authorization (startServerLogin).
		err := a.DB.WithContext(ctx).Raw(`
			SELECT pkce_verifier, nonce, return_to, purpose FROM auth_flows
			WHERE state_hash = ? AND purpose IN ('calendar', 'login') AND code_hash IS NULL
			  AND created_at > now() - interval '10 minutes'`, hashToken(s)).Scan(&flow).Error
		if err != nil || flow.ReturnTo == "" {
			c.String(http.StatusBadRequest, "this link has expired — start again in the app")
			return
		}
		state = s
	} else {
		var err error
		state, err = a.createFlow(ctx, purposeLogin, nil, c.Query("return"), c.Query("challenge"))
		if errors.Is(err, ErrBadConnect) {
			c.String(http.StatusBadRequest, "invalid return address or challenge")
			return
		} else if err != nil {
			FailErr(c, err)
			return
		}
		err = a.DB.WithContext(ctx).Raw(`
			SELECT pkce_verifier, nonce, return_to, purpose FROM auth_flows WHERE state_hash = ?`,
			hashToken(state)).Scan(&flow).Error
		if err != nil {
			FailErr(c, err)
			return
		}
	}

	var target string
	switch {
	case a.Config.MockOAuth && flow.Purpose == purposeCalendar:
		// Mock: no consent screen — straight to the callback.
		target = cookiePath + "/callback?" + url.Values{"state": {state}, "mock": {"1"}}.Encode()
	case a.Config.MockOAuth:
		target = cookiePath + "/mock?" + url.Values{"state": {state}}.Encode()
	default:
		cfg, _, err := a.google.config(ctx, flow.Purpose)
		if err != nil {
			slog.Error("google", "err", err)
			c.String(http.StatusBadGateway, "can't reach Google")
			return
		}
		opts := []oauth2.AuthCodeOption{oauth2.S256ChallengeOption(flow.PkceVerifier), oidc.Nonce(flow.Nonce)}
		if flow.Purpose == purposeCalendar {
			opts = append(opts, oauth2.AccessTypeOffline,
				oauth2.SetAuthURLParam("prompt", "consent"),
				oauth2.SetAuthURLParam("include_granted_scopes", "true"))
		} else {
			opts = append(opts, oauth2.SetAuthURLParam("prompt", "select_account"))
		}
		target = cfg.AuthCodeURL(state, opts...)
	}
	// The state also goes into a cookie: the callback must come from the same browser.
	http.SetCookie(c.Writer, &http.Cookie{
		Name: stateCookie, Value: state, Path: cookiePath, MaxAge: 600,
		HttpOnly: true, Secure: a.secureCookies(), SameSite: http.SameSiteLaxMode,
	})
	c.Redirect(http.StatusFound, target)
}

func (a *Auth) googleCallback(c *gin.Context) {
	ctx := c.Request.Context()
	state := c.Query("state")
	cookie, _ := c.Cookie(stateCookie)
	http.SetCookie(c.Writer, &http.Cookie{Name: stateCookie, Path: cookiePath, MaxAge: -1})
	if state == "" || subtle.ConstantTimeCompare([]byte(state), []byte(cookie)) != 1 {
		c.String(http.StatusBadRequest, "sign-in expired or started in another browser — please try again")
		return
	}
	var flow struct {
		PkceVerifier string
		Nonce        string
		ReturnTo     string
		Purpose      string
		UserID       *uuid.UUID
	}
	err := a.DB.WithContext(ctx).Raw(`
		SELECT pkce_verifier, nonce, return_to, purpose, user_id FROM auth_flows
		WHERE state_hash = ? AND code_hash IS NULL
		  AND created_at > now() - interval '10 minutes'`, hashToken(state)).Scan(&flow).Error
	if err != nil || flow.ReturnTo == "" {
		c.String(http.StatusBadRequest, "sign-in expired — please try again")
		return
	}
	fail := func(code string, err error) {
		slog.Warn("google callback", "purpose", flow.Purpose, "err", err)
		a.DB.WithContext(ctx).Exec("DELETE FROM auth_flows WHERE state_hash = ?", hashToken(state))
		returnTo(c, withQuery(flow.ReturnTo, "error", code))
	}
	if e := c.Query("error"); e != "" { // e.g. access_denied — the user cancelled
		fail(e, errors.New(e))
		return
	}

	userID := flow.UserID
	var result *string
	if flow.Purpose == purposeCalendar {
		g, err := a.calendarGrant(ctx, c, flow.PkceVerifier, flow.Nonce)
		if err != nil {
			fail("connect_failed", err)
			return
		}
		b, _ := json.Marshal(g)
		s := string(b)
		result = &s
	} else {
		var id uuid.UUID
		if a.Config.MockOAuth {
			id, err = a.mockIdentity(ctx, c)
		} else {
			id, err = a.googleIdentity(ctx, c.Query("code"), flow.PkceVerifier, flow.Nonce)
		}
		if err != nil {
			fail("login_failed", err)
			return
		}
		userID = &id
	}
	code := randomToken()
	if err := a.DB.WithContext(ctx).Exec(
		"UPDATE auth_flows SET code_hash = ?, user_id = ?, result = ? WHERE state_hash = ?",
		hashToken(code), userID, result, hashToken(state)).Error; err != nil {
		fail("login_failed", err)
		return
	}
	returnTo(c, withQuery(flow.ReturnTo, "code", code))
}

// idToken exchanges the authorization code and verifies the ID token.
func (a *Auth) idToken(ctx context.Context, purpose, code, pkce, nonce string) (*oauth2.Token, *oidc.IDToken, error) {
	cfg, verifier, err := a.google.config(ctx, purpose)
	if err != nil {
		return nil, nil, err
	}
	tok, err := cfg.Exchange(ctx, code, oauth2.VerifierOption(pkce))
	if err != nil {
		return nil, nil, fmt.Errorf("exchange: %w", err)
	}
	raw, _ := tok.Extra("id_token").(string)
	idt, err := verifier.Verify(ctx, raw) // signature, iss, aud, exp
	if err != nil {
		return nil, nil, fmt.Errorf("id_token: %w", err)
	}
	if subtle.ConstantTimeCompare([]byte(idt.Nonce), []byte(nonce)) != 1 {
		return nil, nil, errors.New("bad nonce")
	}
	return tok, idt, nil
}

type googleClaims struct {
	Email         string `json:"email"`
	EmailVerified bool   `json:"email_verified"`
	Name          string `json:"name"`
	Picture       string `json:"picture"`
}

func (a *Auth) googleIdentity(ctx context.Context, code, pkce, nonce string) (uuid.UUID, error) {
	_, idt, err := a.idToken(ctx, purposeLogin, code, pkce, nonce)
	if err != nil {
		return uuid.Nil, err
	}
	var cl googleClaims
	if err := idt.Claims(&cl); err != nil {
		return uuid.Nil, err
	}
	if cl.Email == "" || !cl.EmailVerified {
		return uuid.Nil, errors.New("no verified e-mail")
	}
	return a.LoginUser(ctx, Identity{
		Provider: "google", Subject: idt.Subject, Email: strings.ToLower(cl.Email),
		EmailVerified: true, Name: cl.Name, Picture: cl.Picture,
	})
}

func (a *Auth) calendarGrant(ctx context.Context, c *gin.Context, pkce, nonce string) (Grant, error) {
	if a.Config.MockOAuth {
		return Grant{Provider: "mock", Account: "mock"}, nil
	}
	tok, idt, err := a.idToken(ctx, purposeCalendar, c.Query("code"), pkce, nonce)
	if err != nil {
		return Grant{}, err
	}
	if tok.RefreshToken == "" {
		return Grant{}, errors.New("no refresh token (offline access not granted)")
	}
	var cl googleClaims
	_ = idt.Claims(&cl)
	creds, _ := json.Marshal(googleCredentials{RefreshToken: tok.RefreshToken})
	sealed, err := a.Config.Sealer.Seal(creds)
	if err != nil {
		return Grant{}, err
	}
	return Grant{Provider: "google", Account: strings.ToLower(cl.Email), Credentials: sealed}, nil
}
