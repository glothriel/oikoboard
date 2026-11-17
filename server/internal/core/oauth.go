package core

import (
	"context"
	"crypto/subtle"
	"database/sql/driver"
	"encoding/json"
	"errors"
	"html/template"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"golang.org/x/oauth2"
	"gorm.io/gorm"
)

// OAuth 2.1 authorization server for MCP clients (ChatGPT, Claude…), as the
// MCP authorization spec expects: metadata (RFC 8414, RFC 9728), dynamic client
// registration (RFC 7591), authorization code + PKCE (S256) and rotating
// refresh tokens. The person signs in with the regular sign-in flow and
// consents; tokens act as that family member, limited to module data
// (ToolAllowed). See docs/mcp.md.

const (
	oauthScope       = "oikoboard"
	accessTokenTTL   = time.Hour
	refreshTokenTTL  = 90 * 24 * time.Hour
	oauthCodeTTL     = 5 * time.Minute
	oauthRequestTTL  = 15 * time.Minute
	consentCookie    = "oiko_oauth_consent"
	oauthCookiePath  = "/oauth"
	MCPPath          = "/mcp"
	resourceMetaPath = "/.well-known/oauth-protected-resource"
)

// PublicBase: the server's public origin — OIKO_PUBLIC_URL, else derived from the request.
func (a *Auth) PublicBase(r *http.Request) string {
	if a.Config.PublicURL != "" {
		return strings.TrimRight(a.Config.PublicURL, "/")
	}
	scheme := "http"
	if r.TLS != nil || r.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	return scheme + "://" + r.Host
}

// ResourceMetadataURL is announced in 401s of /mcp (WWW-Authenticate).
func (a *Auth) ResourceMetadataURL(r *http.Request) string {
	return a.PublicBase(r) + resourceMetaPath + MCPPath
}

// OAuthRoutes: the authorization server (outside /api/v1, at the paths clients expect).
func (a *Auth) OAuthRoutes(r *gin.Engine) {
	r.GET("/.well-known/oauth-authorization-server", a.oauthServerMetadata)
	r.GET("/.well-known/openid-configuration", a.oauthServerMetadata) // some clients only try this one
	r.GET(resourceMetaPath, a.oauthResourceMetadata)
	r.GET(resourceMetaPath+MCPPath, a.oauthResourceMetadata)
	g := r.Group(oauthCookiePath)
	g.POST("/register", a.oauthRegister)
	g.GET("/authorize", a.oauthAuthorize)
	g.GET("/continue", a.oauthContinue)
	g.POST("/consent", a.oauthConsent)
	g.POST("/token", a.oauthToken)
}

// GrantRoutes: the member's connected apps (protected group).
func (a *Auth) GrantRoutes(r *gin.RouterGroup) {
	r.GET("/oauth/grants", a.listGrants)
	r.DELETE("/oauth/grants/:id", a.deleteGrant)
}

func (a *Auth) oauthServerMetadata(c *gin.Context) {
	base := a.PublicBase(c.Request)
	c.JSON(http.StatusOK, gin.H{
		"issuer":                                base,
		"authorization_endpoint":                base + "/oauth/authorize",
		"token_endpoint":                        base + "/oauth/token",
		"registration_endpoint":                 base + "/oauth/register",
		"response_types_supported":              []string{"code"},
		"grant_types_supported":                 []string{"authorization_code", "refresh_token"},
		"code_challenge_methods_supported":      []string{"S256"},
		"token_endpoint_auth_methods_supported": []string{"none", "client_secret_post", "client_secret_basic"},
		"scopes_supported":                      []string{oauthScope},
		// Client ID Metadata Documents: client_id is an https URL of the client's metadata.
		"client_id_metadata_document_supported": true,
	})
}

func (a *Auth) oauthResourceMetadata(c *gin.Context) {
	base := a.PublicBase(c.Request)
	c.JSON(http.StatusOK, gin.H{
		"resource":                 base + MCPPath,
		"authorization_servers":    []string{base},
		"scopes_supported":         []string{oauthScope},
		"bearer_methods_supported": []string{"header"},
		"resource_name":            "Oikoboard",
	})
}

func oauthError(c *gin.Context, status int, code, desc string) {
	c.AbortWithStatusJSON(status, gin.H{"error": code, "error_description": desc})
}

// redirectAllowed: https, or http on a loopback host (native/desktop clients).
func redirectAllowed(raw string) bool {
	u, err := url.Parse(raw)
	if err != nil || u.Fragment != "" || u.Host == "" {
		return false
	}
	switch u.Scheme {
	case "https":
		return true
	case "http":
		h := u.Hostname()
		return h == "localhost" || h == "127.0.0.1" || h == "::1"
	}
	return false
}

// POST /oauth/register (RFC 7591).
func (a *Auth) oauthRegister(c *gin.Context) {
	var req struct {
		RedirectURIs []string `json:"redirect_uris"`
		ClientName   string   `json:"client_name"`
		AuthMethod   string   `json:"token_endpoint_auth_method"`
		GrantTypes   []string `json:"grant_types"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		oauthError(c, http.StatusBadRequest, "invalid_client_metadata", err.Error())
		return
	}
	if len(req.RedirectURIs) == 0 || len(req.RedirectURIs) > 10 {
		oauthError(c, http.StatusBadRequest, "invalid_redirect_uri", "give 1–10 redirect_uris")
		return
	}
	for _, u := range req.RedirectURIs {
		if !redirectAllowed(u) {
			oauthError(c, http.StatusBadRequest, "invalid_redirect_uri", "redirect URIs must be https (or http on localhost): "+u)
			return
		}
	}
	method := req.AuthMethod
	switch method {
	case "":
		method = "none"
	case "none", "client_secret_post", "client_secret_basic":
	default:
		oauthError(c, http.StatusBadRequest, "invalid_client_metadata", "unsupported token_endpoint_auth_method")
		return
	}
	if len(req.ClientName) > 100 {
		req.ClientName = req.ClientName[:100]
	}
	id := "oc_" + randomToken()[:24]
	var secret string
	var secretHash any
	if method != "none" {
		secret = randomToken()
		secretHash = hashToken(secret)
	}
	err := a.DB.WithContext(c.Request.Context()).Exec(
		"INSERT INTO oauth_clients (id, secret_hash, name, redirect_uris) VALUES (?, ?, ?, ?)",
		id, secretHash, req.ClientName, pgTextArray(req.RedirectURIs)).Error
	if err != nil {
		FailErr(c, err)
		return
	}
	out := gin.H{
		"client_id": id, "client_id_issued_at": time.Now().Unix(), "client_name": req.ClientName,
		"redirect_uris": req.RedirectURIs, "token_endpoint_auth_method": method,
		"grant_types": []string{"authorization_code", "refresh_token"}, "response_types": []string{"code"},
	}
	if secret != "" {
		out["client_secret"], out["client_secret_expires_at"] = secret, 0
	}
	c.JSON(http.StatusCreated, out)
}

type oauthClient struct {
	ID           string
	SecretHash   []byte
	Name         string
	RedirectURIs pgTextArray `gorm:"type:text[]"`
}

func (a *Auth) client(ctx context.Context, id string) (*oauthClient, error) {
	if strings.HasPrefix(id, "https://") {
		return a.metadataClient(ctx, id)
	}
	var cl oauthClient
	err := a.DB.WithContext(ctx).Raw("SELECT id, secret_hash, name, redirect_uris FROM oauth_clients WHERE id = ?", id).
		Scan(&cl).Error
	if err != nil || cl.ID == "" {
		return nil, errors.New("unknown client")
	}
	return &cl, nil
}

// metadataClient: a client identified by its metadata document (CIMD). The
// document is fetched (https, public addresses only, small) and cached in
// oauth_clients, refreshed at most hourly.
func (a *Auth) metadataClient(ctx context.Context, id string) (*oauthClient, error) {
	var cl oauthClient
	var fresh bool
	err := a.DB.WithContext(ctx).Raw(`SELECT id, secret_hash, name, redirect_uris,
		created_at > now() - interval '1 hour' AS fresh FROM oauth_clients WHERE id = ?`, id).
		Row().Scan(&cl.ID, &cl.SecretHash, &cl.Name, &cl.RedirectURIs, &fresh)
	if err == nil && fresh {
		return &cl, nil
	}
	doc, err := fetchClientMetadata(ctx, id)
	if err != nil {
		slog.Warn("oauth client metadata", "client", id, "err", err)
		return nil, errors.New("unknown client")
	}
	cl = oauthClient{ID: id, Name: doc.ClientName, RedirectURIs: doc.RedirectURIs}
	err = a.DB.WithContext(ctx).Exec(`
		INSERT INTO oauth_clients (id, name, redirect_uris) VALUES (?, ?, ?)
		ON CONFLICT (id) DO UPDATE SET name = excluded.name, redirect_uris = excluded.redirect_uris, created_at = now()`,
		id, cl.Name, cl.RedirectURIs).Error
	return &cl, err
}

type clientMetadata struct {
	ClientID     string      `json:"client_id"`
	ClientName   string      `json:"client_name"`
	RedirectURIs pgTextArray `json:"redirect_uris"`
	AuthMethod   string      `json:"token_endpoint_auth_method"`
}

// metadataHTTP refuses non-public addresses: the URL comes from the client.
var metadataHTTP = &http.Client{
	Timeout: 5 * time.Second,
	Transport: &http.Transport{DialContext: (&net.Dialer{Timeout: 5 * time.Second,
		Control: func(_, address string, _ syscall.RawConn) error {
			host, _, _ := net.SplitHostPort(address)
			ip := net.ParseIP(host)
			if ip == nil || ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
				return errors.New("non-public address")
			}
			return nil
		}}).DialContext},
	CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("no redirects") },
}

func fetchClientMetadata(ctx context.Context, id string) (*clientMetadata, error) {
	u, err := url.Parse(id)
	if err != nil || u.Scheme != "https" || u.Path == "" || u.Path == "/" || u.Fragment != "" {
		return nil, errors.New("client_id must be an https URL with a path")
	}
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, id, nil)
	req.Header.Set("Accept", "application/json")
	res, err := metadataHTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, errors.New(res.Status)
	}
	var doc clientMetadata
	if err := json.NewDecoder(io.LimitReader(res.Body, 64<<10)).Decode(&doc); err != nil {
		return nil, err
	}
	if doc.ClientID != id {
		return nil, errors.New("client_id in the document doesn't match its URL")
	}
	if doc.AuthMethod != "" && doc.AuthMethod != "none" {
		return nil, errors.New("only public clients (token_endpoint_auth_method none) are supported")
	}
	if len(doc.RedirectURIs) == 0 {
		return nil, errors.New("no redirect_uris")
	}
	for _, r := range doc.RedirectURIs {
		if !redirectAllowed(r) {
			return nil, errors.New("bad redirect_uri " + r)
		}
	}
	if len(doc.ClientName) > 100 {
		doc.ClientName = doc.ClientName[:100]
	}
	return &doc, nil
}

// GET /oauth/authorize — validates the request, then signs the person in
// (the regular sign-in flow, returning to /oauth/continue).
func (a *Auth) oauthAuthorize(c *gin.Context) {
	ctx := c.Request.Context()
	q := c.Request.URL.Query()
	cl, err := a.client(ctx, q.Get("client_id"))
	if err != nil {
		oauthPage(c, http.StatusBadRequest, "Nieznana aplikacja", "Ta aplikacja nie jest zarejestrowana — spróbuj połączyć ją od nowa.")
		return
	}
	redirect := q.Get("redirect_uri")
	if redirect == "" && len(cl.RedirectURIs) == 1 {
		redirect = cl.RedirectURIs[0]
	}
	if !slices.Contains([]string(cl.RedirectURIs), redirect) {
		oauthPage(c, http.StatusBadRequest, "Błędny adres powrotu", "Adres powrotu nie zgadza się z rejestracją aplikacji.")
		return
	}
	// From here on errors go back to the client.
	back := func(code, desc string) {
		c.Redirect(http.StatusFound, withQuery(redirect, "error", code, "error_description", desc, "state", q.Get("state")))
	}
	if q.Get("response_type") != "code" {
		back("unsupported_response_type", "only response_type=code")
		return
	}
	if q.Get("code_challenge_method") != "S256" || len(q.Get("code_challenge")) != 43 {
		back("invalid_request", "PKCE with S256 is required")
		return
	}
	if res := q.Get("resource"); res != "" && strings.TrimRight(res, "/") != a.PublicBase(c.Request)+MCPPath {
		back("invalid_target", "unknown resource")
		return
	}
	if !a.ConnectEnabled() && !a.Config.DevLogin {
		back("temporarily_unavailable", "sign-in is not configured on this server")
		return
	}
	reqToken, verifier := randomToken(), oauth2.GenerateVerifier()
	err = a.DB.WithContext(ctx).Exec(`
		INSERT INTO oauth_requests (id, client_id, redirect_uri, code_challenge, state, scope, resource, login_verifier)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, hashToken(reqToken), cl.ID, redirect, q.Get("code_challenge"),
		q.Get("state"), oauthScope, q.Get("resource"), verifier).Error
	if err != nil {
		FailErr(c, err)
		return
	}
	returnTo := a.PublicBase(c.Request) + "/oauth/continue?" + url.Values{"req": {reqToken}}.Encode()
	state, err := a.newFlow(ctx, purposeLogin, nil, returnTo, pkceChallenge(verifier))
	if err != nil {
		FailErr(c, err)
		return
	}
	c.Redirect(http.StatusFound, cookiePath+"/start?"+url.Values{"state": {state}}.Encode())
}

type oauthRequest struct {
	ClientID      string
	RedirectURI   string
	CodeChallenge string
	State         string
	Scope         string
	Resource      string
	LoginVerifier string
	UserID        *uuid.UUID
	ConsentHash   []byte
}

func (a *Auth) oauthRequest(tx *gorm.DB, token string) (*oauthRequest, error) {
	var r oauthRequest
	err := tx.Raw(`
		SELECT client_id, redirect_uri, code_challenge, state, scope, resource, login_verifier, user_id, consent_hash
		FROM oauth_requests WHERE id = ? AND created_at > now() - interval '15 minutes'`, hashToken(token)).Scan(&r).Error
	if err != nil || r.ClientID == "" {
		return nil, errors.New("expired")
	}
	return &r, nil
}

type consentHousehold struct {
	MemberID uuid.UUID
	Name     string
	Member   string
}

// GET /oauth/continue?req=…&code=… — back from sign-in: shows the consent page.
func (a *Auth) oauthContinue(c *gin.Context) {
	ctx := c.Request.Context()
	reqToken := c.Query("req")
	r, err := a.oauthRequest(a.DB.WithContext(ctx), reqToken)
	if err != nil {
		oauthPage(c, http.StatusBadRequest, "Link wygasł", "Połącz aplikację jeszcze raz.")
		return
	}
	if e := c.Query("error"); e != "" {
		a.DB.WithContext(ctx).Exec("DELETE FROM oauth_requests WHERE id = ?", hashToken(reqToken))
		c.Redirect(http.StatusFound, withQuery(r.RedirectURI, "error", "access_denied", "state", r.State))
		return
	}
	userID, err := a.exchangeLogin(ctx, c.Query("code"), r.LoginVerifier)
	if err != nil {
		oauthPage(c, http.StatusBadRequest, "Logowanie nie powiodło się", "Połącz aplikację jeszcze raz.")
		return
	}
	var hhs []consentHousehold
	if err := a.DB.WithContext(ctx).Raw(`
		SELECT m.id AS member_id, h.name, m.name AS member FROM members m JOIN households h ON h.id = m.household_id
		WHERE m.user_id = ? ORDER BY m.created_at`, userID).Scan(&hhs).Error; err != nil {
		FailErr(c, err)
		return
	}
	if len(hhs) == 0 {
		oauthPage(c, http.StatusForbidden, "Brak rodziny", "To konto nie należy do żadnej rodziny w Oikoboard.")
		return
	}
	csrf := randomToken()
	if err := a.DB.WithContext(ctx).Exec("UPDATE oauth_requests SET user_id = ?, consent_hash = ? WHERE id = ?",
		userID, hashToken(csrf), hashToken(reqToken)).Error; err != nil {
		FailErr(c, err)
		return
	}
	cl, err := a.client(ctx, r.ClientID)
	if err != nil {
		oauthPage(c, http.StatusBadRequest, "Nieznana aplikacja", "")
		return
	}
	// The consent must be posted from this browser.
	http.SetCookie(c.Writer, &http.Cookie{Name: consentCookie, Value: csrf, Path: oauthCookiePath, MaxAge: 900,
		HttpOnly: true, Secure: strings.HasPrefix(a.PublicBase(c.Request), "https://"), SameSite: http.SameSiteStrictMode})
	name := cl.Name
	if name == "" {
		name = "Aplikacja"
	}
	host := ""
	if u, err := url.Parse(r.RedirectURI); err == nil {
		host = u.Host
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	c.Header("X-Frame-Options", "DENY")
	_ = consentPage.Execute(c.Writer, map[string]any{
		"Client": name, "Host": host, "Req": reqToken, "CSRF": csrf, "Households": hhs,
	})
}

// POST /oauth/consent (form) — allow or deny; on allow issues the code.
func (a *Auth) oauthConsent(c *gin.Context) {
	ctx := c.Request.Context()
	reqToken, csrf := c.PostForm("req"), c.PostForm("csrf")
	cookie, _ := c.Cookie(consentCookie)
	http.SetCookie(c.Writer, &http.Cookie{Name: consentCookie, Path: oauthCookiePath, MaxAge: -1})
	var r *oauthRequest
	var err error
	err = a.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if r, err = a.oauthRequest(tx, reqToken); err != nil {
			return err
		}
		return tx.Exec("DELETE FROM oauth_requests WHERE id = ?", hashToken(reqToken)).Error
	})
	if err != nil || r.UserID == nil || csrf == "" ||
		subtle.ConstantTimeCompare([]byte(csrf), []byte(cookie)) != 1 ||
		subtle.ConstantTimeCompare(hashToken(csrf), r.ConsentHash) != 1 {
		oauthPage(c, http.StatusBadRequest, "Link wygasł", "Połącz aplikację jeszcze raz.")
		return
	}
	if c.PostForm("decision") != "allow" {
		c.Redirect(http.StatusFound, withQuery(r.RedirectURI, "error", "access_denied", "state", r.State))
		return
	}
	memberID, err := uuid.Parse(c.PostForm("member"))
	if err != nil {
		oauthPage(c, http.StatusBadRequest, "Wybierz rodzinę", "")
		return
	}
	var m Member
	if err := a.DB.WithContext(ctx).First(&m, "id = ? AND user_id = ?", memberID, *r.UserID).Error; err != nil {
		oauthPage(c, http.StatusForbidden, "Brak dostępu", "Nie należysz do tej rodziny.")
		return
	}
	code := randomToken()
	err = a.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		grantID, err := scanUUID(tx.Raw(`
			INSERT INTO oauth_grants (client_id, household_id, member_id, user_id, scope, resource)
			VALUES (?, ?, ?, ?, ?, ?) RETURNING id`, r.ClientID, m.HouseholdID, m.ID, *r.UserID, r.Scope, r.Resource))
		if err != nil {
			return err
		}
		return tx.Exec(`INSERT INTO oauth_codes (code_hash, grant_id, redirect_uri, code_challenge, expires_at)
			VALUES (?, ?, ?, ?, ?)`, hashToken(code), grantID, r.RedirectURI, r.CodeChallenge,
			time.Now().Add(oauthCodeTTL)).Error
	})
	if err != nil {
		FailErr(c, err)
		return
	}
	c.Redirect(http.StatusFound, withQuery(r.RedirectURI, "code", code, "state", r.State,
		"iss", a.PublicBase(c.Request)))
}

// clientAuth checks the client's credentials at the token endpoint.
func (a *Auth) clientAuth(c *gin.Context) (*oauthClient, bool) {
	id, secret, basic := c.Request.BasicAuth()
	if basic {
		id, _ = url.QueryUnescape(id)
		secret, _ = url.QueryUnescape(secret)
	} else {
		id, secret = c.PostForm("client_id"), c.PostForm("client_secret")
	}
	cl, err := a.client(c.Request.Context(), id)
	if err != nil {
		oauthError(c, http.StatusUnauthorized, "invalid_client", "unknown client")
		return nil, false
	}
	if cl.SecretHash != nil && subtle.ConstantTimeCompare(hashToken(secret), cl.SecretHash) != 1 {
		oauthError(c, http.StatusUnauthorized, "invalid_client", "bad client credentials")
		return nil, false
	}
	return cl, true
}

// POST /oauth/token — authorization_code (PKCE) or refresh_token (rotated).
func (a *Auth) oauthToken(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	cl, ok := a.clientAuth(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	var grantID uuid.UUID
	var err error
	switch c.PostForm("grant_type") {
	case "authorization_code":
		var code struct {
			GrantID       uuid.UUID
			RedirectURI   string
			CodeChallenge string
			ClientID      string
		}
		err = a.DB.WithContext(ctx).Raw(`
			DELETE FROM oauth_codes oc USING oauth_grants g
			WHERE oc.code_hash = ? AND g.id = oc.grant_id AND oc.expires_at > now()
			RETURNING oc.grant_id, oc.redirect_uri, oc.code_challenge, g.client_id`,
			hashToken(c.PostForm("code"))).Scan(&code).Error
		if err != nil {
			FailErr(c, err)
			return
		}
		if code.GrantID == uuid.Nil || code.ClientID != cl.ID ||
			(c.PostForm("redirect_uri") != "" && c.PostForm("redirect_uri") != code.RedirectURI) ||
			subtle.ConstantTimeCompare([]byte(pkceChallenge(c.PostForm("code_verifier"))), []byte(code.CodeChallenge)) != 1 {
			oauthError(c, http.StatusBadRequest, "invalid_grant", "invalid, expired or already used code")
			return
		}
		grantID = code.GrantID
	case "refresh_token":
		var row struct {
			GrantID  uuid.UUID
			ClientID string
		}
		err = a.DB.WithContext(ctx).Raw(`
			DELETE FROM oauth_tokens t USING oauth_grants g
			WHERE t.token_hash = ? AND t.kind = 'refresh' AND g.id = t.grant_id AND t.expires_at > now()
			RETURNING t.grant_id, g.client_id`, hashToken(c.PostForm("refresh_token"))).Scan(&row).Error
		if err != nil {
			FailErr(c, err)
			return
		}
		if row.GrantID == uuid.Nil || row.ClientID != cl.ID {
			oauthError(c, http.StatusBadRequest, "invalid_grant", "invalid or expired refresh token")
			return
		}
		grantID = row.GrantID
	default:
		oauthError(c, http.StatusBadRequest, "unsupported_grant_type", "authorization_code or refresh_token")
		return
	}
	access, refresh := randomToken(), randomToken()
	err = a.DB.WithContext(ctx).Exec(`
		INSERT INTO oauth_tokens (token_hash, grant_id, kind, expires_at) VALUES (?, ?, 'access', ?), (?, ?, 'refresh', ?)`,
		hashToken(access), grantID, time.Now().Add(accessTokenTTL),
		hashToken(refresh), grantID, time.Now().Add(refreshTokenTTL)).Error
	if err != nil {
		FailErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"access_token": access, "token_type": "Bearer",
		"expires_in": int(accessTokenTTL.Seconds()), "refresh_token": refresh, "scope": oauthScope})
}

// ResolveOAuth turns an OAuth access token into the member it acts as.
func (a *Auth) ResolveOAuth(ctx context.Context, token string) (Actor, error) {
	if token == "" {
		return Actor{}, errors.New("no token")
	}
	var row struct {
		GrantID     uuid.UUID
		UserID      uuid.UUID
		MemberID    uuid.UUID
		HouseholdID uuid.UUID
	}
	err := a.DB.WithContext(ctx).Raw(`
		SELECT g.id AS grant_id, g.user_id, g.member_id, g.household_id
		FROM oauth_tokens t JOIN oauth_grants g ON g.id = t.grant_id
		JOIN members m ON m.id = g.member_id AND m.user_id = g.user_id -- still in the family
		WHERE t.token_hash = ? AND t.kind = 'access' AND t.expires_at > now()`, hashToken(token)).Scan(&row).Error
	if err != nil {
		return Actor{}, err
	}
	if row.GrantID == uuid.Nil {
		return Actor{}, errors.New("unknown or expired token")
	}
	a.DB.WithContext(ctx).Exec("UPDATE oauth_grants SET last_used_at = now() WHERE id = ? AND "+
		"(last_used_at IS NULL OR last_used_at < now() - interval '5 minutes')", row.GrantID)
	return Actor{UserID: row.UserID, MemberID: row.MemberID, HouseholdID: row.HouseholdID, Delegated: true}, nil
}

// --- connected apps (for the app's settings) ---

// GET /oauth/grants — the signed-in member's connected apps.
func (a *Auth) listGrants(c *gin.Context) {
	act := ActorOf(c)
	out := []struct {
		ID         uuid.UUID  `json:"id"`
		Client     string     `json:"client"`
		CreatedAt  time.Time  `json:"created_at"`
		LastUsedAt *time.Time `json:"last_used_at"`
	}{}
	err := a.DB.WithContext(c.Request.Context()).Raw(`
		SELECT g.id, coalesce(nullif(cl.name, ''), 'Aplikacja') AS client, g.created_at, g.last_used_at
		FROM oauth_grants g JOIN oauth_clients cl ON cl.id = g.client_id
		WHERE g.household_id = ? AND g.member_id = ? ORDER BY g.created_at DESC`,
		act.HouseholdID, act.MemberID).Scan(&out).Error
	if err != nil {
		FailErr(c, err)
		return
	}
	c.JSON(http.StatusOK, out)
}

// DELETE /oauth/grants/:id — disconnects the app (its tokens stop working).
func (a *Auth) deleteGrant(c *gin.Context) {
	id, ok := ParamUUID(c, "id")
	if !ok {
		return
	}
	act := ActorOf(c)
	res := a.DB.WithContext(c.Request.Context()).Exec(
		"DELETE FROM oauth_grants WHERE id = ? AND household_id = ? AND member_id = ?", id, act.HouseholdID, act.MemberID)
	if res.Error != nil {
		FailErr(c, res.Error)
		return
	}
	if res.RowsAffected == 0 {
		FailErr(c, gorm.ErrRecordNotFound)
		return
	}
	c.Status(http.StatusNoContent)
}

// CleanupOAuth drops expired requests, codes and tokens, and grants nobody used for long.
func (a *Auth) CleanupOAuth(ctx context.Context) {
	db := a.DB.WithContext(ctx)
	for _, q := range []string{
		"DELETE FROM oauth_requests WHERE created_at < now() - interval '1 hour'",
		"DELETE FROM oauth_codes WHERE expires_at < now()",
		"DELETE FROM oauth_tokens WHERE expires_at < now()",
		"DELETE FROM oauth_grants g WHERE NOT EXISTS (SELECT 1 FROM oauth_tokens t WHERE t.grant_id = g.id) " +
			"AND NOT EXISTS (SELECT 1 FROM oauth_codes oc WHERE oc.grant_id = g.id) AND g.created_at < now() - interval '1 hour'",
		"DELETE FROM oauth_clients cl WHERE NOT EXISTS (SELECT 1 FROM oauth_grants g WHERE g.client_id = cl.id) " +
			"AND cl.created_at < now() - interval '30 days'",
	} {
		if err := db.Exec(q).Error; err != nil {
			slog.Warn("oauth cleanup", "err", err)
		}
	}
}

// --- pages ---

func oauthPage(c *gin.Context, status int, title, text string) {
	c.Status(status)
	c.Header("Content-Type", "text/html; charset=utf-8")
	_ = messagePage.Execute(c.Writer, map[string]string{"Title": title, "Text": text})
}

const pageStyle = `<meta name="viewport" content="width=device-width, initial-scale=1"><style>
 body{font-family:system-ui,sans-serif;max-width:460px;margin:40px auto;padding:0 16px;color:#222;background:#fafafa}
 h1{font-size:1.3rem} .card{background:#fff;border:1px solid #ddd;border-radius:12px;padding:16px 20px}
 ul{padding-left:20px} label{display:flex;gap:8px;align-items:center;margin:6px 0}
 .row{display:flex;gap:8px;justify-content:flex-end;margin-top:16px}
 button{padding:10px 16px;border-radius:8px;border:1px solid #2e7d6b;background:#fff;color:#2e7d6b;font-size:1rem}
 button.ok{background:#2e7d6b;color:#fff} small{color:#777}
</style>`

var messagePage = template.Must(template.New("msg").Parse(`<!doctype html><html lang="pl"><head><meta charset="utf-8">
<title>{{.Title}} — Oikoboard</title>` + pageStyle + `</head><body><div class="card"><h1>{{.Title}}</h1><p>{{.Text}}</p></div></body></html>`))

var consentPage = template.Must(template.New("consent").Parse(`<!doctype html><html lang="pl"><head><meta charset="utf-8">
<title>Połącz z Oikoboard</title>` + pageStyle + `</head><body><div class="card">
<h1>{{.Client}} chce połączyć się z Oikoboard</h1>
<p><small>Powrót do: {{.Host}}</small></p>
<p>Aplikacja będzie mogła w Twoim imieniu:</p>
<ul><li>czytać, dodawać, zmieniać i usuwać zadania na listach rodziny,</li>
<li>czytać, dodawać, zmieniać i usuwać wydarzenia w kalendarzu rodziny.</li></ul>
<p><small>Nie dostanie dostępu do ustawień, zaproszeń ani połączonych kont. Połączenie możesz odłączyć w aplikacji
(menu → Czat AI (MCP)).</small></p>
<form method="post" action="/oauth/consent">
<input type="hidden" name="req" value="{{.Req}}"><input type="hidden" name="csrf" value="{{.CSRF}}">
{{if gt (len .Households) 1}}<p>Rodzina:</p>{{range $i, $h := .Households}}
<label><input type="radio" name="member" value="{{$h.MemberID}}" {{if eq $i 0}}checked{{end}}> {{$h.Name}} <small>({{$h.Member}})</small></label>{{end}}
{{else}}{{with index .Households 0}}<p>Rodzina: <b>{{.Name}}</b> <small>(jako {{.Member}})</small></p>
<input type="hidden" name="member" value="{{.MemberID}}">{{end}}{{end}}
<div class="row"><button name="decision" value="deny">Odmów</button>
<button class="ok" name="decision" value="allow">Zezwól</button></div>
</form></div></body></html>`))

// pgTextArray maps a text[] column.
type pgTextArray []string

func (a pgTextArray) Value() (driver.Value, error) {
	parts := make([]string, len(a))
	for i, s := range a {
		parts[i] = `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(s) + `"`
	}
	return "{" + strings.Join(parts, ",") + "}", nil
}

func (a *pgTextArray) Scan(src any) error {
	var s string
	switch v := src.(type) {
	case nil:
		*a = nil
		return nil
	case []byte:
		s = string(v)
	case string:
		s = v
	default:
		return errors.New("pgTextArray: unsupported type")
	}
	*a = parsePgArray(s)
	return nil
}

func parsePgArray(s string) []string {
	s = strings.TrimSuffix(strings.TrimPrefix(s, "{"), "}")
	var out []string
	var cur strings.Builder
	inQ, esc, seen := false, false, false
	for _, r := range s {
		switch {
		case esc:
			cur.WriteRune(r)
			esc = false
		case r == '\\':
			esc = true
		case r == '"':
			inQ, seen = !inQ, true
		case r == ',' && !inQ:
			out = append(out, cur.String())
			cur.Reset()
			seen = false
		default:
			cur.WriteRune(r)
			seen = true
		}
	}
	if seen || cur.Len() > 0 {
		out = append(out, cur.String())
	}
	return out
}
