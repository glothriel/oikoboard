// Package todo: task lists.
package todo

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

type List struct {
	ID          uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey"`
	HouseholdID uuid.UUID  `json:"household_id"`
	Name        string     `json:"name"`
	Color       int64      `json:"color"`
	Due         *core.Date `json:"due"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	Version     int        `json:"version" gorm:"default:1"`
}

func (List) TableName() string { return "todo_lists" }

type Item struct {
	ID          uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey"`
	HouseholdID uuid.UUID  `json:"household_id"`
	ListID      uuid.UUID  `json:"list_id"`
	Title       string     `json:"title"`
	Done        bool       `json:"done"`
	DoneAt      *time.Time `json:"done_at"`
	AssigneeID  *uuid.UUID `json:"assignee_id"`
	Due         *core.Date `json:"due"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	Version     int        `json:"version" gorm:"default:1"`
}

func (Item) TableName() string { return "todo_items" }

// Comment is one message in a task's thread.
type Comment struct {
	ID          uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey"`
	HouseholdID uuid.UUID  `json:"household_id"`
	ItemID      uuid.UUID  `json:"item_id"`
	AuthorID    *uuid.UUID `json:"author_id"`
	Body        string     `json:"body"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	Version     int        `json:"version" gorm:"default:1"`
}

func (Comment) TableName() string { return "todo_comments" }

const (
	entityLists    = "todo_lists"
	entityItems    = "todo_items"
	entityComments = "todo_comments"
)

type Module struct {
	DB *gorm.DB
	// OnItemsChanged is called after a write that changed the household's
	// tasks (e.g. to update the due-tasks calendar). Optional.
	OnItemsChanged func(household uuid.UUID)
}

func (m Module) itemsChanged(hh uuid.UUID) {
	if m.OnItemsChanged != nil {
		m.OnItemsChanged(hh)
	}
}

func (Module) Name() string { return "todo" }

func (m Module) Views() []core.View {
	return []core.View{listsView{}, listView{}, openView{}, commentsView{}}
}

func (m Module) Routes(r *gin.RouterGroup) {
	r.POST("/todo/lists", m.createList)
	r.PATCH("/todo/lists/:id", m.updateList)
	r.DELETE("/todo/lists/:id", m.deleteList)
	r.POST("/todo/items", m.createItem)
	r.PATCH("/todo/items/:id", m.updateItem)
	r.DELETE("/todo/items/:id", m.deleteItem)
	r.POST("/todo/comments", m.createComment)
	r.DELETE("/todo/comments/:id", m.deleteComment)
}

// --- handlers ---

func (m Module) createList(c *gin.Context) {
	var req struct {
		ID    uuid.UUID  `json:"id"`
		Name  string     `json:"name" binding:"required"`
		Color int64      `json:"color"`
		Due   *core.Date `json:"due"`
	}
	if !core.Bind(c, &req) {
		return
	}
	if req.ID == uuid.Nil {
		req.ID = uuid.New()
	}
	if req.Color == 0 {
		req.Color = 0xFF26A69A
	}
	actor := core.ActorOf(c)
	row := List{ID: req.ID, HouseholdID: actor.HouseholdID, Name: req.Name, Color: req.Color, Due: req.Due}
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		return core.CreateIdempotent(tx, &row, actor.HouseholdID, row.ID)
	})
	if err == nil && row.Due != nil {
		m.itemsChanged(actor.HouseholdID)
	}
	respond(c, http.StatusCreated, &row, err)
}

func (m Module) updateList(c *gin.Context) {
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
	var due core.Date
	cols, err := p.Apply(map[string]any{"name": &name, "color": &color, "due": &due})
	if err != nil {
		core.Fail(c, http.StatusBadRequest, "bad_request", err.Error())
		return
	}
	actor := core.ActorOf(c)
	var row List
	err = core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		return update(tx, &row, actor.HouseholdID, id, cols)
	})
	if err == nil {
		m.itemsChanged(actor.HouseholdID) // the list's name and due show in the calendar
	}
	respond(c, http.StatusOK, &row, err)
}

func (m Module) deleteList(c *gin.Context) {
	m.delete(c, &List{})
}

func (m Module) createItem(c *gin.Context) {
	var req struct {
		ID         uuid.UUID  `json:"id"`
		ListID     uuid.UUID  `json:"list_id" binding:"required"`
		Title      string     `json:"title" binding:"required"`
		AssigneeID *uuid.UUID `json:"assignee_id"`
		Due        *core.Date `json:"due"`
	}
	if !core.Bind(c, &req) {
		return
	}
	if req.ID == uuid.Nil {
		req.ID = uuid.New()
	}
	actor := core.ActorOf(c)
	row := Item{
		ID: req.ID, HouseholdID: actor.HouseholdID, ListID: req.ListID,
		Title: req.Title, AssigneeID: req.AssigneeID, Due: req.Due,
	}
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		return core.CreateIdempotent(tx, &row, actor.HouseholdID, row.ID)
	})
	if err == nil {
		m.itemsChanged(actor.HouseholdID)
	}
	respond(c, http.StatusCreated, &row, err)
}

func (m Module) updateItem(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	p, ok := core.BindPatch(c)
	if !ok {
		return
	}
	var (
		title    string
		done     bool
		assignee uuid.UUID
		due      core.Date
	)
	cols, err := p.Apply(map[string]any{
		"title": &title, "done": &done, "assignee_id": &assignee, "due": &due,
	})
	if err != nil {
		core.Fail(c, http.StatusBadRequest, "bad_request", err.Error())
		return
	}
	if d, ok := cols["done"]; ok {
		if d == true {
			cols["done_at"] = gorm.Expr("COALESCE(done_at, now())")
		} else {
			cols["done_at"] = nil
		}
	}
	actor := core.ActorOf(c)
	var row Item
	err = core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		return update(tx, &row, actor.HouseholdID, id, cols)
	})
	if err == nil {
		m.itemsChanged(actor.HouseholdID)
	}
	respond(c, http.StatusOK, &row, err)
}

func (m Module) deleteItem(c *gin.Context) {
	m.delete(c, &Item{})
}

func (m Module) createComment(c *gin.Context) {
	var req struct {
		ID     uuid.UUID `json:"id"`
		ItemID uuid.UUID `json:"item_id" binding:"required"`
		Body   string    `json:"body" binding:"required"`
	}
	if !core.Bind(c, &req) {
		return
	}
	if req.Body = strings.TrimSpace(req.Body); req.Body == "" {
		core.Fail(c, http.StatusBadRequest, "bad_request", "body is empty")
		return
	}
	if req.ID == uuid.Nil {
		req.ID = uuid.New()
	}
	actor := core.ActorOf(c)
	row := Comment{ID: req.ID, HouseholdID: actor.HouseholdID, ItemID: req.ItemID, Body: req.Body}
	if actor.MemberID != uuid.Nil {
		row.AuthorID = &actor.MemberID
	}
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		return core.CreateIdempotent(tx, &row, actor.HouseholdID, row.ID)
	})
	respond(c, http.StatusCreated, &row, err)
}

// deleteComment: only the author can delete their comment.
func (m Module) deleteComment(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	actor := core.ActorOf(c)
	errNotAuthor := errors.New("not the author")
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		var row Comment
		if err := tx.Where("household_id = ? AND id = ?", actor.HouseholdID, id).First(&row).Error; err != nil {
			return err
		}
		if row.AuthorID == nil || *row.AuthorID != actor.MemberID {
			return errNotAuthor
		}
		return tx.Delete(&row).Error
	})
	switch {
	case errors.Is(err, errNotAuthor):
		core.Fail(c, http.StatusForbidden, "forbidden", "only the author can delete a comment")
	case err != nil:
		core.FailErr(c, err)
	default:
		c.Status(http.StatusNoContent)
	}
}

func (m Module) delete(c *gin.Context, model any) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	actor := core.ActorOf(c)
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		res := tx.Where("household_id = ? AND id = ?", actor.HouseholdID, id).Delete(model)
		if res.Error == nil && res.RowsAffected == 0 {
			return gorm.ErrRecordNotFound
		}
		return res.Error
	})
	if err != nil {
		core.FailErr(c, err)
		return
	}
	m.itemsChanged(actor.HouseholdID) // also for a list: its tasks are gone
	c.Status(http.StatusNoContent)
}

// update: an UPDATE scoped to the household, then reads the row back.
func update(tx *gorm.DB, row any, hh, id uuid.UUID, cols map[string]any) error {
	if len(cols) > 0 {
		res := tx.Model(row).Where("household_id = ? AND id = ?", hh, id).Updates(cols)
		if res.Error != nil {
			return res.Error
		}
	}
	return tx.Where("household_id = ? AND id = ?", hh, id).First(row).Error
}

func respond(c *gin.Context, status int, row any, err error) {
	switch {
	case errors.Is(err, core.ErrIDConflict):
		core.Fail(c, http.StatusConflict, "id_conflict", "the id is already taken")
	case err != nil:
		core.FailErr(c, err)
	default:
		c.JSON(status, row)
	}
}

// --- views ---

// todo.lists — all lists of the household (panel / list chips).
type listsView struct{}

func (listsView) Name() string                               { return "todo.lists" }
func (listsView) ParseParams(r json.RawMessage) (any, error) { return core.NoParams(r) }

func (listsView) Snapshot(tx *gorm.DB, hh uuid.UUID, _ any) (core.Entities, error) {
	lists := []List{}
	err := tx.Where("household_id = ?", hh).Order("created_at").Find(&lists).Error
	return core.Entities{entityLists: lists}, err
}

func (listsView) Matches(_ any, entity string, _ json.RawMessage) bool {
	return entity == entityLists
}

// todo.list{list_id} — one list with all its tasks (list screen).
type listView struct{}

type listParams struct {
	ListID uuid.UUID `json:"list_id"`
}

func (listView) Name() string { return "todo.list" }

func (listView) ParseParams(raw json.RawMessage) (any, error) {
	var p listParams
	if err := json.Unmarshal(raw, &p); err != nil || p.ListID == uuid.Nil {
		return nil, errors.New("list_id is required")
	}
	return p, nil
}

func (listView) Snapshot(tx *gorm.DB, hh uuid.UUID, params any) (core.Entities, error) {
	p := params.(listParams)
	lists := []List{}
	items := []Item{}
	if err := tx.Where("household_id = ? AND id = ?", hh, p.ListID).Find(&lists).Error; err != nil {
		return nil, err
	}
	err := tx.Where("household_id = ? AND list_id = ?", hh, p.ListID).Order("created_at").Find(&items).Error
	return core.Entities{entityLists: lists, entityItems: items}, err
}

func (listView) Matches(params any, entity string, row json.RawMessage) bool {
	p := params.(listParams)
	switch entity {
	case entityLists:
		l, ok := core.DecodeRow[List](row)
		return ok && l.ID == p.ListID
	case entityItems:
		i, ok := core.DecodeRow[Item](row)
		return ok && i.ListID == p.ListID
	}
	return false
}

// todo.open — open tasks of all lists (wall, counters).
type openView struct{}

func (openView) Name() string                               { return "todo.open" }
func (openView) ParseParams(r json.RawMessage) (any, error) { return core.NoParams(r) }

func (openView) Snapshot(tx *gorm.DB, hh uuid.UUID, _ any) (core.Entities, error) {
	items := []Item{}
	err := tx.Where("household_id = ? AND NOT done", hh).Order("created_at").Find(&items).Error
	return core.Entities{entityItems: items}, err
}

func (openView) Matches(_ any, entity string, row json.RawMessage) bool {
	if entity != entityItems {
		return false
	}
	i, ok := core.DecodeRow[Item](row)
	return ok && !i.Done
}

// todo.comments{item_id} — the comment thread of one task.
type commentsView struct{}

type commentsParams struct {
	ItemID uuid.UUID `json:"item_id"`
}

func (commentsView) Name() string { return "todo.comments" }

func (commentsView) ParseParams(raw json.RawMessage) (any, error) {
	var p commentsParams
	if err := json.Unmarshal(raw, &p); err != nil || p.ItemID == uuid.Nil {
		return nil, errors.New("item_id is required")
	}
	return p, nil
}

func (commentsView) Snapshot(tx *gorm.DB, hh uuid.UUID, params any) (core.Entities, error) {
	p := params.(commentsParams)
	comments := []Comment{}
	err := tx.Where("household_id = ? AND item_id = ?", hh, p.ItemID).Order("created_at, id").Find(&comments).Error
	return core.Entities{entityComments: comments}, err
}

func (commentsView) Matches(params any, entity string, row json.RawMessage) bool {
	if entity != entityComments {
		return false
	}
	cm, ok := core.DecodeRow[Comment](row)
	return ok && cm.ItemID == params.(commentsParams).ItemID
}
