# Code review rules

Applied by `om-code-review` in addition to its built-in checklist. Conventions come from `AGENTS.md`.

## All changes
- Everything in the repo is in English: code, comments, logs, errors, docs, commit messages. New Polish text is a finding.
- Docs stay minimal: no changelogs, status sections or implementation detail. Behaviour covered by a doc must update that doc in the same change.
- Plans and to-dos belong in GitHub issues, not files.

## Server (Go)
- Every module table has `household_id`, and every query is scoped by it. A read or write that can cross households is a blocker.
- Schema changes are a new numbered goose migration with a working down; editing an applied migration is a blocker.
- Module tables use typed columns, not JSONB blobs. Only the change feed is generic.
- Realtime: writes go through REST; clients get changes through DB triggers → `changes` → NOTIFY → WebSocket views. A new entity type needs its trigger and view; ad-hoc pushes from handlers are a finding.
- Auth: check token scope, OAuth redirect/URI handling and the MCP surface for bypasses; secrets never appear in logs or responses.
- New behaviour has tests in `server/internal/app` (`go test -race`); `gofmt` and `go vet` clean.
- New `OIKO_*` env vars are listed in `server/cmd/oikoboard/main.go`.

## App (Flutter)
- UI text only via `context.l10n.<key>`; English in `app_en.arb`, Polish in `app_pl.arb`, ICU placeholders/plurals, never concatenated fragments. Hard-coded strings are a finding.
- Data goes through repository interfaces with both `Mock*` and `Api*` implementations; a feature that breaks the mock is a finding.
- New modules are registered in `modules/registry.dart`; shared code lives in `core/`.
- `dart format` and `flutter analyze` clean; new logic has tests.

## Dev tooling and config
- `local-dev` stays stdlib-only Python; new tasks are functions in `COMMANDS`.
- Dev-only settings stay out of `docker-compose.yml` and `Dockerfile`.
- `server/.env` is never printed or committed.
