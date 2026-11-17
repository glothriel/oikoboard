package core

import (
	"context"
	"errors"
	"fmt"
	"html/template"
	"net/url"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// Mock Google (OIKO_MOCK_OAUTH=1). /auth/google/start leads here instead of
// Google; the choice returns to the regular /auth/google/callback with one of:
//
//	user=<uuid>    an existing account (also one created with real Google)
//	member=<uuid>  a family member without an account — gets a fresh account
//	email=<addr>   any e-mail (a new person, e.g. to accept an invite; members
//	               waiting for this address are attached as usual)
//	error=…        "cancel", like access_denied from Google

var mockPage = template.Must(template.New("mock").Parse(`<!doctype html>
<html lang="pl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Na kogo się logujesz? (mock)</title>
<style>
 body{font-family:system-ui,sans-serif;max-width:480px;margin:24px auto;padding:0 16px;color:#222;background:#fafafa}
 h1{font-size:1.3rem} h2{font-size:.95rem;color:#666;margin-top:24px}
 .warn{background:#fff3cd;border:1px solid #e0c36c;padding:8px 12px;border-radius:8px;font-size:.9rem}
 a.p{display:flex;align-items:center;gap:12px;padding:10px 12px;margin:6px 0;border:1px solid #ddd;border-radius:10px;
     background:#fff;text-decoration:none;color:inherit}
 a.p:hover{border-color:#5c6bc0}
 .dot{width:32px;height:32px;border-radius:50%;flex:none;display:grid;place-items:center;color:#fff;font-weight:600}
 small{color:#777;display:block}
 form{display:flex;gap:8px} input{flex:1;padding:8px;border:1px solid #ccc;border-radius:8px}
 button{padding:8px 14px;border-radius:8px;border:0;background:#5c6bc0;color:#fff}
</style></head><body>
<h1>Na kogo się logujesz?</h1>
<p class="warn">Tryb <b>OIKO_MOCK_OAUTH</b> — zamiast Google. Tylko do developmentu.</p>
{{if .Users}}<h2>Konta</h2>
{{range .Users}}<a class="p" href="{{$.Callback}}&user={{.ID}}"><span class="dot" style="background:#5c6bc0">{{.Initial}}</span>
<span>{{.Name}}<small>{{.Email}}{{if .Households}} · {{.Households}}{{end}}</small></span></a>
{{end}}{{end}}
{{if .Members}}<h2>Członkowie rodzin bez konta</h2>
{{range .Members}}<a class="p" href="{{$.Callback}}&member={{.ID}}"><span class="dot" style="background:{{.Color}}">{{.Initial}}</span>
<span>{{.Name}}<small>{{.Household}}{{if .InviteEmail}} · czeka na {{.InviteEmail}}{{end}}</small></span></a>
{{end}}{{end}}
<h2>Ktoś nowy</h2>
<form action="{{.CallbackPath}}" method="get">
 <input type="hidden" name="state" value="{{.State}}">
 <input type="email" name="email" placeholder="adres@example.com" required>
 <button>Wejdź</button>
</form>
<p><a href="{{.Callback}}&error=access_denied">Anuluj</a></p>
</body></html>`))

type mockUser struct {
	ID         uuid.UUID
	Name       string
	Email      string
	Households string
	Initial    string
}

type mockMember struct {
	ID          uuid.UUID
	Name        string
	Household   string
	InviteEmail *string
	Color       template.CSS
	Initial     string
}

func initial(s string) string {
	for _, r := range s {
		return strings.ToUpper(string(r))
	}
	return "?"
}

func (a *Auth) mockPicker(c *gin.Context) {
	db := a.DB.WithContext(c.Request.Context())
	var users []mockUser
	if err := db.Raw(`
		SELECT u.id, u.name, u.email,
		       coalesce(string_agg(h.name, ', ' ORDER BY h.name), '') AS households
		FROM users u
		LEFT JOIN members m ON m.user_id = u.id
		LEFT JOIN households h ON h.id = m.household_id
		GROUP BY u.id ORDER BY lower(u.name), u.email`).Scan(&users).Error; err != nil {
		FailErr(c, err)
		return
	}
	var rows []struct {
		ID          uuid.UUID
		Name        string
		Household   string
		InviteEmail *string
		Color       int64
	}
	if err := db.Raw(`
		SELECT m.id, m.name, h.name AS household, m.invite_email, m.color
		FROM members m JOIN households h ON h.id = m.household_id
		WHERE m.user_id IS NULL ORDER BY h.name, m.created_at`).Scan(&rows).Error; err != nil {
		FailErr(c, err)
		return
	}
	for i := range users {
		users[i].Initial = initial(users[i].Name)
	}
	members := make([]mockMember, len(rows))
	for i, r := range rows {
		members[i] = mockMember{r.ID, r.Name, r.Household, r.InviteEmail,
			template.CSS(fmt.Sprintf("#%06x", r.Color&0xFFFFFF)), initial(r.Name)}
	}
	callbackPath := cookiePath + "/callback"
	c.Header("Content-Type", "text/html; charset=utf-8")
	_ = mockPage.Execute(c.Writer, map[string]any{
		"Users":        users,
		"Members":      members,
		"State":        c.Query("state"),
		"CallbackPath": callbackPath,
		"Callback":     template.URL(callbackPath + "?" + url.Values{"state": {c.Query("state")}}.Encode()),
	})
}

// mockIdentity: who was picked on the mock page (parameters above).
func (a *Auth) mockIdentity(ctx context.Context, c *gin.Context) (uuid.UUID, error) {
	db := a.DB.WithContext(ctx)
	switch {
	case c.Query("user") != "":
		id, err := uuid.Parse(c.Query("user"))
		if err != nil {
			return uuid.Nil, err
		}
		found, err := scanUUID(db.Raw("SELECT id FROM users WHERE id = ?", id))
		if err == nil && found == uuid.Nil {
			err = errors.New("nie ma takiego konta")
		}
		return found, err

	case c.Query("member") != "":
		id, err := uuid.Parse(c.Query("member"))
		if err != nil {
			return uuid.Nil, err
		}
		var m Member
		if err := db.First(&m, "id = ? AND user_id IS NULL", id).Error; err != nil {
			return uuid.Nil, err
		}
		email := ""
		if m.InviteEmail != nil {
			email = *m.InviteEmail // LoginUser attaches the member
		} else {
			email = strings.ToLower(strings.ReplaceAll(m.Name, " ", ".")) + "." + m.ID.String()[:8] + "@mock.local"
		}
		userID, err := a.LoginUser(ctx, Identity{
			Provider: "mock", Subject: m.ID.String(), Email: email, EmailVerified: true, Name: m.Name,
		})
		if err != nil {
			return uuid.Nil, err
		}
		return userID, db.Exec(`
			UPDATE members m SET user_id = ?, invite_email = NULL
			WHERE m.id = ? AND m.user_id IS NULL
			  AND NOT EXISTS (SELECT 1 FROM members o
			                  WHERE o.household_id = m.household_id AND o.user_id = ?)`,
			userID, m.ID, userID).Error

	case c.Query("email") != "":
		email := strings.ToLower(strings.TrimSpace(c.Query("email")))
		name, _, _ := strings.Cut(email, "@")
		// Same provider as /auth/dev/login — the accounts are shared.
		return a.LoginUser(ctx, Identity{
			Provider: "dev", Subject: email, Email: email, EmailVerified: true, Name: name,
		})
	}
	return uuid.Nil, errors.New("mock: nie wybrano nikogo")
}
