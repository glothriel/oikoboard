# Execution plan: recurring tasks (#27)

Source doc: .ai/specs/2026-11-23-recurring-tasks.md
Refs: #27, spec PR #37

## Goal
Implement the spec: recurring task templates (RRULE), DBOS-scheduled generation, drawer UI.

## Scope
Phase 1 server (`server/`), Phase 2 app (`app/`). Disjoint scopes; the API contract in the spec is the interface.

## Non-goals
Repeat-after-completion, per-occurrence series editing, notifications.

## Implementation Plan
Phase 1 steps 1-7 and Phase 2 steps 1-5 exactly as in the spec's Implementation Plan.

## Progress
- [x] 1.1 DBOS spike + Scheduler interface
- [x] 1.2 Migration 00017
- [x] 1.3 Model + validation
- [x] 1.4 generate + timezone helper
- [x] 1.5 REST + view + preview
- [x] 1.6 DBOSScheduler wiring, reconcile, catch-up
- [x] 1.7 Docs
- [x] 2.1 App models + repositories (Mock + Api)
- [x] 2.2 RRULE builder/summary
- [x] 2.3 Drawer UI + l10n
- [x] 2.4 List-view button + widget tests
- [x] 2.5 Archive Delta
