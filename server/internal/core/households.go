package core

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

const inviteTTL = 7 * 24 * time.Hour

// Kolory nowych członków (ARGB), po kolei.
var memberColors = []int64{0xFF5C6BC0, 0xFFE57373, 0xFFAB47BC, 0xFF26A69A, 0xFFFFA726, 0xFF8D6E63, 0xFF42A5F5, 0xFF9CCC65}

func nextColor(tx *gorm.DB, hh uuid.UUID) int64 {
	var n int64
	tx.Model(&Member{}).Where("household_id = ?", hh).Count(&n)
	return memberColors[int(n)%len(memberColors)]
}

func (a *Auth) userName(tx *gorm.DB, userID uuid.UUID) string {
	var u User
	if tx.First(&u, "id = ?", userID).Error != nil {
		return ""
	}
	if first, _, _ := strings.Cut(u.Name, " "); first != "" {
		return first
	}
	name, _, _ := strings.Cut(u.Email, "@")
	return name
}

// createHousehold: nowa rodzina, zakładający zostaje jej pierwszym członkiem.
func (a *Auth) createHousehold(c *gin.Context) {
	var req struct {
		Name       string `json:"name" binding:"required,max=100"`
		MemberName string `json:"member_name" binding:"max=50"`
		Timezone   string `json:"timezone" binding:"max=64"` // IANA, from the device; empty = default
	}
	if !Bind(c, &req) {
		return
	}
	actor := ActorOf(c)
	var m Member
	err := a.DB.WithContext(c.Request.Context()).Transaction(func(tx *gorm.DB) error {
		hh := Household{Name: strings.TrimSpace(req.Name)}
		if _, err := time.LoadLocation(req.Timezone); err == nil && req.Timezone != "" && req.Timezone != "Local" {
			hh.Timezone = req.Timezone
		}
		if err := tx.Create(&hh).Error; err != nil {
			return err
		}
		name := strings.TrimSpace(req.MemberName)
		if name == "" {
			name = a.userName(tx, actor.UserID)
		}
		m = Member{HouseholdID: hh.ID, Name: name, Color: memberColors[0], UserID: &actor.UserID}
		if err := tx.Create(&m).Error; err != nil {
			return err
		}
		return a.setSessionMember(tx, bearer(c), m.ID)
	})
	if err != nil {
		FailErr(c, err)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"member_id": m.ID, "household_id": m.HouseholdID})
}

// createInvite: link dla nowej osoby albo dla istniejącego członka bez
// konta (np. „Kuba” dodany przez rodzica). Jednorazowy, ważny 7 dni.
func (a *Auth) createInvite(c *gin.Context) {
	var req struct {
		MemberID *uuid.UUID `json:"member_id"`
	}
	if !Bind(c, &req) {
		return
	}
	actor := ActorOf(c)
	db := a.DB.WithContext(c.Request.Context())
	if req.MemberID != nil {
		var m Member
		if err := db.First(&m, "id = ? AND household_id = ?", *req.MemberID, actor.HouseholdID).Error; err != nil {
			FailErr(c, err)
			return
		}
		if m.UserID != nil {
			Fail(c, http.StatusConflict, "has_account", m.Name+" ma już konto")
			return
		}
	}
	token := randomToken()
	expires := time.Now().Add(inviteTTL)
	id, err := scanUUID(db.Raw(`
		INSERT INTO invites (household_id, token_hash, member_id, created_by, expires_at)
		VALUES (?, ?, ?, ?, ?) RETURNING id`,
		actor.HouseholdID, hashToken(token), req.MemberID, actor.MemberID, expires))
	if err != nil {
		FailErr(c, err)
		return
	}
	out := gin.H{"id": id, "token": token, "expires_at": expires}
	if a.Config.AppURL != "" {
		out["url"] = withQuery(a.Config.AppURL, "invite", token)
	}
	c.JSON(http.StatusCreated, out)
}

func (a *Auth) revokeInvite(c *gin.Context) {
	id, ok := ParamUUID(c, "id")
	if !ok {
		return
	}
	res := a.DB.WithContext(c.Request.Context()).Exec(
		"DELETE FROM invites WHERE id = ? AND household_id = ?", id, ActorOf(c).HouseholdID)
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

type invite struct {
	ID            uuid.UUID
	HouseholdID   uuid.UUID
	HouseholdName string
	MemberID      *uuid.UUID
	MemberName    *string
	InvitedBy     *string
	ExpiresAt     time.Time
}

const inviteSQL = `
	SELECT i.id, i.household_id, h.name AS household_name, i.member_id,
	       m.name AS member_name, cb.name AS invited_by, i.expires_at
	FROM invites i
	JOIN households h ON h.id = i.household_id
	LEFT JOIN members m ON m.id = i.member_id
	LEFT JOIN members cb ON cb.id = i.created_by
	WHERE i.token_hash = ? AND i.used_at IS NULL AND i.expires_at > now()`

var errBadInvite = errors.New("zaproszenie jest nieważne")

func failInvite(c *gin.Context) {
	Fail(c, http.StatusNotFound, "bad_invite", "zaproszenie jest nieważne, wykorzystane albo wygasło")
}

// previewInvite: do czego zaprasza link (przed dołączeniem).
func (a *Auth) previewInvite(c *gin.Context) {
	var inv invite
	if err := a.DB.WithContext(c.Request.Context()).Raw(inviteSQL, hashToken(c.Param("token"))).
		Scan(&inv).Error; err != nil {
		FailErr(c, err)
		return
	}
	if inv.ID == uuid.Nil {
		failInvite(c)
		return
	}
	var already int64
	a.DB.WithContext(c.Request.Context()).Model(&Member{}).
		Where("household_id = ? AND user_id = ?", inv.HouseholdID, ActorOf(c).UserID).Count(&already)
	c.JSON(http.StatusOK, gin.H{
		"household_name": inv.HouseholdName, "member_name": inv.MemberName,
		"invited_by": inv.InvitedBy, "expires_at": inv.ExpiresAt, "already_member": already > 0,
	})
}

// acceptInvite: dołączenie do rodziny (jako nowa osoba albo jako członek,
// dla którego było zaproszenie). Sesja przełącza się na tę rodzinę.
func (a *Auth) acceptInvite(c *gin.Context) {
	var req struct {
		Name string `json:"name" binding:"max=50"`
	}
	if c.Request.ContentLength > 0 && !Bind(c, &req) {
		return
	}
	actor := ActorOf(c)
	var memberID uuid.UUID
	err := a.DB.WithContext(c.Request.Context()).Transaction(func(tx *gorm.DB) error {
		var inv invite
		if err := tx.Raw(inviteSQL+" FOR UPDATE OF i", hashToken(c.Param("token"))).Scan(&inv).Error; err != nil {
			return err
		}
		if inv.ID == uuid.Nil {
			return errBadInvite
		}
		// Już w tej rodzinie? Tylko przełączamy, zaproszenie zostaje.
		var err error
		memberID, err = scanUUID(tx.Raw("SELECT id FROM members WHERE household_id = ? AND user_id = ?",
			inv.HouseholdID, actor.UserID))
		if err != nil {
			return err
		}
		if memberID != uuid.Nil {
			return a.setSessionMember(tx, bearer(c), memberID)
		}
		if inv.MemberID != nil {
			res := tx.Exec("UPDATE members SET user_id = ?, invite_email = NULL WHERE id = ? AND user_id IS NULL",
				actor.UserID, *inv.MemberID)
			if res.Error != nil {
				return res.Error
			}
			if res.RowsAffected == 0 {
				return errBadInvite
			}
			memberID = *inv.MemberID
		} else {
			name := strings.TrimSpace(req.Name)
			if name == "" {
				name = a.userName(tx, actor.UserID)
			}
			m := Member{HouseholdID: inv.HouseholdID, Name: name,
				Color: nextColor(tx, inv.HouseholdID), UserID: &actor.UserID}
			if err := tx.Create(&m).Error; err != nil {
				return err
			}
			memberID = m.ID
		}
		if err := tx.Exec("UPDATE invites SET used_at = now(), used_by = ? WHERE id = ?",
			actor.UserID, inv.ID).Error; err != nil {
			return err
		}
		return a.setSessionMember(tx, bearer(c), memberID)
	})
	if errors.Is(err, errBadInvite) {
		failInvite(c)
		return
	}
	if err != nil {
		FailErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"member_id": memberID})
}
