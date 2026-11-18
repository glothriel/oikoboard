# Calendar

The family calendar has no storage of its own: every calendar lives at an external **provider** (Google today,
CalDAV later) and the server keeps a **mirror** of it. Changes flow both ways.

Code: `server/internal/modules/calendar/`, migration `00005_calendar_sources.sql`, app `app/lib/modules/calendar/`.

## Model

```
calendar_connections   a user's provider account (OAuth grant, sealed credentials)
  └─< calendars         a provider calendar linked to a household (tracked → realtime);
        │                todo_target: the one that receives due tasks (see below)
        ├─ calendar_sync_state       sync token, last sync (untracked: polling makes no changes)
        ├─< calendar_remote_events   the mirror: series masters, exceptions, single events
        └─< calendar_events          occurrences — what the app, views and MCP read (tracked)

```

The view the app opens with (day / 3 days / week / month) is remembered on the device, not on the server.

- **Provider** (`provider.go`) is the only abstraction point: `ListCalendars`, `Changes(token)`, `Put`, `Delete`.
  Implementations: `google_provider.go` (Calendar API v3, plain REST) and `mock_provider.go` (dev/tests, stored in
  Postgres, mimics Google's semantics).
- **Occurrences** are materialized from the mirror in the same transaction: single events 1:1, series expanded
  (RRULE/EXDATE via `rrule-go`) from a year back to two years ahead; the window moves daily. Only differences are
  written, so the change feed carries real changes only.
- **Ids are derived**: mirror id = uuid5(calendar, remote id), occurrence id = uuid5(series, original start). The mirror
  can be rebuilt from the provider alone and gets the same ids; an exception keeps the id of the instance it replaces.

## Sync

- **Our writes go to the provider first.** The provider returns the stored event, which is applied to the mirror in
  the same request — the response and realtime already show the stored state. A client-chosen id becomes the remote
  id, so a retried create doesn't duplicate.
- **Changes made elsewhere** are pulled by polling with sync tokens (`OIKO_CALENDAR_SYNC`, default 2m). An expired
  token (410) triggers a full listing, which also prunes the mirror. Push webhooks are possible later (need public HTTPS).
- **Ordering:** a mirror row is only replaced by a version with `updated` ≥ its own, and writes and syncs of one
  calendar are serialized, so a slow sync can't revert or prune a fresh write. Conflicts are last-write-wins.
- **Revoked access** (`invalid_grant`) marks the connection `revoked`; its calendars show a sync error until the
  account is connected again.

## Recurring events

The API edits occurrences: `PATCH|DELETE /calendar/events/:id?scope=this|series`.

- `this` (default) creates/updates an exception (the instance id `<series>_<start>`, Google's format) or cancels it.
- `series` changes the master; a time change shifts every occurrence by the same delta and **resets exceptions**
  (they would no longer line up with the instances).

## Field mapping

| Oikoboard (mirror)                 | Google Calendar API v3                    | iCalendar / CalDAV               |
|------------------------------------|-------------------------------------------|----------------------------------|
| `remote_id`                        | `id`                                      | resource name + `UID`            |
| `etag`, `remote_updated`           | `etag`, `updated`                         | `ETag`, `LAST-MODIFIED`          |
| `status`                           | `status`                                  | `STATUS`                         |
| `title`                            | `summary`                                 | `SUMMARY`                        |
| `description`                      | `description`                             | `DESCRIPTION`                    |
| `location`                         | `location`                                | `LOCATION`                       |
| `starts_at`, `ends_at` (UTC)       | `start/end.dateTime`                      | `DTSTART`, `DTEND`               |
| `all_day` (dates at UTC midnight, end exclusive) | `start/end.date`            | `DTSTART;VALUE=DATE`             |
| `timezone` (IANA; empty = calendar's) | `start.timeZone`                       | `TZID`                           |
| `recurrence` (lines as-is)         | `recurrence[]`                            | `RRULE`, `EXDATE`, `RDATE`       |
| `series_remote_id`, `original_start` | `recurringEventId`, `originalStartTime` | same `UID` + `RECURRENCE-ID`     |
| `member_ids`                       | `extendedProperties.private["oiko.members"]` (comma-separated uuids) | `X-OIKO-MEMBERS` |
| `attendee_emails` (read only)      | `attendees[].email`                       | `ATTENDEE`                       |
| `kind` (managed events, see below) | `extendedProperties.private["oiko.kind"]` | `X-OIKO-KIND`                    |

- Writes send only these fields (PATCH), so reminders, colors, attachments etc. set at the provider are kept.
- **Members** live in the event itself, so a rebuilt mirror loses nothing. Attendees are never written (that would
  invite people by e-mail); when an event has no members, attendees whose e-mail is a member's account count as members.

## Due tasks

Tasks with a due date (`todo_items.due`, a date) and lists with one (`todo_lists.due`) appear in the household's
**todo target** calendar as one all-day event per day with open tasks or lists due, `kind = "todo-day"`: title
"Zadanie: <title>", "Lista: <name>" or "Zadania: N", the entries listed in the description, the assignees as members. The app renders these as a task chip that opens the day's tasks; the
events API refuses to edit them (409 `managed_event`).

- **Target:** the first writable calendar linked to the household; changeable (`PATCH /calendars/:id
  {"todo_target": true}`). Unlinking the target first deletes its task events, then the oldest remaining writable
  calendar takes over.
- **Reconciliation, not event handling** (`todo_sync.go`): desired state = open tasks and lists (unless all their tasks are done) due from 30 days back to a year
  ahead, grouped by date (in the calendar's time zone); actual state = the mirror's `todo-day` rows of the household.
  The differences are written to the provider (`Put` / `Delete`) and applied to the mirror. A moved, finished or
  deleted task therefore just changes the desired state — an emptied day loses its event. Older events are left alone.
- **Runs** after task writes (debounced 2 s per household), after linking or retargeting, and after every sync poll.
- **Oikoboard owns these events:** an edit or deletion made in Google is undone by the next reconciliation.
- **Ids** are derived from (household, date), so a repeated create can't duplicate a day.

## Connecting an account

Same Google client and callback as sign-in (see [auth.md](auth.md)), as a separate flow with
`calendar.events` + `calendar.calendarlist.readonly`, offline access and consent. The signed-in app starts it
(`POST /calendar/connections`) and finishes it with the one-time code and its PKCE verifier
(`POST /calendar/connections/complete`) — only the account that started a flow can complete it. Refresh tokens are
encrypted with `OIKO_SECRET_KEY` (AES-GCM). With `OIKO_MOCK_OAUTH=1` the flow skips Google and creates a mock account.

The Google OAuth app must be **In production** (unverified is fine for a family): in *Testing*, refresh tokens expire
after 7 days.
