package todo

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"oikoboard/server/internal/core"
)

// Attachment is an uploaded file (core.Files) attached to a task or to one of
// its comments. Its id is the file's id.
type Attachment struct {
	ID          uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey"`
	HouseholdID uuid.UUID  `json:"household_id"`
	ItemID      uuid.UUID  `json:"item_id"`
	CommentID   *uuid.UUID `json:"comment_id"` // null: the task's own
	Name        string     `json:"name"`
	Mime        string     `json:"mime"`
	Size        int64      `json:"size"`
	CreatedBy   *uuid.UUID `json:"created_by"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	Version     int        `json:"version" gorm:"default:1"`
}

func (Attachment) TableName() string { return "todo_attachments" }

const entityAttachments = "todo_attachments"

// FileRefs: the files in use (core.FileOwner).
func (Module) FileRefs() []string { return []string{"SELECT id FROM todo_attachments"} }

// attach attaches uploaded files to a task (comment nil) or a comment. Files
// that don't exist (e.g. cleaned up) are skipped; already attached ones too.
func attach(tx *gorm.DB, actor core.Actor, item uuid.UUID, comment *uuid.UUID, ids []uuid.UUID) ([]Attachment, error) {
	files, err := core.FileMetas(tx, actor.HouseholdID, ids)
	if err != nil || len(files) == 0 {
		return []Attachment{}, err
	}
	rows := make([]Attachment, 0, len(files))
	for _, f := range files {
		a := Attachment{ID: f.ID, HouseholdID: actor.HouseholdID, ItemID: item, CommentID: comment,
			Name: f.Name, Mime: f.Mime, Size: f.Size}
		if actor.MemberID != uuid.Nil {
			a.CreatedBy = &actor.MemberID
		}
		rows = append(rows, a)
	}
	if err := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&rows).Error; err != nil {
		return nil, err
	}
	out := []Attachment{}
	err = tx.Where("household_id = ? AND id IN ?", actor.HouseholdID, ids).Find(&out).Error
	return out, err
}

// createAttachment attaches one uploaded file to an existing task or comment.
func (m Module) createAttachment(c *gin.Context) {
	var req struct {
		ID        uuid.UUID  `json:"id" binding:"required"` // the file's id
		ItemID    uuid.UUID  `json:"item_id" binding:"required"`
		CommentID *uuid.UUID `json:"comment_id"`
	}
	if !core.Bind(c, &req) {
		return
	}
	actor := core.ActorOf(c)
	var row Attachment
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		if req.CommentID != nil {
			var n int64
			if err := tx.Model(&Comment{}).Where("household_id = ? AND id = ? AND item_id = ?",
				actor.HouseholdID, *req.CommentID, req.ItemID).Count(&n).Error; err != nil {
				return err
			}
			if n == 0 {
				return gorm.ErrForeignKeyViolated
			}
		}
		rows, err := attach(tx, actor, req.ItemID, req.CommentID, []uuid.UUID{req.ID})
		if err != nil {
			return err
		}
		if len(rows) == 0 {
			return gorm.ErrRecordNotFound // no such file
		}
		row = rows[0]
		if row.ItemID != req.ItemID {
			return core.ErrIDConflict // attached elsewhere
		}
		return nil
	})
	respond(c, http.StatusCreated, &row, err)
}

// deleteAttachment removes the attachment and its file.
func (m Module) deleteAttachment(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	actor := core.ActorOf(c)
	err := core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		var n int64
		if err := tx.Model(&Attachment{}).Where("household_id = ? AND id = ?", actor.HouseholdID, id).
			Count(&n).Error; err != nil {
			return err
		}
		if n == 0 {
			return gorm.ErrRecordNotFound
		}
		// the attachment goes with it (ON DELETE CASCADE)
		return tx.Exec("DELETE FROM files WHERE household_id = ? AND id = ?", actor.HouseholdID, id).Error
	})
	if err != nil {
		core.FailErr(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// todo.attachments{item_id} — the files of one task and of its comments.
type attachmentsView struct{}

func (attachmentsView) Name() string { return "todo.attachments" }

func (attachmentsView) ParseParams(raw json.RawMessage) (any, error) {
	var p commentsParams
	if err := json.Unmarshal(raw, &p); err != nil || p.ItemID == uuid.Nil {
		return nil, errors.New("item_id is required")
	}
	return p, nil
}

func (attachmentsView) Snapshot(tx *gorm.DB, hh uuid.UUID, params any) (core.Entities, error) {
	p := params.(commentsParams)
	rows := []Attachment{}
	err := tx.Where("household_id = ? AND item_id = ?", hh, p.ItemID).Order("created_at, id").Find(&rows).Error
	return core.Entities{entityAttachments: rows}, err
}

func (attachmentsView) Matches(params any, entity string, row json.RawMessage) bool {
	if entity != entityAttachments {
		return false
	}
	a, ok := core.DecodeRow[Attachment](row)
	return ok && a.ItemID == params.(commentsParams).ItemID
}
