package mcp

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"
	sdk "github.com/modelcontextprotocol/go-sdk/mcp"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
)

// The MCP server is a thin, task-oriented layer over the REST API: tools call
// the API in-process with the caller's token, so writes go through the
// same handlers, validation and change feed as the app's, and reads use the
// same views. Names of people, lists and calendars are resolved here, and
// times are in the household's timezone.

// MCP returns the /mcp handler. api is the REST router (/api/v1/...).
func Handler(db *gorm.DB, auth *core.Auth, api http.Handler) http.Handler {
	srv := sdk.NewServer(&sdk.Implementation{Name: "oikoboard", Version: "1"}, &sdk.ServerOptions{
		Instructions: "Household todo lists and calendar. Call `family` first: it gives today's date, " +
			"the timezone, people (and who \"me\" is), lists and calendars.",
	})
	t := tools{db: db, api: api}
	t.register(srv)
	h := sdk.NewStreamableHTTPHandler(func(*http.Request) *sdk.Server { return srv },
		&sdk.StreamableHTTPOptions{Stateless: true, JSONResponse: true})
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		actor, err := auth.ResolveOAuth(r.Context(), token)
		if err != nil {
			// Tells OAuth clients where to authorize (MCP authorization spec).
			w.Header().Set("WWW-Authenticate", fmt.Sprintf(`Bearer resource_metadata=%q, scope="oikoboard"`,
				auth.ResourceMetadataURL(r)))
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			w.Write([]byte(`{"error":"invalid_token"}`))
			return
		}
		ctx := context.WithValue(r.Context(), callerKey{}, callerCtx{actor: actor, token: token})
		h.ServeHTTP(w, r.WithContext(ctx))
	})
}

type callerKey struct{}

type callerCtx struct {
	actor core.Actor
	token string
}

func callerOf(ctx context.Context) callerCtx { return ctx.Value(callerKey{}).(callerCtx) }

type tools struct {
	db  *gorm.DB
	api http.Handler
}

// call makes an in-process API request as the caller.
func (t tools) call(ctx context.Context, method, path string, body, out any) error {
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			return err
		}
	}
	req := httptest.NewRequestWithContext(ctx, method, "/api/v1"+path, &buf)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+callerOf(ctx).token)
	req.Header.Set("X-Mutation-Id", uuid.NewString())
	rec := httptest.NewRecorder()
	t.api.ServeHTTP(rec, req)
	res := rec.Result()
	data, _ := io.ReadAll(res.Body)
	if res.StatusCode >= 400 {
		var e struct{ Message string }
		if json.Unmarshal(data, &e) == nil && e.Message != "" {
			return errors.New(e.Message)
		}
		return fmt.Errorf("%s %s: %s", method, path, res.Status)
	}
	if out != nil && len(data) > 0 {
		return json.Unmarshal(data, out)
	}
	return nil
}

// view reads a view snapshot into out (entity → rows).
func (t tools) view(ctx context.Context, name string, params any, out any) error {
	p, _ := json.Marshal(params)
	var res struct{ Data json.RawMessage }
	if err := t.call(ctx, http.MethodGet, "/views/"+name+"?params="+url.QueryEscape(string(p)), nil, &res); err != nil {
		return err
	}
	return json.Unmarshal(res.Data, out)
}

// --- household context ---

type person struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type todoList struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Due  string `json:"due,omitempty"`
}

type calendarRef struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Writable   bool   `json:"writable"`
	TodoTarget bool   `json:"todo_target"`
}

type family struct {
	loc       *time.Location
	household core.Household
	members   []person
	lists     []todoList
	calendars []calendarRef
}

func (t tools) family(ctx context.Context, withLists, withCalendars bool) (*family, error) {
	hh := callerOf(ctx).actor.HouseholdID
	f := &family{}
	var h core.Household
	if err := t.db.WithContext(ctx).First(&h, "id = ?", hh).Error; err != nil {
		return nil, err
	}
	f.household = h
	if loc, err := time.LoadLocation(h.Timezone); err == nil {
		f.loc = loc
	} else {
		f.loc = time.UTC
	}
	if err := t.db.WithContext(ctx).Model(&core.Member{}).Where("household_id = ?", hh).
		Order("created_at").Find(&f.members).Error; err != nil {
		return nil, err
	}
	if withLists {
		var v struct {
			Lists []todoList `json:"todo_lists"`
		}
		if err := t.view(ctx, "todo.lists", struct{}{}, &v); err != nil {
			return nil, err
		}
		f.lists = v.Lists
	}
	if withCalendars {
		var v struct {
			Calendars []calendarRef `json:"calendars"`
		}
		if err := t.view(ctx, "calendar.calendars", struct{}{}, &v); err != nil {
			return nil, err
		}
		f.calendars = v.Calendars
	}
	return f, nil
}

func (f *family) today() core.Date { return core.DateOf(time.Now().In(f.loc)) }

func (f *family) memberName(id *string) string {
	if id == nil {
		return ""
	}
	for _, p := range f.members {
		if p.ID == *id {
			return p.Name
		}
	}
	return ""
}

// match finds one entry by id or (case-insensitive) name.
func match[T any](kind, ref string, items []T, id func(T) string, name func(T) string) (T, error) {
	var zero T
	ref = strings.TrimSpace(ref)
	if u, err := uuid.Parse(ref); err == nil {
		for _, it := range items {
			if id(it) == u.String() {
				return it, nil
			}
		}
	}
	var found []T
	for _, it := range items {
		if strings.EqualFold(name(it), ref) {
			found = append(found, it)
		}
	}
	if len(found) == 1 {
		return found[0], nil
	}
	names := make([]string, len(items))
	for i, it := range items {
		names[i] = name(it)
	}
	if len(found) > 1 {
		return zero, fmt.Errorf("%s %q is ambiguous — use the id", kind, ref)
	}
	return zero, fmt.Errorf("no %s %q; available: %s", kind, ref, strings.Join(names, ", "))
}

func (f *family) member(ref string) (string, error) {
	p, err := match("person", ref, f.members, func(p person) string { return p.ID },
		func(p person) string { return p.Name })
	return p.ID, err
}

func (f *family) membersOf(refs []string) ([]string, error) {
	out := []string{}
	for _, r := range refs {
		id, err := f.member(r)
		if err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, nil
}

func (f *family) list(ref string) (todoList, error) {
	return match("list", ref, f.lists, func(l todoList) string { return l.ID },
		func(l todoList) string { return l.Name })
}

func (f *family) calendar(ref string) (calendarRef, error) {
	var writable []calendarRef
	for _, c := range f.calendars {
		if c.Writable {
			writable = append(writable, c)
		}
	}
	if ref == "" {
		if len(writable) == 0 {
			return calendarRef{}, errors.New("the family has no writable calendar")
		}
		for _, c := range writable {
			if !c.TodoTarget {
				return c, nil
			}
		}
		return writable[0], nil
	}
	return match("writable calendar", ref, writable, func(c calendarRef) string { return c.ID },
		func(c calendarRef) string { return c.Name })
}

// parseWhen reads "YYYY-MM-DD" (a date: all-day semantics, UTC midnight) or
// "YYYY-MM-DDTHH:MM[:SS]" in the household timezone, or RFC 3339.
func (f *family) parseWhen(s string) (t time.Time, date bool, err error) {
	s = strings.TrimSpace(strings.Replace(s, " ", "T", 1))
	if d, err := core.ParseDate(s); err == nil {
		return d.Time, true, nil
	}
	for _, layout := range []string{time.RFC3339, "2006-01-02T15:04:05", "2006-01-02T15:04"} {
		if layout == time.RFC3339 {
			if t, err := time.Parse(layout, s); err == nil {
				return t, false, nil
			}
			continue
		}
		if t, err := time.ParseInLocation(layout, s, f.loc); err == nil {
			return t, false, nil
		}
	}
	return time.Time{}, false, fmt.Errorf("can't read %q — use YYYY-MM-DD or YYYY-MM-DDTHH:MM", s)
}

func (f *family) fmtTime(t time.Time, allDay bool) string {
	if allDay {
		return t.UTC().Format("2006-01-02")
	}
	return t.In(f.loc).Format("2006-01-02 15:04")
}

// --- tools ---

func (t tools) register(s *sdk.Server) {
	sdk.AddTool(s, &sdk.Tool{Name: "family", Description: "Today's date and time, the timezone, " +
		"family members, todo lists and calendars. Call this first."}, t.familyTool)
	sdk.AddTool(s, &sdk.Tool{Name: "list_todos", Description: "Tasks on the family's todo lists " +
		"(shopping lists are todo lists too). Open tasks only unless include_done."}, t.listTodos)
	sdk.AddTool(s, &sdk.Tool{Name: "create_todo_list", Description: "Create a todo list."}, t.createTodoList)
	sdk.AddTool(s, &sdk.Tool{Name: "add_todo", Description: "Add a task to a todo list."}, t.addTodo)
	sdk.AddTool(s, &sdk.Tool{Name: "update_todo", Description: "Change a task: title, description, assignee, " +
		"due date, or mark it done / not done. Only the given fields change."}, t.updateTodo)
	sdk.AddTool(s, &sdk.Tool{Name: "delete_todo", Description: "Delete a task."}, t.deleteTodo)
	sdk.AddTool(s, &sdk.Tool{Name: "add_comment", Description: "Add a comment (a note in the task's " +
		"discussion, signed by the caller) to a task."}, t.addComment)
	sdk.AddTool(s, &sdk.Tool{Name: "agenda", Description: "Calendar events and tasks due in a range " +
		"of days."}, t.agenda)
	sdk.AddTool(s, &sdk.Tool{Name: "create_event", Description: "Create a calendar event, optionally " +
		"recurring (returns its first occurrence)."}, t.createEvent)
	sdk.AddTool(s, &sdk.Tool{Name: "update_event", Description: "Change a calendar event (an occurrence " +
		"id from agenda). Only the given fields change."}, t.updateEvent)
	sdk.AddTool(s, &sdk.Tool{Name: "delete_event", Description: "Delete a calendar event (an occurrence " +
		"id from agenda)."}, t.deleteEvent)
}

type none struct{}

type familyOut struct {
	Today     string        `json:"today"`
	Weekday   string        `json:"weekday"`
	Now       string        `json:"now"`
	Timezone  string        `json:"timezone"`
	Household string        `json:"household"`
	Me        string        `json:"me,omitempty"` // the person using this client ("me", "my")
	Members   []person      `json:"members"`
	TodoLists []todoList    `json:"todo_lists"`
	Calendars []calendarOut `json:"calendars"`
}

type calendarOut struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Writable bool   `json:"writable"`
	Default  bool   `json:"default,omitempty"`
}

var weekdays = [...]string{"niedziela", "poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota"}

func (t tools) familyTool(ctx context.Context, _ *sdk.CallToolRequest, _ none) (*sdk.CallToolResult, familyOut, error) {
	f, err := t.family(ctx, true, true)
	if err != nil {
		return nil, familyOut{}, err
	}
	now := time.Now().In(f.loc)
	def, _ := f.calendar("")
	out := familyOut{Today: f.today().String(), Weekday: weekdays[now.Weekday()], Now: now.Format("15:04"),
		Timezone: f.loc.String(), Household: f.household.Name, Members: f.members, TodoLists: f.lists}
	if me := callerOf(ctx).actor.MemberID; me != uuid.Nil {
		id := me.String()
		out.Me = f.memberName(&id)
	}
	for _, c := range f.calendars {
		out.Calendars = append(out.Calendars, calendarOut{ID: c.ID, Name: c.Name, Writable: c.Writable,
			Default: c.ID == def.ID})
	}
	return nil, out, nil
}

type todoItem struct {
	ID          string          `json:"id"`
	ListID      string          `json:"list_id"`
	Title       string          `json:"title"`
	Description string          `json:"description"`
	Done        bool            `json:"done"`
	AssigneeID  *string         `json:"assignee_id"`
	Due         *core.Date      `json:"due"`
	DueTime     *core.TimeOfDay `json:"due_time"`
}

type todoOut struct {
	ID          string `json:"id"`
	List        string `json:"list"`
	Title       string `json:"title"`
	Description string `json:"description,omitempty"`
	Done        bool   `json:"done,omitempty"`
	Assignee    string `json:"assignee,omitempty"`
	Due         string `json:"due,omitempty"`
}

func (f *family) todoOut(it todoItem) todoOut {
	o := todoOut{ID: it.ID, Title: it.Title, Description: it.Description, Done: it.Done, Assignee: f.memberName(it.AssigneeID)}
	for _, l := range f.lists {
		if l.ID == it.ListID {
			o.List = l.Name
		}
	}
	if it.Due != nil {
		o.Due = it.Due.String()
		if it.DueTime != nil {
			o.Due += " " + it.DueTime.String()
		}
	}
	return o
}

type listTodosIn struct {
	List        string `json:"list,omitempty" jsonschema:"list name or id; all lists when empty"`
	Assignee    string `json:"assignee,omitempty" jsonschema:"only tasks assigned to this person (name or id)"`
	IncludeDone bool   `json:"include_done,omitempty" jsonschema:"also return completed tasks"`
}

type todosOut struct {
	Todos []todoOut `json:"todos"`
}

func (t tools) listTodos(ctx context.Context, _ *sdk.CallToolRequest, in listTodosIn) (*sdk.CallToolResult, todosOut, error) {
	out := todosOut{Todos: []todoOut{}}
	f, err := t.family(ctx, true, false)
	if err != nil {
		return nil, out, err
	}
	var assignee string
	if in.Assignee != "" {
		if assignee, err = f.member(in.Assignee); err != nil {
			return nil, out, err
		}
	}
	lists := f.lists
	if in.List != "" {
		l, err := f.list(in.List)
		if err != nil {
			return nil, out, err
		}
		lists = []todoList{l}
	}
	for _, l := range lists {
		var v struct {
			Items []todoItem `json:"todo_items"`
		}
		if err := t.view(ctx, "todo.list", map[string]any{"list_id": l.ID}, &v); err != nil {
			return nil, out, err
		}
		for _, it := range v.Items {
			if (it.Done && !in.IncludeDone) || (assignee != "" && (it.AssigneeID == nil || *it.AssigneeID != assignee)) {
				continue
			}
			out.Todos = append(out.Todos, f.todoOut(it))
		}
	}
	return nil, out, nil
}

type addTodoIn struct {
	List        string `json:"list" jsonschema:"list name or id"`
	Title       string `json:"title"`
	Description string `json:"description,omitempty" jsonschema:"details, markdown; mention a member as [@Name](member:<id from family>)"`
	Assignee    string `json:"assignee,omitempty" jsonschema:"person (name or id)"`
	Due         string `json:"due,omitempty" jsonschema:"due date YYYY-MM-DD, or YYYY-MM-DDTHH:MM for a time (it then gets its own event in the calendar)"`
	Done        bool   `json:"done,omitempty" jsonschema:"add it already completed"`
}

func (t tools) addTodo(ctx context.Context, _ *sdk.CallToolRequest, in addTodoIn) (*sdk.CallToolResult, todoOut, error) {
	f, err := t.family(ctx, true, false)
	if err != nil {
		return nil, todoOut{}, err
	}
	l, err := f.list(in.List)
	if err != nil {
		return nil, todoOut{}, err
	}
	body := map[string]any{"list_id": l.ID, "title": strings.TrimSpace(in.Title),
		"description": strings.TrimSpace(in.Description)}
	if in.Assignee != "" {
		if body["assignee_id"], err = f.member(in.Assignee); err != nil {
			return nil, todoOut{}, err
		}
	}
	if in.Due != "" {
		if body["due"], body["due_time"], err = parseDue(in.Due); err != nil {
			return nil, todoOut{}, err
		}
	}
	var it todoItem
	if err := t.call(ctx, http.MethodPost, "/todo/items", body, &it); err != nil {
		return nil, todoOut{}, err
	}
	if in.Done {
		if err := t.call(ctx, http.MethodPatch, "/todo/items/"+it.ID, map[string]any{"done": true}, &it); err != nil {
			return nil, todoOut{}, err
		}
	}
	return nil, f.todoOut(it), nil
}

type createTodoListIn struct {
	Name        string `json:"name"`
	Description string `json:"description,omitempty" jsonschema:"details, markdown; mention a member as [@Name](member:<id from family>)"`
	Due         string `json:"due,omitempty" jsonschema:"due date of the whole list YYYY-MM-DD"`
}

func (t tools) createTodoList(ctx context.Context, _ *sdk.CallToolRequest, in createTodoListIn) (*sdk.CallToolResult, todoList, error) {
	f, err := t.family(ctx, true, false)
	if err != nil {
		return nil, todoList{}, err
	}
	name := strings.TrimSpace(in.Name)
	if name == "" {
		return nil, todoList{}, errors.New("name is required")
	}
	if _, err := f.list(name); err == nil {
		return nil, todoList{}, fmt.Errorf("a list named %q already exists", name)
	}
	body := map[string]any{"name": name, "description": strings.TrimSpace(in.Description)}
	if in.Due != "" {
		d, err := core.ParseDate(in.Due)
		if err != nil {
			return nil, todoList{}, errors.New("due must be YYYY-MM-DD")
		}
		body["due"] = d
	}
	var l struct {
		ID   string     `json:"id"`
		Name string     `json:"name"`
		Due  *core.Date `json:"due"`
	}
	if err := t.call(ctx, http.MethodPost, "/todo/lists", body, &l); err != nil {
		return nil, todoList{}, err
	}
	out := todoList{ID: l.ID, Name: l.Name}
	if l.Due != nil {
		out.Due = l.Due.String()
	}
	return nil, out, nil
}

type updateTodoIn struct {
	ID          string  `json:"id"`
	Title       *string `json:"title,omitempty"`
	Description *string `json:"description,omitempty" jsonschema:"details, markdown (mention a member as [@Name](member:<id from family>)); empty string removes it"`
	Assignee    *string `json:"assignee,omitempty" jsonschema:"person (name or id); empty string removes the assignee"`
	Due         *string `json:"due,omitempty" jsonschema:"YYYY-MM-DD, or YYYY-MM-DDTHH:MM for a time; empty string removes the due date"`
	Done        *bool   `json:"done,omitempty"`
}

func (t tools) updateTodo(ctx context.Context, _ *sdk.CallToolRequest, in updateTodoIn) (*sdk.CallToolResult, todoOut, error) {
	f, err := t.family(ctx, true, false)
	if err != nil {
		return nil, todoOut{}, err
	}
	id, err := uuid.Parse(in.ID)
	if err != nil {
		return nil, todoOut{}, errors.New("id must be a task id from list_todos")
	}
	body := map[string]any{}
	if in.Title != nil {
		body["title"] = strings.TrimSpace(*in.Title)
	}
	if in.Description != nil {
		body["description"] = strings.TrimSpace(*in.Description)
	}
	if in.Done != nil {
		body["done"] = *in.Done
	}
	if in.Assignee != nil {
		body["assignee_id"] = nil
		if *in.Assignee != "" {
			if body["assignee_id"], err = f.member(*in.Assignee); err != nil {
				return nil, todoOut{}, err
			}
		}
	}
	if in.Due != nil {
		body["due"], body["due_time"] = nil, nil
		if *in.Due != "" {
			if body["due"], body["due_time"], err = parseDue(*in.Due); err != nil {
				return nil, todoOut{}, err
			}
		}
	}
	var it todoItem
	if err := t.call(ctx, http.MethodPatch, "/todo/items/"+id.String(), body, &it); err != nil {
		return nil, todoOut{}, err
	}
	return nil, f.todoOut(it), nil
}

// parseDue reads a task's due "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM" (household
// local time) into the API's due and due_time (nil without a time).
func parseDue(s string) (due, dueTime any, err error) {
	date, clock, timed := strings.Cut(strings.Replace(strings.TrimSpace(s), " ", "T", 1), "T")
	d, err := core.ParseDate(date)
	if err != nil {
		return nil, nil, errors.New("due must be YYYY-MM-DD or YYYY-MM-DDTHH:MM")
	}
	if !timed {
		return d, nil, nil
	}
	tm, err := core.ParseTimeOfDay(clock)
	if err != nil {
		return nil, nil, errors.New("due must be YYYY-MM-DD or YYYY-MM-DDTHH:MM")
	}
	return d, tm, nil
}

type idIn struct {
	ID string `json:"id"`
}

type deletedOut struct {
	Deleted string `json:"deleted"`
}

type addCommentIn struct {
	ID   string `json:"id" jsonschema:"task id from list_todos"`
	Body string `json:"body" jsonschema:"comment text, markdown; mention a member as [@Name](member:<id from family>) to notify them"`
}

type commentOut struct {
	ID   string `json:"id"`
	Task string `json:"task"`
	Body string `json:"body"`
}

func (t tools) addComment(ctx context.Context, _ *sdk.CallToolRequest, in addCommentIn) (*sdk.CallToolResult, commentOut, error) {
	id, err := uuid.Parse(in.ID)
	if err != nil {
		return nil, commentOut{}, errors.New("id must be a task id from list_todos")
	}
	var c struct {
		ID     string `json:"id"`
		ItemID string `json:"item_id"`
		Body   string `json:"body"`
	}
	body := map[string]any{"item_id": id.String(), "body": strings.TrimSpace(in.Body)}
	if err := t.call(ctx, http.MethodPost, "/todo/comments", body, &c); err != nil {
		return nil, commentOut{}, err
	}
	return nil, commentOut{ID: c.ID, Task: c.ItemID, Body: c.Body}, nil
}

func (t tools) deleteTodo(ctx context.Context, _ *sdk.CallToolRequest, in idIn) (*sdk.CallToolResult, deletedOut, error) {
	id, err := uuid.Parse(in.ID)
	if err != nil {
		return nil, deletedOut{}, errors.New("id must be a task id from list_todos")
	}
	if err := t.call(ctx, http.MethodDelete, "/todo/items/"+id.String(), nil, nil); err != nil {
		return nil, deletedOut{}, err
	}
	return nil, deletedOut{Deleted: id.String()}, nil
}

// --- calendar ---

type event struct {
	ID          string     `json:"id"`
	CalendarID  string     `json:"calendar_id"`
	Title       string     `json:"title"`
	Description string     `json:"description"`
	Location    string     `json:"location"`
	StartsAt    time.Time  `json:"starts_at"`
	EndsAt      time.Time  `json:"ends_at"`
	AllDay      bool       `json:"all_day"`
	MemberIDs   []string   `json:"member_ids"`
	Recurrence  []string   `json:"recurrence"`
	Original    *time.Time `json:"original_start"`
	Kind        string     `json:"kind"`
}

type eventOut struct {
	ID          string   `json:"id"`
	Title       string   `json:"title"`
	Start       string   `json:"start"`
	End         string   `json:"end"`
	AllDay      bool     `json:"all_day,omitempty"`
	Calendar    string   `json:"calendar"`
	Members     []string `json:"members,omitempty"`
	Location    string   `json:"location,omitempty"`
	Description string   `json:"description,omitempty"`
	Recurring   bool     `json:"recurring,omitempty"`
}

func (f *family) eventOut(e event) eventOut {
	o := eventOut{ID: e.ID, Title: e.Title, AllDay: e.AllDay, Location: e.Location, Description: e.Description,
		Recurring: e.Original != nil, Start: f.fmtTime(e.StartsAt, e.AllDay)}
	end := e.EndsAt
	if e.AllDay { // inclusive last day
		end = end.AddDate(0, 0, -1)
	}
	o.End = f.fmtTime(end, e.AllDay)
	for _, c := range f.calendars {
		if c.ID == e.CalendarID {
			o.Calendar = c.Name
		}
	}
	for _, id := range e.MemberIDs {
		o.Members = append(o.Members, f.memberName(&id))
	}
	return o
}

type agendaIn struct {
	From   string `json:"from,omitempty" jsonschema:"first day YYYY-MM-DD; today when empty"`
	Days   int    `json:"days,omitempty" jsonschema:"number of days, default 1, max 62"`
	Member string `json:"member,omitempty" jsonschema:"only events and tasks of this person (name or id)"`
}

type agendaOut struct {
	From     string     `json:"from"`
	To       string     `json:"to"`
	Events   []eventOut `json:"events"`
	TodosDue []todoOut  `json:"todos_due"`
}

func (t tools) agenda(ctx context.Context, _ *sdk.CallToolRequest, in agendaIn) (*sdk.CallToolResult, agendaOut, error) {
	out := agendaOut{Events: []eventOut{}, TodosDue: []todoOut{}}
	f, err := t.family(ctx, true, true)
	if err != nil {
		return nil, out, err
	}
	from := f.today()
	if in.From != "" {
		if from, err = core.ParseDate(in.From); err != nil {
			return nil, out, errors.New("from must be YYYY-MM-DD")
		}
	}
	days := min(max(in.Days, 1), 62)
	to := from.AddDays(days) // exclusive
	var who string
	if in.Member != "" {
		if who, err = f.member(in.Member); err != nil {
			return nil, out, err
		}
	}
	out.From, out.To = from.String(), to.AddDays(-1).String()

	start := time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, f.loc)
	end := time.Date(to.Year(), to.Month(), to.Day(), 0, 0, 0, 0, f.loc)
	var ev struct {
		Events []event `json:"calendar_events"`
	}
	if err := t.view(ctx, "calendar.range", map[string]any{"from": start, "to": end}, &ev); err != nil {
		return nil, out, err
	}
	for _, e := range ev.Events {
		if e.Kind != "" { // due-task days; tasks are listed below
			continue
		}
		if e.AllDay && (!e.EndsAt.After(from.Time) || !e.StartsAt.Before(to.Time)) {
			continue // all-day dates are UTC midnights: compare as dates
		}
		if who != "" && !contains(e.MemberIDs, who) {
			continue
		}
		out.Events = append(out.Events, f.eventOut(e))
	}
	var td struct {
		Items []todoItem `json:"todo_items"`
	}
	if err := t.view(ctx, "todo.open", struct{}{}, &td); err != nil {
		return nil, out, err
	}
	for _, it := range td.Items {
		if it.Due == nil || it.Due.Before(from.Time) || !it.Due.Before(to.Time) {
			continue
		}
		if who != "" && (it.AssigneeID == nil || *it.AssigneeID != who) {
			continue
		}
		out.TodosDue = append(out.TodosDue, f.todoOut(it))
	}
	return nil, out, nil
}

func contains(ids []string, id string) bool {
	for _, x := range ids {
		if x == id {
			return true
		}
	}
	return false
}

type createEventIn struct {
	Title       string   `json:"title"`
	Start       string   `json:"start" jsonschema:"YYYY-MM-DDTHH:MM (local time), or YYYY-MM-DD for an all-day event"`
	End         string   `json:"end,omitempty" jsonschema:"same format as start; for all-day events the last day (inclusive). Default: 1 hour / 1 day"`
	Calendar    string   `json:"calendar,omitempty" jsonschema:"calendar name or id; the default calendar when empty"`
	Members     []string `json:"members,omitempty" jsonschema:"people taking part (names or ids)"`
	Location    string   `json:"location,omitempty"`
	Description string   `json:"description,omitempty"`
	Recurrence  []string `json:"recurrence,omitempty" jsonschema:"makes a recurring event: iCalendar lines, e.g. [\"RRULE:FREQ=WEEKLY;BYDAY=MO,WE\"] or [\"RRULE:FREQ=MONTHLY;COUNT=6\"]; EXDATE/RDATE lines are allowed too"`
}

// span turns start/end strings into API times. A date-only start makes an
// all-day event (end date inclusive).
func (f *family) span(startS, endS string) (start, end time.Time, allDay bool, err error) {
	start, allDay, err = f.parseWhen(startS)
	if err != nil {
		return
	}
	switch {
	case endS == "" && allDay:
		end = start.AddDate(0, 0, 1)
	case endS == "":
		end = start.Add(time.Hour)
	default:
		var endDate bool
		if end, endDate, err = f.parseWhen(endS); err != nil {
			return
		}
		if endDate != allDay {
			err = errors.New("start and end must both be dates or both be date-times")
			return
		}
		if allDay {
			end = end.AddDate(0, 0, 1)
		}
	}
	if end.Before(start) {
		err = errors.New("end is before start")
	}
	return
}

func (t tools) createEvent(ctx context.Context, _ *sdk.CallToolRequest, in createEventIn) (*sdk.CallToolResult, eventOut, error) {
	f, err := t.family(ctx, false, true)
	if err != nil {
		return nil, eventOut{}, err
	}
	cal, err := f.calendar(in.Calendar)
	if err != nil {
		return nil, eventOut{}, err
	}
	start, end, allDay, err := f.span(in.Start, in.End)
	if err != nil {
		return nil, eventOut{}, err
	}
	members, err := f.membersOf(in.Members)
	if err != nil {
		return nil, eventOut{}, err
	}
	body := map[string]any{"calendar_id": cal.ID, "title": strings.TrimSpace(in.Title), "starts_at": start,
		"ends_at": end, "all_day": allDay, "member_ids": members, "location": in.Location,
		"description": in.Description}
	if len(in.Recurrence) > 0 {
		lines := make([]string, len(in.Recurrence))
		for i, l := range in.Recurrence {
			lines[i] = strings.TrimSpace(l)
			if !strings.Contains(lines[i], ":") {
				lines[i] = "RRULE:" + lines[i] // a bare "FREQ=..." rule
			}
		}
		body["recurrence"] = lines
	}
	var e event
	if err := t.call(ctx, http.MethodPost, "/calendar/events", body, &e); err != nil {
		return nil, eventOut{}, err
	}
	return nil, f.eventOut(e), nil
}

type updateEventIn struct {
	ID          string    `json:"id" jsonschema:"occurrence id from agenda"`
	Series      bool      `json:"series,omitempty" jsonschema:"for a recurring event: change the whole series instead of this occurrence"`
	Title       *string   `json:"title,omitempty"`
	Start       *string   `json:"start,omitempty" jsonschema:"YYYY-MM-DDTHH:MM, or YYYY-MM-DD for all-day"`
	End         *string   `json:"end,omitempty" jsonschema:"same format as start; all-day: the last day (inclusive)"`
	Members     *[]string `json:"members,omitempty" jsonschema:"the complete new list of people (names or ids)"`
	Location    *string   `json:"location,omitempty"`
	Description *string   `json:"description,omitempty"`
}

func scope(series bool) string {
	if series {
		return "?scope=series"
	}
	return "?scope=this"
}

func (t tools) updateEvent(ctx context.Context, _ *sdk.CallToolRequest, in updateEventIn) (*sdk.CallToolResult, eventOut, error) {
	f, err := t.family(ctx, false, true)
	if err != nil {
		return nil, eventOut{}, err
	}
	id, err := uuid.Parse(in.ID)
	if err != nil {
		return nil, eventOut{}, errors.New("id must be an event id from agenda")
	}
	body := map[string]any{}
	if in.Title != nil {
		body["title"] = *in.Title
	}
	if in.Location != nil {
		body["location"] = *in.Location
	}
	if in.Description != nil {
		body["description"] = *in.Description
	}
	if in.Members != nil {
		if body["member_ids"], err = f.membersOf(*in.Members); err != nil {
			return nil, eventOut{}, err
		}
	}
	if in.Start != nil || in.End != nil {
		if in.Start == nil {
			return nil, eventOut{}, errors.New("give start together with end")
		}
		endS := ""
		if in.End != nil {
			endS = *in.End
		}
		start, end, allDay, err := f.span(*in.Start, endS)
		if err != nil {
			return nil, eventOut{}, err
		}
		body["starts_at"], body["ends_at"], body["all_day"] = start, end, allDay
	}
	var e event
	if err := t.call(ctx, http.MethodPatch, "/calendar/events/"+id.String()+scope(in.Series), body, &e); err != nil {
		return nil, eventOut{}, err
	}
	if e.ID == "" { // the series moved: occurrence ids changed
		return nil, eventOut{ID: id.String(), Title: "updated (series moved — call agenda for new ids)"}, nil
	}
	return nil, f.eventOut(e), nil
}

type deleteEventIn struct {
	ID     string `json:"id" jsonschema:"occurrence id from agenda"`
	Series bool   `json:"series,omitempty" jsonschema:"for a recurring event: delete the whole series"`
}

func (t tools) deleteEvent(ctx context.Context, _ *sdk.CallToolRequest, in deleteEventIn) (*sdk.CallToolResult, deletedOut, error) {
	id, err := uuid.Parse(in.ID)
	if err != nil {
		return nil, deletedOut{}, errors.New("id must be an event id from agenda")
	}
	if err := t.call(ctx, http.MethodDelete, "/calendar/events/"+id.String()+scope(in.Series), nil, nil); err != nil {
		return nil, deletedOut{}, err
	}
	return nil, deletedOut{Deleted: id.String()}, nil
}
