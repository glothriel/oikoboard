# Live family members and online presence

Source: issue #1.

## Goal
Every signed-in device of a household sees members added, edited or removed (and gaining an account or picture) live, without a reload, and sees which members are online right now.

## Requirements
- R1: A change to a `members` row (insert, update, delete) reaches every connected device of that household through a new `family.members` view (snapshot + upserts/removes), and not other households.
- R2: Member rows sent to clients carry `id`, `household_id`, `name`, `color`, `created_at`, `has_account` (user_id set) and `picture`; never `user_id` or `invite_email`, in snapshots and in live changes alike.
- R3: A member's `picture` follows the account's picture: a login that changes `users.picture` produces a live `members` change for each family the account belongs to.
- R4: The app's family (`familyProvider`) follows the `family.members` view in API mode: a new member is selectable in pickers, assignee chips and avatars without re-login; a removed one disappears.
- R5: The app never crashes on an id with no member (removed member): assignee, comment author and mention lookups show a neutral placeholder ("removed member" label, neutral avatar) instead. This covers stale or in-flight data only: the server unassigns a removed member's tasks (FK `SET NULL`), so server data never produces it.
- R6: The server tracks online members per household: a member is online while at least one WebSocket of their account is connected, and goes offline 5 s after the last one closes (reconnect blips do not flicker).
- R7: Every connection of a household receives a `{"t":"presence","online":[member ids]}` message after `ready` and on each change of the set; members without an account are never in it.
- R8: `MemberAvatar` shows a small green dot for members in the online set, wherever it is used; mock mode shows presence too (seeded, toggled by the family simulator).

## UI
- `MemberAvatar` (shared widget; seen in the member picker/list, task rows, calendar chips, shell drawer, wall): optional online dot.
- Removed-member placeholder in task row assignee, task comments, inbox and calendar day sheet.
- Prototype: branch `centurion-mockups/issue-1` (never merged).

## Backward compatibility
Additive. Migration `00021` adds a nullable-safe `members.picture` column (backfilled) and a new tracked entity; older apps ignore the `family.members` view and the unknown `presence` message (the sync client drops messages for unknown subs/types). `/me` keeps its shape (`picture` is still returned).

## Out of scope
- Member management endpoints (rename, recolor, remove): none exist today; this change only makes whatever writes `members` (invite accept, SQL, a future endpoint) live.
- Offline/push notifications, "last seen", presence opt-out, presence across several server instances.
- Changing how members are created or invited.

## Decisions and why
- `members` goes into the change feed with `oiko_track('members')` (author's hint). The raw row holds `user_id` and `invite_email`, so views may implement an optional `core.RowProjector`; the dispatcher applies it to every row it sends. Rejected: a separate public table (duplicate data).
- `picture` is denormalized into `members.picture`, kept in sync by triggers (BEFORE INSERT/UPDATE OF user_id on members, AFTER UPDATE OF picture on users). Without it a live row cannot carry the picture, and joining `users` in `Matches` is impossible.
- Presence is in-memory in the realtime `Hub` and pushed as its own message, not as a table or change: it is ephemeral and must not hit `changes`/retention. Single server instance assumed (as deployed by `docker-compose.yml`); documented as a limit.
- Presence is not a view subscription: every household connection gets it automatically, so no screen has to subscribe and the dot works everywhere.
- Online = account connected, so several devices of one person are one online member; the 5 s grace matches the client's reconnect behaviour.
- Removed member: no removal endpoint exists and the FK `ON DELETE SET NULL (assignee_id)` unassigns tasks, so tasks cannot stay assigned (the intent's accepted proposal). The FK stays as is; the app still tolerates dangling ids (R5), since cached or in-flight data can reference a just-removed member. Overrule on the plan PR if tasks must keep a ghost assignee.
- Mock mode keeps the static mock family (no member writes exist to simulate); only presence is mocked.
