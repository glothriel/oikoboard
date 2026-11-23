# Recurring tasks (#27): RRULE templates created by per-template DBOS schedules

- Date: 2026-11-23
- Category: feature
- Priority signal: medium — owner-requested feature, no incident
- Risk signal: medium — new dependency (DBOS) and a scheduler touching task creation
- Routing: Next: om-auto-write-spec "Recurring tasks (#27): RRULE templates, DBOS per-template schedules, relative due — brief: .ai/specs/briefs/2026-11-23-recurring-tasks.md"

## Problem

Households have chores and obligations that repeat on a calendar (monthly "close the company books"; Mon+Fri "do groceries" due 2 days after it is added). Today every instance must be created by hand. Issue #27 asks for recurring tasks and names DBOS (dbos-transact-golang) for workflow execution and scheduling.

## Agreed direction

- Fixed-calendar recurrence only. A new task is created on each occurrence regardless of whether earlier ones are done.
- Schedule is an RFC 5545 RRULE, stored as a string on a typed template table in the todo module (household_id, target list, title, description, assignee, rrule, creation time of day, due offset, active). UI presets and a custom editor generate the RRULE: daily, weekly with weekdays, monthly by day or last day, yearly, every N. The editor shows a preview of the next occurrences. Reuse the existing rrule-go dependency and the calendar module's expander.
- Relative due date: offset in days from the creation date (0 = same day), optional due_time; "next given weekday" is a candidate extra. Creation moment and due date are independent.
- Scheduler: one DBOS database-backed schedule per template, created, updated and deleted dynamically with dbos.CreateSchedule after Launch. The schedule is a daily cron at the template's creation time in the household timezone. The workflow checks whether today matches the RRULE and creates the task. Idempotency: unique (template_id, occurrence_date) with ON CONFLICT DO NOTHING. Catch-up after downtime: create only the latest missed occurrence. Compute in the household timezone, DST-safe.
- Fallback if DBOS dynamic schedules prove unsuitable: a once-a-minute tick selecting templates by next_run_at. Verify in the spec phase whether DBOS schedules support a timezone, and what DBOS adds as a dependency (its own schema in Postgres).
- Frontend: a button next to the edit icon in the list view opens a drawer to create/edit/pause the template; also a way to list existing recurring templates.
- Phasing: (1) table, migration, change-feed trigger, scheduler, API; (2) Flutter UI. Only phase 1 depends on the DBOS decision.
- Rejected: "repeat after completion" (owner: not wanted); build nothing (the problem is real, no cheaper way to get calendar recurrence).

## Resolved unknowns

| Question | Answer (from the conversation) |
|----------|--------------------------------|
| Fixed calendar or after completion? | Fixed calendar only; after completion explicitly not wanted |
| Schedule format | RRULE, stored as string; UI generates it |
| Relative due date | Offset in days from the creation date (example: Mon+Fri task due 2 days later) |
| Scheduler | DBOS, with dynamic reconfiguration; a per-minute tick is an acceptable fallback |
| Can DBOS add schedules at runtime? | Yes per its README (CreateSchedule after Launch); timezone support still to verify |
| Where is the UI entry? | Button next to the edit icon in the list view, opening a drawer |

## Non-goals

- Repeat-after-completion mode.
- Editing a single generated occurrence as part of the series; notifications; skipping logic for open previous instances.

## Affected areas (if known)

- server/internal/modules/todo, server/migrations, server/internal/modules/calendar (expander reuse), server/cmd/oikoboard (DBOS setup and config).
- app/lib/modules/todo (list view button, drawer), app/lib/l10n (en + pl), Mock* and Api* repositories.
