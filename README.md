# Oikoboard

A small, family-sized FamilyWall clone — a shared household "board": todo lists, a calendar, and over
time more modules (weight, meal calories, shopping, etc.). Everything syncs live between family
members' devices.

> **Status:** MVP of both the Flutter app (web + Android from one codebase) and the Go backend is in
> place. The app can still run without a server on an in-memory repository hidden behind the same
> interface the API client uses (`--dart-define=OIKO_API=mock`).

---

## Goals

- **Realtime** — a change made on a phone shows up in the browser within a second, without a refresh.
- **One codebase** for web and Android (Flutter compiles to both; logic is 100% shared, only the
  layout may differ — phone vs. wide screen).
- **Generic / modular** — adding a new "view" (e.g. weight tracking) means adding a module,
  not reworking the app core.
- **Simplicity** — this is a family project, not a SaaS. One household (maybe a few), a handful of users.

## Scope

### MVP
| Module       | Features |
|--------------|----------|
| **Todo**     | multiple lists, items (text, check off, optional assignee and due date), ordering, deletion |
| **Calendar** | events (title, start/end, all-day, participants, color), month / week / agenda view |
| **Core**     | household, members, login, realtime sync, navigation between modules |

### Later (examples)
- Weight tracking (entries per person, chart)
- Calories / meals (log, daily totals)
- Shopping list (essentially a todo variant)
- Recurring events (RRULE), ICS import/export, reminders / push notifications
- Offline mode with a write queue

---

## Architecture (overview)

```
┌───────────────────────────┐        HTTPS (REST/JSON)        ┌──────────────────────────┐
│  Flutter app              │ ──────────────────────────────▶ │  Go server               │
│  (web + Android)          │                                 │                          │
│                           │ ◀────── WebSocket: changes ──── │  ┌────────────────────┐  │
│  modules: todo, calendar… │                                 │  │ modules: todo, cal…│  │
└───────────────────────────┘                                 │  └─────────┬──────────┘  │
                                                              │            │ LISTEN/NOTIFY│
                                                              └────────────┼─────────────┘
                                                                           ▼
                                                                  ┌──────────────────┐
                                                                  │   PostgreSQL     │
                                                                  └──────────────────┘
```

### Realtime — how it works

> Detailed design: [docs/backend-realtime.md](docs/backend-realtime.md). Below is a summary of the original idea.

1. Writes go through plain REST (`POST/PATCH/DELETE`), queued on the device (outbox) so they work offline
   and show up at once.
2. Every change in the database gets an increasing number in the `changes` table
   (`seq`, `household_id`, `module`, `entity_type`, `entity_id`, `op`, `payload`).
3. After commit the server does `pg_notify` → every server instance gets notified
   and pushes the change over WebSocket to clients of that household.
4. The client remembers the last `seq` it saw. After a reconnect it re-subscribes and gets a fresh
   snapshot (resuming from `since: <seq>` is a planned optimisation) — nothing is lost on a dropped connection.
5. Conflicts: **last-write-wins** per entity (with a `version` field) to start with — enough for a family app.

This mechanism is shared by all modules — a module only declares its entity types.

### Modularity
Each module (on both sides) is a separate package with a well-defined contract.

**Flutter** — a module implements something like:
```dart
abstract class FamilyModule {
  String get id;                    // "todo", "calendar", "weight"
  String get title;
  IconData get icon;
  List<RouteBase> get routes;       // its own screens
  Widget? dashboardTile(BuildContext c); // tile on the "wall" (optional)
  void handleChange(Change change); // reacts to a change from the WebSocket
}
```
Modules are registered in one place (`modules/registry.dart`); the menu, routing and change
dispatch are built from that list automatically.

**Go** — a module registers its HTTP handlers, SQL migrations and the entity types published to the change feed:
```go
type Module interface {
    ID() string
    Routes(r *gin.RouterGroup)
    Views() []View  // see docs/backend-realtime.md
}
```

Each module has **its own tables** (typed, with normal columns) — we don't pack everything into a
single JSONB table. Only the change feed and the infrastructure around it are generic.

---

## Stack

### App (Flutter) — `app/`
- **Flutter / Dart** — one codebase → `flutter build web` and `flutter build apk`
- **Riverpod** — state and dependency injection
- **go_router** — routing (works with browser URLs too)
- **http** + **web_socket_channel** — talking to the server (both work on web and Android)
- **json_serializable / freezed** — data models
- **table_calendar** (or a custom view) — calendar

App layers:
```
ui (widgets)  →  controllers/providers (Riverpod)  →  repository (interface)
                                                      ├── Mock*Repository      ← phase 1 (MockStore)
                                                      └── Api*Repository       ← phase 2 (REST + WS)
```
This let us write the UI first and plug the backend in later without rewriting screens.

### Backend (Go) — `server/`
- Go 1.26, **Gin** (HTTP) + **GORM** (ORM)
- **pgx** — Postgres driver (also handles `LISTEN/NOTIFY`)
- **goose** — SQL migrations (tables, triggers writing to `changes`)
- **coder/websocket** — WebSockets
- Auth: Google sign-in (OIDC) and session tokens; household invites by link — [docs/auth.md](docs/auth.md)

### Database — PostgreSQL 17, locally via `docker compose`

---

## Repository layout

```
oikoboard/
├── app/                 # Flutter (web + Android)
│   └── lib/
│       ├── core/        # sync, api, auth, routing, shared widgets
│       └── modules/
│           ├── todo/
│           └── calendar/
├── server/              # Go
│   ├── cmd/oikoboard/
│   ├── migrations/      # goose SQL migrations (embedded)
│   └── internal/
│       ├── app/         # wiring + integration tests
│       ├── core/        # http, auth, households, db
│       ├── realtime/    # LISTEN, websocket hub, view dispatch
│       ├── seed/
│       └── modules/
│           ├── todo/
│           └── calendar/
├── docs/                # design docs
├── Dockerfile           # production image: Go binary + built web app
├── docker-compose.yml   # production: postgres + the image
├── docker-compose.dev.yml # dev: postgres + `go run` with auto-reload (./local-dev)
├── local-dev            # dev task runner (Python stdlib)
├── AGENTS.md            # rules for AI agents / contributors
└── README.md
```

---

## Roadmap

1. **Phase 1 — Flutter, no backend**
   - [x] Flutter project with web + Android targets
   - [x] Skeleton: navigation, module registry, responsive layout (phone / desktop)
   - [x] Backend mock (`MockStore`: in-memory data + a change stream like the WebSocket one)
   - [x] Todo module (lists, check off, assignee, due date, swipe = delete)
   - [x] Calendar module (month + day agenda, adding/editing events)
   - [x] Family simulator (⚡ in the app bar) — others "click" every 4 s, changes arrive live
   - [ ] Run on an Android emulator / phone
2. **Phase 2 — Backend**
   - [x] Go server (Gin + GORM) + Postgres in docker compose, migrations (goose)
   - [x] Multiple households (everything scoped by `household_id`, composite FKs), seed of one sample family
   - [x] Google sign-in (OIDC), creating a household, invite links — [docs/auth.md](docs/auth.md)
   - [x] REST for todo and calendar
   - [x] Change log (trigger → `changes` → NOTIFY) + WebSocket with views (snapshot + stream)
   - [x] `Api*Repository` + `SyncClient` in the app (reconnect = fresh snapshots)
   - [x] Optimistic UI, offline write queue (outbox) with a dead letter for rejected changes
   - [ ] Resume from `since`
3. **Phase 3 — More modules** (weight, meals, shopping…), notifications, offline

---

## Environment (Linux)

SDKs live in `~/sdks`:

| What           | Path                        |
|----------------|-----------------------------|
| Flutter 3.50   | `~/sdks/flutter`            |
| Android SDK    | `~/sdks/android`            |
| Android Studio | `~/sdks/android-studio`     |

In `~/.bashrc`:
```bash
export ANDROID_HOME="$HOME/sdks/android"
export PATH="$HOME/sdks/flutter/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

First run:
```bash
flutter config --android-sdk "$ANDROID_HOME"
flutter doctor                      # shows what's missing
flutter doctor --android-licenses   # accept the licenses
```

Also needed: Docker with Compose v2.32+ (for `watch` with `action: restart`) and Python 3 for `./local-dev`.

### Running

1. Database and server (API on `:8090`, Postgres on `:5433`):
   ```bash
   ./local-dev            # same as ./local-dev start
   ```
   This runs `docker compose -f docker-compose.dev.yml up --watch`: Postgres plus the server via
   `go run ./cmd/oikoboard` (migrations + seed when the DB is empty + server). `./server` is bind-mounted, and any change
   there restarts the server (a fresh `go run`). The container runs as your user and shares your Go
   module/build caches (`go env GOMODCACHE GOCACHE`), so rebuilds are fast and no root-owned files appear.
   `./local-dev --help` lists the available commands.

   Config lives in `server/.env` (not in git): `OIKO_GOOGLE_CLIENT_ID`, `OIKO_GOOGLE_CLIENT_SECRET`,
   optionally `OIKO_DEV_LOGIN=1` (login with just an e-mail, local only). Details and Google Cloud
   setup: [docs/auth.md](docs/auth.md). The full list of variables is in `server/cmd/oikoboard/main.go`.

   Without Docker for the server:
   ```bash
   docker compose -f docker-compose.dev.yml up -d postgres
   cd server && OIKO_SEED=1 go run ./cmd/oikoboard
   ```
   `go run ./cmd/oikoboard seed` adds another sample family,
   `go run ./cmd/oikoboard link-email "Our family" Dad someone@gmail.com` links an e-mail to a member.

   The production setup (built image, web app on `/`, no seed) runs with plain `docker compose up --build`,
   or `./local-dev prod`.

2. App (runs on the host, not in Docker):
   ```bash
   ./local-dev app                      # Chrome on :5555, talks to localhost:8090
   ./local-dev app --mock               # no server, in-memory data (+ ⚡ simulator)
   ./local-dev app -d emulator-5554     # Android; sets up `adb reverse tcp:8090` for you
                                        # (first start asks for the server — localhost:8090 is prefilled)
   ./local-dev app -- --release         # anything after `--` goes to `flutter run`
   ```
   Before launching it checks that `flutter`, Chrome / the Android device (`adb`) and the API
   (`/api/v1/health`) are available, and runs `flutter pub get` if `pubspec.*` changed
   (`--skip-checks` skips the checks). Or by hand:
   ```bash
   cd app
   flutter run -d chrome --web-port 5555              # web, talks to localhost:8090
   flutter run -d chrome --dart-define=OIKO_API=mock  # no server, in-memory data (+ ⚡ simulator)
   flutter emulators --launch <name>                  # Android:
   adb reverse tcp:8090 tcp:8090                      #   localhost in the emulator = your machine
   flutter run -d emulator-5554
   ```
   While `flutter run` is running: `r` = hot reload, `R` = hot restart.

**Manual realtime test:** server with `OIKO_DEV_LOGIN=1`, two browsers (or an incognito window), Google
sign-in in one, a dev-mode e-mail in the other joining via an invite link — changes made in one appear
in the other (with a notification saying who made them).

### Tests
```bash
cd server && go test -race ./...          # integration: Postgres from docker compose, each test on its own DB
cd app && flutter test                    # test/live_server_test.dart: needs a server with OIKO_DEV_LOGIN=1
```

---

## Cheat sheet for people new to Flutter

- **Everything is a widget** — a screen, a button, padding, layout. UI is a widget tree built in `build()`.
- `StatelessWidget` — only displays data; state lives in Riverpod providers, not in widgets.
- Web and Android are **the same Dart code**; platform differences are rare (e.g. file access, notifications).
- Android Studio is mostly needed for the emulator and SDK; you can write code in VS Code with the Flutter extension.
