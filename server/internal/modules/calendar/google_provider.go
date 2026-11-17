package calendar

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"golang.org/x/oauth2"
)

// googleProvider talks to the Google Calendar API v3 (REST/JSON).
type googleProvider struct {
	http *http.Client
	base string
}

const (
	membersProp = "oiko.members"
	kindProp    = "oiko.kind"
)

type gTime struct {
	Date     string `json:"date,omitempty"`
	DateTime string `json:"dateTime,omitempty"`
	TimeZone string `json:"timeZone,omitempty"`
}

type gEvent struct {
	ID                 string   `json:"id,omitempty"`
	Status             string   `json:"status,omitempty"`
	ETag               string   `json:"etag,omitempty"`
	Updated            string   `json:"updated,omitempty"`
	Summary            *string  `json:"summary,omitempty"`
	Description        *string  `json:"description,omitempty"`
	Location           *string  `json:"location,omitempty"`
	Start              *gTime   `json:"start,omitempty"`
	End                *gTime   `json:"end,omitempty"`
	Recurrence         []string `json:"recurrence,omitempty"`
	RecurringEventID   string   `json:"recurringEventId,omitempty"`
	OriginalStartTime  *gTime   `json:"originalStartTime,omitempty"`
	ExtendedProperties *struct {
		Private map[string]string `json:"private,omitempty"`
	} `json:"extendedProperties,omitempty"`
	Attendees []struct {
		Email string `json:"email"`
	} `json:"attendees,omitempty"`
}

type gError struct {
	Status int
	Body   string
}

func (e *gError) Error() string { return fmt.Sprintf("google calendar: %d %s", e.Status, e.Body) }

// Message is Google's human-readable explanation (e.g. "Google Calendar API
// has not been used in project … or it is disabled").
func (e *gError) Message() string {
	var b struct {
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if json.Unmarshal([]byte(e.Body), &b) == nil && b.Error.Message != "" {
		return b.Error.Message
	}
	return http.StatusText(e.Status)
}

func (g googleProvider) do(ctx context.Context, method, path string, q url.Values, body any, out any) error {
	u := g.base + path
	if len(q) > 0 {
		u += "?" + q.Encode()
	}
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, u, rd)
	if err != nil {
		return err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := g.http.Do(req)
	if err != nil {
		var re *oauth2.RetrieveError
		if errors.As(err, &re) && re.ErrorCode == "invalid_grant" {
			return ErrRevoked
		}
		return err
	}
	defer res.Body.Close()
	if res.StatusCode >= 300 {
		b, _ := io.ReadAll(io.LimitReader(res.Body, 2048))
		return &gError{res.StatusCode, strings.TrimSpace(string(b))}
	}
	if out != nil {
		return json.NewDecoder(res.Body).Decode(out)
	}
	return nil
}

func statusOf(err error) int {
	var ge *gError
	if errors.As(err, &ge) {
		return ge.Status
	}
	return 0
}

func calPath(calID string) string { return "/calendars/" + url.PathEscape(calID) + "/events" }

func (g googleProvider) ListCalendars(ctx context.Context) ([]RemoteCalendar, error) {
	var out []RemoteCalendar
	page := ""
	for {
		var res struct {
			Items []struct {
				ID              string `json:"id"`
				Summary         string `json:"summary"`
				SummaryOverride string `json:"summaryOverride"`
				BackgroundColor string `json:"backgroundColor"`
				AccessRole      string `json:"accessRole"`
				TimeZone        string `json:"timeZone"`
			} `json:"items"`
			NextPageToken string `json:"nextPageToken"`
		}
		q := url.Values{"minAccessRole": {"reader"}}
		if page != "" {
			q.Set("pageToken", page)
		}
		if err := g.do(ctx, "GET", "/users/me/calendarList", q, nil, &res); err != nil {
			return nil, err
		}
		for _, c := range res.Items {
			name := c.SummaryOverride
			if name == "" {
				name = c.Summary
			}
			out = append(out, RemoteCalendar{
				RemoteID: c.ID, Name: name, Color: parseHexColor(c.BackgroundColor),
				Writable: c.AccessRole == "owner" || c.AccessRole == "writer", TimeZone: c.TimeZone,
			})
		}
		if page = res.NextPageToken; page == "" {
			return out, nil
		}
	}
}

func parseHexColor(s string) int64 {
	v, err := strconv.ParseInt(strings.TrimPrefix(s, "#"), 16, 64)
	if err != nil || len(s) != 7 {
		return 0xFF5C6BC0
	}
	return 0xFF000000 | v
}

func (g googleProvider) Changes(ctx context.Context, calID, token string) (ChangeSet, error) {
	cs := ChangeSet{Full: token == ""}
	page := ""
	for {
		// showDeleted also for full listings: cancelled exceptions remove
		// occurrences from a series.
		q := url.Values{"showDeleted": {"true"}, "maxResults": {"2500"}}
		if token != "" {
			q.Set("syncToken", token)
		}
		if page != "" {
			q.Set("pageToken", page)
		}
		var res struct {
			Items         []gEvent `json:"items"`
			NextPageToken string   `json:"nextPageToken"`
			NextSyncToken string   `json:"nextSyncToken"`
		}
		if err := g.do(ctx, "GET", calPath(calID), q, nil, &res); err != nil {
			if statusOf(err) == http.StatusGone {
				return ChangeSet{}, ErrSyncReset
			}
			return ChangeSet{}, err
		}
		for _, it := range res.Items {
			ev, err := fromGoogle(it)
			if err != nil {
				return ChangeSet{}, err
			}
			if cs.Full && ev.cancelled() && ev.SeriesRemoteID == "" {
				continue
			}
			cs.Events = append(cs.Events, ev)
		}
		if page = res.NextPageToken; page == "" {
			cs.Token = res.NextSyncToken
			return cs, nil
		}
	}
}

func (g googleProvider) Put(ctx context.Context, calID string, ev RemoteEvent, create bool) (RemoteEvent, error) {
	body := toGoogle(ev)
	var out gEvent
	if create {
		body.ID = ev.RemoteID
		err := g.do(ctx, "POST", calPath(calID), nil, body, &out)
		if statusOf(err) != http.StatusConflict { // 409: retried create — update instead
			if err != nil {
				return RemoteEvent{}, err
			}
			return fromGoogle(out)
		}
		body.ID = ""
	}
	if err := g.do(ctx, "PATCH", calPath(calID)+"/"+url.PathEscape(ev.RemoteID), nil, body, &out); err != nil {
		return RemoteEvent{}, err
	}
	return fromGoogle(out)
}

func (g googleProvider) Delete(ctx context.Context, calID, remoteID string) error {
	err := g.do(ctx, "DELETE", calPath(calID)+"/"+url.PathEscape(remoteID), nil, nil, nil)
	if s := statusOf(err); s == http.StatusNotFound || s == http.StatusGone {
		return nil
	}
	return err
}

func toGoogleTime(t time.Time, allDay bool, tz string) *gTime {
	if allDay {
		return &gTime{Date: t.UTC().Format("2006-01-02")}
	}
	return &gTime{DateTime: t.Format(time.RFC3339), TimeZone: tz}
}

func toGoogle(ev RemoteEvent) gEvent {
	out := gEvent{
		Status:  ev.Status, // "confirmed" also restores an event deleted at Google
		Summary: &ev.Title, Description: &ev.Description, Location: &ev.Location,
		Start: toGoogleTime(ev.Start, ev.AllDay, ev.TimeZone),
		End:   toGoogleTime(ev.End, ev.AllDay, ev.TimeZone),
	}
	if ev.SeriesRemoteID == "" {
		// Recurrence only on masters/single events; an empty list makes a
		// series a single event again.
		out.Recurrence = ev.Recurrence
		if out.Recurrence == nil {
			out.Recurrence = []string{}
		}
	}
	ids := make([]string, len(ev.MemberIDs))
	for i, id := range ev.MemberIDs {
		ids[i] = id.String()
	}
	out.ExtendedProperties = &struct {
		Private map[string]string `json:"private,omitempty"`
	}{Private: map[string]string{membersProp: strings.Join(ids, ",")}}
	if ev.Kind != "" {
		out.ExtendedProperties.Private[kindProp] = ev.Kind
	}
	return out
}

// MarshalJSON keeps an explicitly empty recurrence (omitempty would drop it).
func (e gEvent) MarshalJSON() ([]byte, error) {
	type plain gEvent
	b, err := json.Marshal(plain(e))
	if err != nil || e.Recurrence == nil || len(e.Recurrence) > 0 {
		return b, err
	}
	return append(b[:len(b)-1], []byte(`,"recurrence":[]}`)...), nil
}

func parseGoogleTime(t *gTime) (time.Time, bool, string, error) {
	if t == nil {
		return time.Time{}, false, "", errors.New("missing time")
	}
	if t.Date != "" {
		d, err := time.Parse("2006-01-02", t.Date)
		return d, true, t.TimeZone, err
	}
	d, err := time.Parse(time.RFC3339, t.DateTime)
	return d, false, t.TimeZone, err
}

func fromGoogle(it gEvent) (RemoteEvent, error) {
	ev := RemoteEvent{
		RemoteID: it.ID, ETag: it.ETag, Status: it.Status,
		Recurrence: it.Recurrence, SeriesRemoteID: it.RecurringEventID,
	}
	if ev.Status == "" {
		ev.Status = "confirmed"
	}
	ev.Updated, _ = time.Parse(time.RFC3339, it.Updated)
	if ev.Updated.IsZero() {
		ev.Updated = time.Now().UTC()
	}
	if it.Summary != nil {
		ev.Title = *it.Summary
	}
	if it.Description != nil {
		ev.Description = *it.Description
	}
	if it.Location != nil {
		ev.Location = *it.Location
	}
	if it.OriginalStartTime != nil {
		t, _, _, err := parseGoogleTime(it.OriginalStartTime)
		if err != nil {
			return ev, fmt.Errorf("event %s: originalStartTime: %w", it.ID, err)
		}
		ev.OriginalStart = &t
	}
	if ev.cancelled() {
		return ev, nil // cancelled events carry no times
	}
	var err error
	if ev.Start, ev.AllDay, ev.TimeZone, err = parseGoogleTime(it.Start); err != nil {
		return ev, fmt.Errorf("event %s: start: %w", it.ID, err)
	}
	if ev.End, _, _, err = parseGoogleTime(it.End); err != nil {
		ev.End = ev.Start // Google allows events without an end
	}
	if it.ExtendedProperties != nil {
		ev.Kind = it.ExtendedProperties.Private[kindProp]
		for _, s := range strings.Split(it.ExtendedProperties.Private[membersProp], ",") {
			if id, err := uuid.Parse(strings.TrimSpace(s)); err == nil {
				ev.MemberIDs = append(ev.MemberIDs, id)
			}
		}
	}
	for _, a := range it.Attendees {
		if a.Email != "" {
			ev.AttendeeEmails = append(ev.AttendeeEmails, strings.ToLower(a.Email))
		}
	}
	return ev, nil
}
