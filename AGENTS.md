# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository. See [README.md](README.md)
for what the project is, its architecture and how to run it; design docs are in [docs/](docs/).

## Language

- **Everything in the repository is in English**: code, identifiers, comments, log and error
  messages, commit messages, README and docs.
- Conversation with the maintainer may be in Polish — answer in the language you're spoken to,
  but whatever you write into files is English.
- Some older files still have Polish comments/docs/log messages. When you touch such code,
  translate the parts you change (or the whole file if it's small); don't add new Polish text.
- User-facing app strings live only in `app/lib/l10n/*.arb`: English in `app_en.arb` is the source, and every
  key also gets a Polish translation in `app_pl.arb`. Never hard-code UI text in Dart — use `context.l10n.<key>`.
  Interpolation uses ARB placeholders and counts use ICU plurals; never concatenate translated fragments.

## Layout

- `app/` — Flutter (web + Android). Modules in `app/lib/modules/`, registered in `modules/registry.dart`;
  shared infrastructure in `app/lib/core/`.
- `server/` — Go 1.26 (Gin + GORM + pgx, goose migrations in `server/migrations/`, embedded).
  Entry point `server/cmd/oikoboard/main.go` (also lists all `OIKO_*` env vars).
- `docs/` — design docs: `architecture.md` (start here), `backend-realtime.md`, `auth.md`, `calendar.md`.
- Plans, to-dos and the backlog are GitHub issues (`gh issue list`), not files.
- `local-dev` — the dev task runner (Python, **stdlib only**, no dependencies). New dev tasks go here
  as functions in `COMMANDS`; `start` is the default.

## Documentation

- Keep docs **minimal**. Document only what matters about the project: architecture, key design decisions and why,
  contracts between parts (protocols, data mappings), and operational essentials (config, deployment).
- Don't document individual changes, implementation details visible in the code, or anything that isn't
  architecturally or operationally significant. No changelogs or "status" sections — that's what git is for.
- When behaviour covered by a doc changes, update the doc in the same change (prefer editing or deleting over adding).
  Plans and to-dos go to GitHub issues, not `docs/`.

## Dev workflow

- `./local-dev` (= `start`) runs Postgres + the server from `docker-compose.dev.yml` with `up --watch`; the server is
  `go run` and restarts on any change under `server/`. API on `:8090`, Postgres on `:5433`.
- `docker-compose.yml` + `Dockerfile` are production (built binary + web app); `./local-dev prod` runs them locally.
  Keep dev-only settings out of them.
- `./local-dev app [--mock] [-d DEVICE]` runs the Flutter app on the host after pre-flight checks
  (flutter, Chrome/adb, API health, `pub get`).
- Server config: `server/.env` (gitignored, contains secrets — never print or commit it).
- Tests: `cd server && go test -race ./...` (needs Postgres from compose), `cd app && flutter test`.
- Before finishing: `gofmt`/`go vet` for Go, `dart format` + `flutter analyze` for Dart.

## Conventions

- Modules own their tables (typed columns, not a generic JSONB blob); only the change feed is generic.
  Every module table is scoped by `household_id`.
- Schema changes = a new numbered goose migration; never edit an applied one.
- Realtime: writes go through REST, changes reach clients via DB triggers → `changes` → NOTIFY →
  WebSocket views. A new entity type needs its trigger and view, not ad-hoc pushes from handlers.
- The Flutter app talks to data through repository interfaces with both `Mock*` and `Api*`
  implementations — keep the mock working when adding features.
