package todo

import (
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"slices"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

// InboxEntry is one thing in a member's inbox (see migration 00014).
type InboxEntry struct {
	ID          uuid.UUID  `json:"id" gorm:"type:uuid;primaryKey"`
	HouseholdID uuid.UUID  `json:"household_id"`
	MemberID    uuid.UUID  `json:"member_id"`
	Kind        string     `json:"kind"`
	ListID      uuid.UUID  `json:"list_id"`
	ItemID      *uuid.UUID `json:"item_id"`
	CommentID   *uuid.UUID `json:"comment_id"`
	ActorID     *uuid.UUID `json:"actor_id"`
	Title       string     `json:"title"`
	Excerpt     string     `json:"excerpt"`
	ReadAt      *time.Time `json:"read_at"`
	// Recurring: made by a recurring task template (no human actor).
	Recurring bool      `json:"recurring"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
	Version   int       `json:"version" gorm:"default:1"`
}

func (InboxEntry) TableName() string { return "todo_inbox" }

const (
	entityInbox = "todo_inbox"

	kindMention   = "mention"
	kindReply     = "reply"
	kindAssigned  = "assigned"
	kindRecurring = "recurring"

	inboxSnapshotLimit = 100
	excerptRunes       = 280
)

// A mention in markdown text is a link to a member: [@Anna](member:<uuid>).
var mentionRe = regexp.MustCompile(`\]\(member:([0-9a-fA-F-]{36})\)`)

// mentionedIDs: the distinct member ids mentioned in text, in order.
func mentionedIDs(text string) []uuid.UUID {
	var out []uuid.UUID
	for _, m := range mentionRe.FindAllStringSubmatch(text, -1) {
		if id, err := uuid.Parse(m[1]); err == nil && !slices.Contains(out, id) {
			out = append(out, id)
		}
	}
	return out
}

// notices collects the inbox rows of one write: at most one per member, the
// most specific kind wins.
type notices struct {
	order []uuid.UUID
	kinds map[uuid.UUID]string
}

var kindRank = map[string]int{kindAssigned: 3, kindMention: 2, kindReply: 1}

func (n *notices) add(member uuid.UUID, kind string) {
	if n.kinds == nil {
		n.kinds = map[uuid.UUID]string{}
	}
	prev, ok := n.kinds[member]
	if !ok {
		n.order = append(n.order, member)
	}
	if !ok || kindRank[kind] > kindRank[prev] {
		n.kinds[member] = kind
	}
}

// mentions adds the members mentioned in text who weren't already in before
// (so re-saving a description doesn't notify again). Unknown ids are skipped.
func (n *notices) mentions(tx *gorm.DB, hh uuid.UUID, text, before string) error {
	ids := mentionedIDs(text)
	old := mentionedIDs(before)
	ids = slices.DeleteFunc(ids, func(id uuid.UUID) bool { return slices.Contains(old, id) })
	if len(ids) == 0 {
		return nil
	}
	var known []uuid.UUID
	if err := tx.Table("members").Where("household_id = ? AND id IN ?", hh, ids).
		Pluck("id", &known).Error; err != nil {
		return err
	}
	for _, id := range ids {
		if slices.Contains(known, id) {
			n.add(id, kindMention)
		}
	}
	return nil
}

// participants adds everyone taking part in a task's thread as a reply: the
// assignee, whoever commented and whoever already got something about it.
func (n *notices) participants(tx *gorm.DB, hh uuid.UUID, item Item) error {
	if item.AssigneeID != nil {
		n.add(*item.AssigneeID, kindReply)
	}
	var ids []uuid.UUID
	err := tx.Raw(`SELECT author_id FROM todo_comments
	                WHERE household_id = ? AND item_id = ? AND author_id IS NOT NULL
	               UNION
	               SELECT member_id FROM todo_inbox WHERE household_id = ? AND item_id = ?`,
		hh, item.ID, hh, item.ID).Scan(&ids).Error
	for _, id := range ids {
		n.add(id, kindReply)
	}
	return err
}

// save writes the collected rows, leaving out the actor.
func (n *notices) save(tx *gorm.DB, actor core.Actor, e InboxEntry) error {
	var rows []InboxEntry
	for _, m := range n.order {
		if m == actor.MemberID {
			continue
		}
		r := e
		r.ID = uuid.New()
		r.HouseholdID = actor.HouseholdID
		r.MemberID = m
		r.Kind = n.kinds[m]
		if actor.MemberID != uuid.Nil {
			r.ActorID = &actor.MemberID
		}
		if runes := []rune(r.Excerpt); len(runes) > excerptRunes {
			r.Excerpt = string(runes[:excerptRunes]) + "…"
		}
		rows = append(rows, r)
	}
	if len(rows) == 0 {
		return nil
	}
	return tx.Create(&rows).Error
}

// notifyComment: a new comment mentions people and replies to the thread.
func notifyComment(tx *gorm.DB, actor core.Actor, cm Comment) error {
	var item Item
	if err := tx.Where("household_id = ? AND id = ?", actor.HouseholdID, cm.ItemID).First(&item).Error; err != nil {
		return err
	}
	var n notices
	if err := n.mentions(tx, actor.HouseholdID, cm.Body, ""); err != nil {
		return err
	}
	if err := n.participants(tx, actor.HouseholdID, item); err != nil {
		return err
	}
	return n.save(tx, actor, InboxEntry{
		ListID: item.ListID, ItemID: &item.ID, CommentID: &cm.ID, Title: item.Title, Excerpt: cm.Body,
	})
}

// notifyItem: a task got an assignee or new mentions in its description.
// before is the zero Item for a new task.
func notifyItem(tx *gorm.DB, actor core.Actor, before, after Item) error {
	var n notices
	if after.AssigneeID != nil && (before.AssigneeID == nil || *before.AssigneeID != *after.AssigneeID) {
		n.add(*after.AssigneeID, kindAssigned)
	}
	if err := n.mentions(tx, actor.HouseholdID, after.Description, before.Description); err != nil {
		return err
	}
	return n.save(tx, actor, InboxEntry{ListID: after.ListID, ItemID: &after.ID, Title: after.Title})
}

// notifyList: new mentions in a list's description.
func notifyList(tx *gorm.DB, actor core.Actor, before, after List) error {
	var n notices
	if err := n.mentions(tx, actor.HouseholdID, after.Description, before.Description); err != nil {
		return err
	}
	return n.save(tx, actor, InboxEntry{ListID: after.ID, Title: after.Name})
}

// updateInbox: the recipient marks an entry read (read_at) or unread (null).
func (m Module) updateInbox(c *gin.Context) {
	id, ok := core.ParamUUID(c, "id")
	if !ok {
		return
	}
	p, ok := core.BindPatch(c)
	if !ok {
		return
	}
	var readAt time.Time
	cols, err := p.Apply(map[string]any{"read_at": &readAt})
	if err != nil {
		core.Fail(c, http.StatusBadRequest, "bad_request", err.Error())
		return
	}
	actor := core.ActorOf(c)
	errNotMine := errors.New("not the recipient")
	var row InboxEntry
	err = core.Write(c.Request.Context(), m.DB, actor, core.MutationID(c), func(tx *gorm.DB) error {
		if err := tx.Where("household_id = ? AND id = ?", actor.HouseholdID, id).First(&row).Error; err != nil {
			return err
		}
		if row.MemberID != actor.MemberID {
			return errNotMine
		}
		return update(tx, &row, actor.HouseholdID, id, cols)
	})
	if errors.Is(err, errNotMine) {
		core.Fail(c, http.StatusForbidden, "forbidden", "only the recipient can change an inbox entry")
		return
	}
	respond(c, http.StatusOK, &row, err)
}

// todo.inbox{member_id} — a member's inbox, newest first (the last 100).
// Everyone in a household sees its tasks anyway, so the member is a plain param.
type inboxView struct{}

type inboxParams struct {
	MemberID uuid.UUID `json:"member_id"`
}

func (inboxView) Name() string { return "todo.inbox" }

func (inboxView) ParseParams(raw json.RawMessage) (any, error) {
	var p inboxParams
	if err := json.Unmarshal(raw, &p); err != nil || p.MemberID == uuid.Nil {
		return nil, errors.New("member_id is required")
	}
	return p, nil
}

func (inboxView) Snapshot(tx *gorm.DB, hh uuid.UUID, params any) (core.Entities, error) {
	p := params.(inboxParams)
	rows := []InboxEntry{}
	err := tx.Where("household_id = ? AND member_id = ?", hh, p.MemberID).
		Order("created_at DESC, id").Limit(inboxSnapshotLimit).Find(&rows).Error
	return core.Entities{entityInbox: rows}, err
}

func (inboxView) Matches(params any, entity string, row json.RawMessage) bool {
	if entity != entityInbox {
		return false
	}
	e, ok := core.DecodeRow[InboxEntry](row)
	return ok && e.MemberID == params.(inboxParams).MemberID
}
