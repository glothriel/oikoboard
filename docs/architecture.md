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
