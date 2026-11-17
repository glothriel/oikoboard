package calendar

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"oikoboard/server/internal/core"
)

// Connecting an account: the app POSTs /calendar/connections, opens the
// returned URL in a browser (Google consent, or straight back in mock mode),
// comes back with ?code= and POSTs /calendar/connections/complete. Then it
// lists the account's calendars and links chosen ones to the household.

func (m Module) listConnections(c *gin.Context) {
	conns := []Connection{}
	if err := m.DB.WithContext(c.Request.Context()).Where("user_id = ?", core.ActorOf(c).UserID).
		Order("created_at").Find(&conns).Error; err != nil {
		core.FailErr(c, err)
		return
	}
	c.JSON(http.StatusOK, conns)
}

func (m Module) startConnect(c *gin.Context) {
	var req struct {
		Return    string `json:"return" binding:"required"`
		Challenge string `json:"challenge" binding:"required"`
	}
	if !core.Bind(c, &req) {
		return
	}
	path, err := m.Auth.StartConnect(c.Request.Context(), core.ActorOf(c).UserID, req.Return, req.Challenge)
	switch {
	case errors.Is(err, core.ErrBadConnect):
		core.Fail(c, http.StatusBadRequest, "bad_request", err.Error())
	case errors.Is(err, core.ErrNoSecretKey):
		core.Fail(c, http.StatusServiceUnavailable, "not_configured", "the server has no OIKO_SECRET_KEY")
	case err != nil:
		core.Fail(c, http.StatusServiceUnavailable, "not_configured", err.Error())
	default:
		c.JSON(http.StatusOK, gin.H{"url": path})
	}
}

func (m Module) completeConnect(c *gin.Context) {
	var req struct {
		Code     string `json:"code" binding:"required"`
		Verifier string `json:"verifier" binding:"required"`
	}
	if !core.Bind(c, &req) {
		return
	}
	ctx := c.Request.Context()
	userID := core.ActorOf(c).UserID
	g, err := m.Auth.CompleteConnect(ctx, userID, req.Code, req.Verifier)
	if err != nil {
		core.Fail(c, http.StatusBadRequest, "bad_code", "the connect link is invalid or expired — try again")
		return
	}
	var conn Connection
	err = m.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		err := tx.Where("user_id = ? AND provider = ? AND account = ?", userID, g.Provider, g.Account).
			First(&conn).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			conn = Connection{UserID: &userID, Provider: g.Provider, Account: g.Account, Credentials: g.Credentials}
			if err := tx.Create(&conn).Error; err != nil {
				return err
			}
		} else if err != nil {
			return err
		} else if err := tx.Model(&conn).Updates(map[string]any{
			"credentials": g.Credentials, "status": "ok"}).Error; err != nil {
			return err
		}
		if g.Provider == "mock" {
			return CreateMockCalendars(tx, conn.ID)
		}
		return nil
	})
	if err != nil {
		core.FailErr(c, err)
		return
	}
	// Reconnected: calendars that failed because of revoked access may sync again.
	go m.syncConnection(conn.ID)
	c.JSON(http.StatusOK, conn)
}

func (m Module) syncConnection(id uuid.UUID) {
	var ids []uuid.UUID
	m.DB.Raw("SELECT id FROM calendars WHERE connection_id = ?", id).Scan(&ids)
	for _, cid := range ids {
		_ = m.Syncer.SyncCalendar(context.Background(), cid)
	}
}

// ownConnection loads a connection of the signed-in user.
func (m Module) ownConnection(c *gin.Context, id uuid.UUID) (*Connection, bool) {
	var conn Connection
	if err := m.DB.WithContext(c.Request.Context()).
		First(&conn, "id = ? AND user_id = ?", id, core.ActorOf(c).UserID).Error; err != nil {
		core.FailErr(c, err)
		return nil, false
	}
	return &conn, true
}

// Disconnecting removes the account's calendars from every household.
func (m Module) deleteConnection(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	if _, ok := m.ownConnection(c, id); !ok {
		return
	}
	ctx := c.Request.Context()
	var cals []Calendar
	m.DB.WithContext(ctx).Where("connection_id = ?", id).Find(&cals)
	ids := make([]uuid.UUID, len(cals))
	for i, cal := range cals {
		ids[i] = cal.ID
	}
	m.removeManaged(ctx, ids)
	err := core.Write(ctx, m.DB, core.ActorOf(c), core.MutationID(c), func(tx *gorm.DB) error {
		if err := tx.Delete(&Connection{}, "id = ?", id).Error; err != nil {
			return err
		}
		for _, cal := range cals {
			if err := ensureTodoTarget(tx, cal.HouseholdID); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		core.FailErr(c, err)
		return
	}
	for _, cal := range cals {
		m.Syncer.TodosChanged(cal.HouseholdID)
	}
	c.Status(http.StatusNoContent)
}

func (m Module) remoteCalendars(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	conn, ok := m.ownConnection(c, id)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	p, err := m.Providers.For(ctx, m.DB, *conn)
	if err != nil {
		fail(c, err)
		return
	}
	cals, err := p.ListCalendars(ctx)
	if err != nil {
		fail(c, err)
		return
	}
	var linked []string
	m.DB.WithContext(ctx).Raw(`SELECT remote_id FROM calendars WHERE household_id = ? AND connection_id = ?`,
		core.ActorOf(c).HouseholdID, conn.ID).Scan(&linked)
	type out struct {
		RemoteCalendar
		Linked bool `json:"linked"`
	}
	res := make([]out, len(cals))
	for i, rc := range cals {
		res[i] = out{rc, false}
		for _, l := range linked {
			res[i].Linked = res[i].Linked || l == rc.RemoteID
		}
	}
	c.JSON(http.StatusOK, res)
}

func (m Module) linkCalendar(c *gin.Context) {
	var req struct {
		ConnectionID uuid.UUID `json:"connection_id" binding:"required"`
		RemoteID     string    `json:"remote_id" binding:"required"`
	}
	if !core.Bind(c, &req) {
		return
	}
	conn, ok := m.ownConnection(c, req.ConnectionID)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	p, err := m.Providers.For(ctx, m.DB, *conn)
	if err != nil {
		fail(c, err)
		return
	}
	cals, err := p.ListCalendars(ctx)
	if err != nil {
		fail(c, err)
		return
	}
	var rc *RemoteCalendar
	for i := range cals {
		if cals[i].RemoteID == req.RemoteID {
			rc = &cals[i]
		}
	}
	if rc == nil {
		core.Fail(c, http.StatusNotFound, "not_found", "no such calendar in this account")
		return
	}
	actor := core.ActorOf(c)
	tz := rc.TimeZone
	if tz == "" {
		tz = "UTC"
	}
	cal := Calendar{HouseholdID: actor.HouseholdID, ConnectionID: conn.ID, RemoteID: rc.RemoteID,
		Name: rc.Name, Color: rc.Color, Writable: rc.Writable, Timezone: tz, Account: conn.Account}
	err = core.Write(ctx, m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		res := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&cal)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return core.ErrIDConflict
		}
		if err := tx.Exec("INSERT INTO calendar_sync_state (calendar_id) VALUES (?)", cal.ID).Error; err != nil {
			return err
		}
		return ensureTodoTarget(tx, actor.HouseholdID)
	})
	if errors.Is(err, core.ErrIDConflict) {
		core.Fail(c, http.StatusConflict, "already_linked", "this calendar is already linked")
		return
	}
	if err != nil {
		core.FailErr(c, err)
		return
	}
	// First (full) sync in the background; events arrive over realtime.
	// Then due tasks, if this became the todo target.
	go func() {
		ctx := context.Background()
		if err := m.Syncer.SyncCalendar(ctx, cal.ID); err != nil {
			slog.Warn("initial calendar sync", "calendar", cal.ID, "err", err)
		}
		if err := m.Syncer.ReconcileTodos(ctx, actor.HouseholdID); err != nil {
			slog.Warn("due tasks → calendar", "household", actor.HouseholdID, "err", err)
		}
	}()
	c.JSON(http.StatusCreated, cal)
}

func (m Module) updateCalendar(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	p, ok := core.BindPatch(c)
	if !ok {
		return
	}
	var name string
	var color int64
	var todoTarget bool
	cols, err := p.Apply(map[string]any{"name": &name, "color": &color, "todo_target": &todoTarget})
	if err != nil || cols["name"] == "" || (cols["todo_target"] != nil && cols["todo_target"] != true) {
		core.Fail(c, http.StatusBadRequest, "bad_request",
			"only name, color and todo_target (true: due tasks go to this calendar) can be changed")
		return
	}
	actor := core.ActorOf(c)
	var cal Calendar
	err = core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		if _, ok := cols["todo_target"]; ok {
			if err := tx.First(&cal, "household_id = ? AND id = ?", actor.HouseholdID, id).Error; err != nil {
				return err
			}
			if !cal.Writable {
				return errReadOnly
			}
			// One target per household: move the flag.
			if err := tx.Model(&Calendar{}).Where("household_id = ? AND todo_target AND id <> ?", actor.HouseholdID, id).
				Update("todo_target", false).Error; err != nil {
				return err
			}
		}
		if len(cols) > 0 {
			if err := tx.Model(&Calendar{}).Where("household_id = ? AND id = ?", actor.HouseholdID, id).
				Updates(cols).Error; err != nil {
				return err
			}
		}
		return tx.First(&cal, "household_id = ? AND id = ?", actor.HouseholdID, id).Error
	})
	if err != nil {
		fail(c, err)
		return
	}
	if _, ok := cols["todo_target"]; ok {
		m.Syncer.TodosChanged(actor.HouseholdID) // moves the events
	}
	c.JSON(http.StatusOK, cal)
}

func (m Module) unlinkCalendar(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	actor := core.ActorOf(c)
	ctx := c.Request.Context()
	var n int64
	m.DB.WithContext(ctx).Model(&Calendar{}).Where("household_id = ? AND id = ?", actor.HouseholdID, id).Count(&n)
	if n == 0 {
		core.Fail(c, http.StatusNotFound, "not_found", "not found")
		return
	}
	m.removeManaged(ctx, []uuid.UUID{id})
	err := core.Write(ctx, m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		if err := tx.Delete(&Calendar{}, "household_id = ? AND id = ?", actor.HouseholdID, id).Error; err != nil {
			return err
		}
		return ensureTodoTarget(tx, actor.HouseholdID)
	})
	if err != nil {
		core.FailErr(c, err)
		return
	}
	m.Syncer.TodosChanged(actor.HouseholdID)
	c.Status(http.StatusNoContent)
}

// removeManaged deletes Oikoboard's own events (due tasks) from calendars
// about to be unlinked — best effort: the account may be revoked already.
func (m Module) removeManaged(ctx context.Context, calIDs []uuid.UUID) {
	for _, id := range calIDs {
		if err := m.Syncer.RemoveManaged(ctx, id); err != nil {
			slog.Warn("removing due tasks from an unlinked calendar", "calendar", id, "err", err)
		}
	}
}

func (m Module) syncCalendar(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	var n int64
	m.DB.WithContext(c.Request.Context()).Model(&Calendar{}).
		Where("household_id = ? AND id = ?", core.ActorOf(c).HouseholdID, id).Count(&n)
	if n == 0 {
		core.Fail(c, http.StatusNotFound, "not_found", "not found")
		return
	}
	if err := m.Syncer.SyncCalendar(c.Request.Context(), id); err != nil {
		fail(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}
