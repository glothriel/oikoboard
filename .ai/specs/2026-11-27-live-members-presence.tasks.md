# Tasks

## [x] T1: Server: `members` in the change feed with a `family.members` view
**Goal:** Member changes reach all household devices through a sanitized `family.members` view.
**Acceptance criteria:**
- R1, R2, R3: a websocket on `family.members` gets a snapshot, then upserts for insert/update and a remove for delete, only for its own household.
- Rows contain `has_account` and `picture` and never `user_id`/`invite_email`.
- Changing `users.picture` produces a members change; `/me` still returns members with `picture`.
**Changes:**
- `server/migrations/00021_members_live.sql` — add `members.picture`, backfill from `users`, triggers keeping it synced (members user_id, users picture); `oiko_track('members')`; Down.
- `server/internal/core/view.go` — add optional `RowProjector` interface (`Project(entity string, row json.RawMessage) json.RawMessage`).
- `server/internal/realtime/dispatcher.go` — in `emit`, run the row through `RowProjector` when the view implements it, for both upsert and remove rows.
- `server/internal/core/members.go` — `Members` module, same shape as `todo.Module` (`Name`, empty `Routes`, `Views`), in core as it is cross-cutting; `family.members` view (no params), Matches `members`.
- `server/internal/core/members.go` — Snapshot selects only public columns plus `has_account`, so it needs no projection; `Project` applies to live changes only (strips `user_id`/`invite_email`, derives `has_account`).
- `server/internal/app/app.go` — register the module in `Modules()`.
- `server/internal/core/auth.go` — `/me` members query reads `m.picture` instead of joining `users`; `memberOut` unchanged in shape.
- `server/internal/app/members_test.go` — websocket test: snapshot, insert via invite accept, rename via SQL, delete, second household sees nothing, no leaked fields, picture change propagates.

## [x] T2: Server: online presence
**Goal:** Connected household devices learn which members are online, live.
**Acceptance criteria:**
- R6, R7: presence message after `ready` and on each change; two connections of one account count once; offline only after a 5 s grace; accountless members never listed.
**Changes:**
- `server/internal/realtime/presence.go` — `Hub`-owned tracker: per household member → connection count, `add`/`remove`, offline grace (`presenceGrace` 5 s, test-overridable), broadcasts `presenceMsg`.
- `server/internal/realtime/hub.go` — create the tracker in `NewHub`.
- `server/internal/realtime/conn.go` — after `ready`, register the conn and send the current set; deregister in the deferred cleanup.
- `server/internal/app/presence_test.go` — two accounts in one household: A connects → B sees A online; A reconnects within grace → no offline broadcast; A leaves → offline after the (shortened) grace; other household unaffected.
- `docs/backend-realtime.md` — add the `family.members` view row and the `presence` message to the protocol; one line on the single-instance limit.

## [x] T3: App: family follows `family.members`; removed-member placeholder
**Goal:** Members added/edited/removed show up in the running app and dangling member ids never crash.
**Acceptance criteria:**
- R4: in API mode `familyProvider` reflects `family.members` upserts/removes; before the first snapshot it uses the session's members.
- R5: assignee, comment author, inbox actor and day-sheet assignee for an unknown id show the placeholder, no `!` crash.
**Changes:**
- Mockup: `centurion-mockups/issue-1` — reuse `Member.removed`/`byIdOrRemoved` in `core/family.dart`, the placeholder avatar, and the `todo_screen.dart`/`todo_module.dart` call sites; the `memberRemoved` l10n key.
- `app/lib/core/family.dart` — `membersProvider` (API: `syncClientProvider.watch('family.members')`; mock: session members), `familyProvider` derives from it; neutral `Member.removed` placeholder.
- `app/lib/core/family.dart` — `familyOf(context)` reads the live `familyProvider` and its doc comment is corrected; its callers (`calendar_screen.dart`, `markdown.dart`, `mentions.dart`) rebuild on family changes.
- `app/lib/modules/calendar/calendar_screen.dart`, `core/markdown.dart`, `core/mentions.dart` — unknown ids use `byIdOrRemoved`/the `memberRemoved` label instead of null.
- `app/lib/modules/todo/todo_screen.dart`, `modules/calendar/todo_day_sheet.dart`, `modules/todo/inbox.dart` — replace `family.byId(...)!` and null-hiding spots with the placeholder avatar/label.
- `app/lib/l10n/app_en.arb`, `app_pl.arb` — `memberRemoved` ("Removed member" / "Usunięty członek").
- `app/test/family_live_mock_test.dart` — widget test on the mock backend: a provider override feeding a new member makes it appear in the assignee picker; an unknown assignee id renders the placeholder without exceptions.
- `app/test/sync_client_test.dart` — a `family.members` snapshot then upsert/remove updates the watched state (existing fake-socket pattern).

## [x] T4: App: online dot on `MemberAvatar`
**Goal:** Online members show a green dot on their avatar everywhere, live.
**Acceptance criteria:**
- R8: members in the online set show the dot; others and accountless members do not; it updates on a `presence` message; mock mode shows a seeded online member.
**Changes:**
- Mockup: `centurion-mockups/issue-1` — reuse the `MemberAvatar` online dot (size, green, surface border, Semantics label) in `core/family.dart` and the `memberOnline` l10n key; the provider there is a fixed stub.
- `app/lib/core/api/sync_client.dart` — handle `presence` messages (before the `sub` lookup), keep `Set<String> online`, expose `Stream<Set<String>> get presence`; clear it on disconnect.
- `app/lib/core/family.dart` — `onlineMembersProvider` (API: `SyncClient.presence`; mock: `MockStore`); `MemberAvatar` becomes a `ConsumerWidget` with a small green dot and semantic label.
- `app/lib/core/mock/mock_store.dart`, `app/lib/core/mock/simulator.dart` — mock presence set (me + one seeded member) as a stream; the simulator toggles a random other member's presence on each tick.
- `app/lib/l10n/app_en.arb`, `app_pl.arb` — `memberOnline` ("Online" / "Online").
- `app/test/presence_mock_test.dart` — avatar of an online member shows the dot, an offline one does not, toggling in the mock store updates it.
- `app/test/sync_client_test.dart` — `presence` message updates `online` and the stream; unknown message types are still ignored.
