# Clean up completed tasks after X days

Source: issue #49.

## Goal
Completed tasks no longer pile up: the server deletes a task a configurable number of days after it was completed, unless the task is marked "never delete". Household members set and clear that flag on a task in the app.

## Requirements
- R1: A task with `done = true` and `done_at` older than X days is deleted by the server, together with its comments, attachments and inbox entries (existing cascades), and the deletion reaches clients through the normal change feed.
- R2: X comes from the env var `OIKO_DONE_RETENTION_DAYS` (default 30); `0` disables cleanup.
- R3: Open tasks (`done = false`) are never deleted, however old.
- R4: A task with `keep_forever = true` is never deleted, even when completed long ago. The column defaults to `false`.
- R5: `keep_forever` is returned in the task JSON, accepted on `POST /todo/items` and `PATCH /todo/items/:id` (set and clear, null is rejected).
- R6: Cleanup runs at boot and then hourly, and never fails the server (errors are logged).
- R7: The task editor in the app has a "Keep forever" switch that sets and clears the flag, on new and existing tasks; the mock repository supports it too. Texts exist in English and Polish.
- R8: Reopening a completed task clears `done_at` (existing behaviour), so it restarts its retention clock when completed again.

## Out of scope
- Per-household or per-list retention settings, or a settings UI for X.
- Soft delete, trash or undo.
- Cleaning up other entities (comments, inbox, recurring templates).
- Recurring templates carrying a keep-forever flag to their generated tasks.

## Decisions and why
- X is a server-wide env var, not a household setting: the issue only says "configurable", env vars are how the server is configured today, and it needs no schema or UI. A per-household setting can be added later.
- Default 30 days, `0` = off: the issue asks for cleanup, so it is on by default; the value is a guess the human may overrule. Done tasks with `done_at IS NULL` are left alone (nothing to measure from).
- Hard delete of the rows, in one DELETE inside `core.Write` with an empty actor: the `oiko_track` triggers on `todo_items` then emit delete changes, so clients drop the tasks without any ad-hoc push. Cascades already remove comments/attachments/inbox entries.
- Cleanup goes in `App.Run`'s hourly loop (next to the other cleanups), not DBOS: a single idempotent DELETE needs no durable schedule. It must call `Calendar.TodosChanged` for affected households because the due-tasks calendar shows tasks.
- Flag is a plain `keep_forever boolean NOT NULL DEFAULT false` column on `todo_items`, typed like the other fields.
