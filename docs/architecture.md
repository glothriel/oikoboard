# Architecture

```
Flutter app (web + Android)                    Go server                          PostgreSQL
  modules: todo, calendar…   ── REST writes ─▶  Gin handlers ── tx ─────────────▶  module tables
                             ◀─ WebSocket ───   views + dispatcher ◀── NOTIFY ──  triggers → changes
                                                calendar sync ◀──▶ Google Calendar (mirror, see calendar.md)
```

- **Writes are REST, reads are WebSocket views.** A view is a named query with params (`todo.list`,
  `calendar.range`…): the client subscribes, gets a snapshot, then only changes that match. Reconnect = resubscribe =
  fresh snapshot. The app queues writes in a persistent outbox and shows them on top of the views until the server
  confirms them, so it works offline. Details: [backend-realtime.md](backend-realtime.md).
- **Change feed in the database:** every tracked table has a trigger writing to `changes` (per-household `seq`) and
  `pg_notify` after commit. Handlers never push to clients themselves.
- **Modules** own their tables, routes and views; the core (households, members, auth, change feed) is generic.
  Every table is scoped by `household_id`.
- **Fitness module** (`measurements`, `fitness_profiles`): any member records weigh-ins for any member, a profile is
  written by its own member only. Body composition is computed on the device and stored at save time; scale access sits
  behind a `ScaleDriver` interface (Android only). Body data is sensitive: delegated (OAuth/MCP) clients get 403 on the
  `fitness.*` views and `/fitness/` routes.
- **Scale layer** (`modules/fitness/scale/`): a `ScaleDriver` only speaks one scale's BLE protocol (variant
  detection, writes, parsing; one reassembly buffer for both Mi scale variants) and emits `readings` plus
  `ScaleSignal`s (`activity`, `historyComplete`). `ScaleSession` owns the lifecycle and never guesses from readings:
  activity resets a silence timer, and it finishes on silence, a disconnect, end-of-history plus a short quiet period,
  or the user's Done. Implausible dates are dropped in this shared layer. The paired scale (remote id, driver id, name)
  is remembered in `DevicePrefs` and reconnected directly (autoConnect, then a scan filtered to its id); the
  per-scale import cursor is kept separately, and a never-seen scale imports all stored records.
- **Logging:** the server's default `slog` logger is built by `internal/logging`: a decorator handler keeps the console
  output and also exports every record as OTLP/HTTP JSON (hand-written, batched, bounded queue) to
  `OIKO_OTLP_LOGS_URL` with basic auth `OIKO_OTLP_USER` / `OIKO_OTLP_PASSWORD`; without the URL it is console only.
  The app's `AppLog` batches records into `{"t":"log"}` messages on the existing WebSocket (ring buffer while
  offline); the hub re-emits them through the same logger (`source=app`, household and member ids, never tokens), with
  per-message limits so one client cannot flood the collector.
- **Accounts vs members:** a user (who signs in) can be a member of several households; a member needn't have an
  account (children). Sign-in is Google OIDC done by the backend. Details: [auth.md](auth.md).
- **External data is mirrored, not proxied:** the calendar lives at providers (Google; CalDAV later). Our writes go to
  the provider first and the result lands in the mirror; reads (app, views, MCP) never call the
  provider. Details: [calendar.md](calendar.md).
- **AI chats (ChatGPT, Claude…)** connect over MCP + OAuth and act as the member who connected them; the MCP tools wrap
  the REST API. Details: [mcp.md](mcp.md).
- **Mentions and the inbox:** markdown text (task/list descriptions, comments) mentions a member as
  `[@Name](member:<id>)`; the app shows the current name and edits it as plain `@Name`. Instead of notices about every
  change, the server writes `todo_inbox` rows in the same transaction as the write: a mention, a reply in a thread the
  member takes part in (assignee, commenter, earlier recipient) or an assignment — never to the actor, and description
  mentions only when newly added. The app shows them in an inbox in the app bar.
- **Files** (uploads) live in the core `files` table — Postgres for now — outside the change feed, with a per-family
  quota (`OIKO_STORAGE_QUOTA_MB`, default 1 GB) and 25 MB per file. Upload is `POST /files` (multipart) before the
  form is saved; a module then references the file from its own tracked table (tasks: `todo_attachments`, id = file
  id, shown in a strip under the description or comment; view `todo.attachments`). Files no module references are
  deleted a day after upload. The app gets content with its bearer token (`GET /files/:id`); browsers open a
  short-lived signed link (`POST /files/:id/link`). Only common image types and PDF are served inline; everything
  else is a download, so an uploaded page never runs on the app's origin. The app scales photos to 2560 px first.
- **Search** is per module: each answers `GET /<module>/search?q=` (server-side, so done tasks and events outside
  the loaded range are found too) and implements `FamilyModule.search` in the app; the search sheet asks every module
  and each hit knows how to open itself (switch screen, select, open the editor).
- **Recurring tasks** (`todo_recurring`): a template holds an RFC 5545 RRULE (no DTSTART/COUNT/UNTIL: `start_date`,
  `end_date` and `create_time` are separate fields), the household-local creation time and a due offset in days. The
  table is the source of truth; [DBOS](https://github.com/dbos-inc/dbos-transact-golang) (`internal/recurring`,
  state in the `dbos` schema of the same Postgres) only decides *when* to wake up: one database-backed schedule per
  active template, a daily 6-field cron (`0 M H * * *`) in the household timezone. A tick calls `todo.Generate(template,
  local date)`, which checks the rule and inserts the task idempotently (unique `(recurring_id, occurrence_date)`), and
  always advances `last_run_date`. At boot the schedules are reconciled with the table and a catch-up creates only the
  latest occurrence missed while the server was down. Schedule edits reach other instances within DBOS's polling interval
  (5 s). Changing a household's timezone must re-apply its schedules (`Reconcile`); there is no such endpoint yet.
- **Completed-task cleanup**: a daily DBOS workflow (03:00 UTC) hard-deletes tasks `OIKO_DONE_RETENTION_DAYS` days
  (default 30, `0` = off) after `done_at`, unless `todo_items.keep_forever` is set. Deletes go through the normal
  change feed.
- **App data access** goes through repository interfaces with `Api*` and `Mock*` implementations; the mock (no server)
  must keep working.

## Deployment

One instance per family (or a few): Postgres + one image (root `Dockerfile`) with the Go binary that also serves the
built web app (`OIKO_WEB_DIR`); `docker compose up -d --build` runs it (`docker-compose.yml`). Development uses
`docker-compose.dev.yml` through `./local-dev`. Releases: a `v*` tag builds the image to `ghcr.io/glothriel/oikoboard`
(`:<version>` and `:latest`) and attaches the Android APK to a GitHub release (`.github/workflows/release.yml`). The app finds its server like this: a release **web** build talks to its own origin (the
web app is served from the same host as the API); **Android** asks for the server address on first start (saved,
changeable on the login screen); `--dart-define=OIKO_API=<url|mock>` overrides both. Config is `OIKO_*` env vars,
listed in `server/cmd/oikoboard/main.go`.
