package core

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"database/sql/driver"
	"encoding/base64"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Household struct {
	ID        uuid.UUID `json:"id" gorm:"type:uuid;default:gen_random_uuid()"`
	Name      string    `json:"name"`
	Timezone  string    `json:"timezone" gorm:"default:Europe/Warsaw"`
	CreatedAt time.Time `json:"created_at"`
}

type Member struct {
	ID          uuid.UUID  `json:"id" gorm:"type:uuid;default:gen_random_uuid()"`
	HouseholdID uuid.UUID  `json:"household_id"`
	Name        string     `json:"name"`
	Color       int64      `json:"color"`
	UserID      *uuid.UUID `json:"-"`
	InviteEmail *string    `json:"-"`
	CreatedAt   time.Time  `json:"created_at"`
}

type User struct {
	ID        uuid.UUID `json:"id" gorm:"type:uuid;default:gen_random_uuid()"`
	Email     string    `json:"email"`
	Name      string    `json:"name"`
	Picture   *string   `json:"picture"`
	CreatedAt time.Time `json:"created_at"`
}

// AuthConfig — konfiguracja logowania (z env w main).
type AuthConfig struct {
	Google *GoogleConfig // nil = logowanie Google wyłączone
	// Logowanie samym e-mailem, bez weryfikacji. TYLKO do developmentu
	// i testów (kilka osób w kilku kartach bez kilku kont Google).
	DevLogin bool
	// Mock Google: /auth/google/start shows a "who are you?" page (an
	// existing account, a member without an account or any e-mail) instead
	// of Google; the rest of the flow is real. Local development ONLY.
	MockOAuth bool
	// Encrypts provider credentials (calendar refresh tokens) at rest.
	Sealer *Sealer
	// Dokąd wolno wrócić po logowaniu (adres aplikacji). Wzorce:
	// "http://localhost:*" (dowolny port), "https://oiko.example.com",
	// "oikoboard://auth" (Android).
	ReturnURLs []string
	// Publiczny adres aplikacji webowej — do linków z zaproszeniami.
	AppURL string
	// Public URL of this API (OIKO_PUBLIC_URL): OAuth issuer and MCP resource.
	// Empty = derived from each request (local development, tests).
	PublicURL string
}

type Auth struct {
	DB     *gorm.DB
	Config AuthConfig
	google *googleClient
}

func NewAuth(db *gorm.DB, cfg AuthConfig) *Auth {
	a := &Auth{DB: db, Config: cfg}
	if cfg.Google != nil {
		a.google = &googleClient{cfg: *cfg.Google}
	}
	return a
}

func randomToken() string {
	buf := make([]byte, 32)
	_, _ = rand.Read(buf)
	return base64.RawURLEncoding.EncodeToString(buf)
}

// tokenHash: bytea w zapytaniach (gołe []byte GORM rozwinąłby w listę).
type tokenHash []byte

func (h tokenHash) Value() (driver.Value, error) { return []byte(h), nil }

func hashToken(t string) tokenHash {
	h := sha256.Sum256([]byte(t))
	return h[:]
}

// pkceChallenge: BASE64URL(SHA256(verifier)), jak w RFC 7636 (S256).
func pkceChallenge(verifier string) string {
	h := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(h[:])
}

// Resolve zamienia token sesji na Actora. Konto bez rodziny dostaje
// Actora z pustym HouseholdID.
func (a *Auth) Resolve(ctx context.Context, token string) (Actor, error) {
	if token == "" {
		return Actor{}, errors.New("brak tokena")
	}
	var row struct {
		UserID      uuid.UUID
		MemberID    *uuid.UUID
		HouseholdID *uuid.UUID
	}
	// Wybrana rodzina z sesji, a gdy jej nie ma (lub konto już do niej nie
	// należy) — pierwsza, do której konto należy.
	err := a.DB.WithContext(ctx).Raw(`
		WITH s AS (
			UPDATE sessions SET last_seen_at = now()
			WHERE token_hash = ?
			RETURNING user_id, member_id
		)
		SELECT s.user_id, m.id AS member_id, m.household_id
		FROM s
		LEFT JOIN LATERAL (
			SELECT id, household_id FROM members
			WHERE user_id = s.user_id
			ORDER BY (id = s.member_id) DESC NULLS LAST, created_at
			LIMIT 1
		) m ON true`, hashToken(token)).Scan(&row).Error
	if err != nil {
		return Actor{}, err
	}
	if row.UserID == uuid.Nil {
		return Actor{}, errors.New("nieznana sesja")
	}
	act := Actor{UserID: row.UserID}
	if row.MemberID != nil {
		act.MemberID, act.HouseholdID = *row.MemberID, *row.HouseholdID
	}
	return act, nil
}

func bearer(c *gin.Context) string {
	t, _ := strings.CutPrefix(c.GetHeader("Authorization"), "Bearer ")
	return t
}

// UserMiddleware: wystarczy zalogowane konto (np. zakładanie rodziny).
func (a *Auth) UserMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		actor, err := a.Resolve(c.Request.Context(), bearer(c))
		if err != nil {
			Fail(c, http.StatusUnauthorized, "unauthorized", "zaloguj się")
			return
		}
		c.Set(actorKey, actor)
		c.Next()
	}
}

// Middleware: the account must belong to a household (module data, views).
// OAuth access tokens (AI chats acting for a member) are accepted too,
// for module data only (see ToolAllowed).
func (a *Auth) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		actor, err := a.Resolve(c.Request.Context(), bearer(c))
		if err != nil {
			if agent, aerr := a.ResolveOAuth(c.Request.Context(), bearer(c)); aerr == nil {
				if !ToolAllowed(c.Request.Method, c.FullPath()) {
					Fail(c, http.StatusForbidden, "forbidden", "not available to connected apps")
					return
				}
				c.Set(actorKey, agent)
				c.Next()
				return
			}
		}
		if err != nil {
			Fail(c, http.StatusUnauthorized, "unauthorized", "zaloguj się")
			return
		}
		if !actor.InHousehold() {
			Fail(c, http.StatusForbidden, "no_household", "dołącz do rodziny lub załóż nową")
			return
		}
		c.Set(actorKey, actor)
		c.Next()
	}
}

func (a *Auth) newSession(ctx context.Context, userID uuid.UUID) (string, error) {
	token := randomToken()
	err := a.DB.WithContext(ctx).Exec(
		"INSERT INTO sessions (token_hash, user_id) VALUES (?, ?)",
		hashToken(token), userID).Error
	return token, err
}

// setSessionMember zapamiętuje w sesji wybraną rodzinę.
func (a *Auth) setSessionMember(tx *gorm.DB, token string, memberID uuid.UUID) error {
	return tx.Exec("UPDATE sessions SET member_id = ? WHERE token_hash = ?",
		memberID, hashToken(token)).Error
}

// scanUUID czyta jedną wartość uuid (uuid.Nil, gdy brak wierszy).
// GORM-owe Scan traktuje uuid.UUID jak tablicę bajtów, więc przez sql.Row.
func scanUUID(q *gorm.DB) (uuid.UUID, error) {
	var id uuid.UUID
	err := q.Row().Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return uuid.Nil, nil
	}
	return id, err
}

// Identity — to, co wiemy o osobie od dostawcy logowania.
type Identity struct {
	Provider      string
	Subject       string
	Email         string
	EmailVerified bool
	Name          string
	Picture       string
}

// LoginUser znajduje albo zakłada konto dla tożsamości. Przy
// zweryfikowanym e-mailu przypina konto do członków rodzin, którzy na nie
// czekają (members.invite_email).
func (a *Auth) LoginUser(ctx context.Context, id Identity) (uuid.UUID, error) {
	if id.Provider == "" || id.Subject == "" || id.Email == "" {
		return uuid.Nil, errors.New("niepełna tożsamość")
	}
	var userID uuid.UUID
	err := a.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var pic *string
		if id.Picture != "" {
			pic = &id.Picture
		}
		var err error
		userID, err = scanUUID(tx.Raw("SELECT user_id FROM identities WHERE provider = ? AND subject = ?",
			id.Provider, id.Subject))
		if err != nil {
			return err
		}
		if userID == uuid.Nil {
			u := User{Email: id.Email, Name: id.Name, Picture: pic}
			if err := tx.Create(&u).Error; err != nil {
				return err
			}
			userID = u.ID
			if err := tx.Exec("INSERT INTO identities (provider, subject, user_id) VALUES (?, ?, ?)",
				id.Provider, id.Subject, userID).Error; err != nil {
				return err
			}
		} else if err := tx.Model(&User{}).Where("id = ?", userID).
			Updates(map[string]any{"email": id.Email, "name": id.Name, "picture": pic}).Error; err != nil {
			return err
		}
		if !id.EmailVerified {
			return nil
		}
		return tx.Exec(`
			UPDATE members m SET user_id = ?, invite_email = NULL
			WHERE m.user_id IS NULL AND lower(m.invite_email) = lower(?)
			  AND NOT EXISTS (SELECT 1 FROM members o
			                  WHERE o.household_id = m.household_id AND o.user_id = ?)`,
			userID, id.Email, userID).Error
	})
	return userID, err
}

type memberOut struct {
	Member
	HasAccount bool    `json:"has_account"`
	Picture    *string `json:"picture"` // the account's profile picture (Google)
}

type membership struct {
	MemberID      uuid.UUID `json:"member_id"`
	HouseholdID   uuid.UUID `json:"household_id"`
	HouseholdName string    `json:"household_name"`
}

// Routes: publiczne endpointy logowania.
func (a *Auth) Routes(r *gin.RouterGroup) {
	r.GET("/auth/config", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"google": a.google != nil || a.Config.MockOAuth, "dev_login": a.Config.DevLogin})
	})

	if a.google != nil || a.Config.MockOAuth {
		r.GET("/auth/google/start", a.googleStart)
		r.GET("/auth/google/callback", a.googleCallback)
	}
	if a.Config.MockOAuth {
		slog.Warn("OIKO_MOCK_OAUTH is on — Google sign-in is faked, anyone can sign in as anyone")
		r.GET("/auth/google/mock", a.mockPicker)
	}

	// Aplikacja wymienia jednorazowy kod (z przekierowania po logowaniu)
	// na token sesji. verifier musi pasować do challenge podanego przy
	// starcie — kod przechwycony z URL-a nikomu innemu się nie przyda.
	r.POST("/auth/exchange", func(c *gin.Context) {
		var req struct {
			Code     string `json:"code" binding:"required"`
			Verifier string `json:"verifier" binding:"required"`
		}
		if !Bind(c, &req) {
			return
		}
		userID, err := a.exchangeLogin(c.Request.Context(), req.Code, req.Verifier)
		if errors.Is(err, errBadLoginCode) {
			Fail(c, http.StatusBadRequest, "bad_code", "kod logowania jest nieważny — spróbuj ponownie")
			return
		} else if err != nil {
			FailErr(c, err)
			return
		}
		token, err := a.newSession(c.Request.Context(), userID)
		if err != nil {
			FailErr(c, err)
			return
		}
		c.JSON(http.StatusOK, gin.H{"token": token})
	})

	if a.Config.DevLogin {
		slog.Warn("OIKO_DEV_LOGIN włączony — każdy może zalogować się dowolnym e-mailem")
		r.POST("/auth/dev/login", func(c *gin.Context) {
			var req struct {
				Email string `json:"email" binding:"required,email"`
				Name  string `json:"name"`
			}
			if !Bind(c, &req) {
				return
			}
			email := strings.ToLower(strings.TrimSpace(req.Email))
			name := req.Name
			if name == "" {
				name, _, _ = strings.Cut(email, "@")
			}
			userID, err := a.LoginUser(c.Request.Context(), Identity{
				Provider: "dev", Subject: email, Email: email, EmailVerified: true, Name: name,
			})
			if err != nil {
				FailErr(c, err)
				return
			}
			token, err := a.newSession(c.Request.Context(), userID)
			if err != nil {
				FailErr(c, err)
				return
			}
			c.JSON(http.StatusOK, gin.H{"token": token})
		})
	}
}

var errBadLoginCode = errors.New("invalid sign-in code")

// exchangeLogin burns the one-time code of a finished sign-in flow and
// returns the account; verifier must match the challenge the flow started with.
func (a *Auth) exchangeLogin(ctx context.Context, code, verifier string) (uuid.UUID, error) {
	var flow struct {
		UserID       *uuid.UUID
		AppChallenge string
	}
	err := a.DB.WithContext(ctx).Raw(`
		DELETE FROM auth_flows
		WHERE code_hash = ? AND purpose = 'login' AND created_at > now() - interval '15 minutes'
		RETURNING user_id, app_challenge`, hashToken(code)).Scan(&flow).Error
	if err != nil {
		return uuid.Nil, err
	}
	if flow.UserID == nil || subtle.ConstantTimeCompare(
		[]byte(pkceChallenge(verifier)), []byte(flow.AppChallenge)) != 1 {
		return uuid.Nil, errBadLoginCode
	}
	return *flow.UserID, nil
}

// AccountRoutes: wymagają konta, ale nie rodziny.
func (a *Auth) AccountRoutes(r *gin.RouterGroup) {
	r.GET("/me", a.me)

	r.POST("/auth/logout", func(c *gin.Context) {
		a.DB.WithContext(c.Request.Context()).Exec(
			"DELETE FROM sessions WHERE token_hash = ?", hashToken(bearer(c)))
		c.Status(http.StatusNoContent)
	})

	// Przełączenie na inną rodzinę konta.
	r.POST("/auth/switch", func(c *gin.Context) {
		var req struct {
			MemberID uuid.UUID `json:"member_id" binding:"required"`
		}
		if !Bind(c, &req) {
			return
		}
		res := a.DB.WithContext(c.Request.Context()).Exec(`
			UPDATE sessions SET member_id = m.id FROM members m
			WHERE sessions.token_hash = ? AND m.id = ? AND m.user_id = sessions.user_id`,
			hashToken(bearer(c)), req.MemberID)
		if res.Error != nil {
			FailErr(c, res.Error)
			return
		}
		if res.RowsAffected == 0 {
			Fail(c, http.StatusNotFound, "not_found", "nie należysz do tej rodziny")
			return
		}
		c.Status(http.StatusNoContent)
	})

	r.POST("/households", a.createHousehold)
	r.GET("/invites/:token", a.previewInvite)
	r.POST("/invites/:token/accept", a.acceptInvite)
}

// ProtectedRoutes: wymagają rodziny.
func (a *Auth) ProtectedRoutes(r *gin.RouterGroup) {
	r.POST("/invites", a.createInvite)
	r.DELETE("/invites/:id", a.revokeInvite)
}

// me: konto, wybrana rodzina (lub null) z członkami i wszystkie rodziny konta.
func (a *Auth) me(c *gin.Context) {
	actor := ActorOf(c)
	db := a.DB.WithContext(c.Request.Context())
	var user User
	if err := db.First(&user, "id = ?", actor.UserID).Error; err != nil {
		FailErr(c, err)
		return
	}
	ms := []membership{}
	if err := db.Raw(`
		SELECT m.id AS member_id, h.id AS household_id, h.name AS household_name
		FROM members m JOIN households h ON h.id = m.household_id
		WHERE m.user_id = ? ORDER BY m.created_at`, actor.UserID).Scan(&ms).Error; err != nil {
		FailErr(c, err)
		return
	}
	out := gin.H{"user": user, "memberships": ms, "member_id": nil, "household": nil, "members": []memberOut{}}
	if actor.InHousehold() {
		var hh Household
		var members []memberOut
		if err := db.First(&hh, "id = ?", actor.HouseholdID).Error; err != nil {
			FailErr(c, err)
			return
		}
		if err := db.Raw(`SELECT m.*, m.user_id IS NOT NULL AS has_account
			FROM members m
			WHERE m.household_id = ? ORDER BY m.created_at`, hh.ID).Scan(&members).Error; err != nil {
			FailErr(c, err)
			return
		}
		out["member_id"], out["household"], out["members"] = actor.MemberID, hh, members
	}
	c.JSON(http.StatusOK, out)
}
