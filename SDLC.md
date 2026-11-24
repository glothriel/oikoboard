# Software delivery process

New PRs target `master`; issues and PRs live in GitHub (tracker operations are defined in `.ai/trackers/github.md`). The agent skills configured in `.ai/agentic.config.json` enforce this process; this file is the human-readable version. Change both together, and re-run `om-setup-agent-pipeline` when the toolchain or labels change.

## Ticket lifecycle

| Stage | What happens | Driven by |
|---|---|---|
| Discovery | An idea is talked through; ends in a routing decision and optionally a brief in `.ai/specs/briefs/` | `om-brainstorm` |
| Intake | A GitHub issue with what is wanted, for whom, and what done looks like | `om-prepare-issue` or a human |
| Triage | Confirm a bug is real and unfixed on `master`, not claimed, not covered by an open PR | `om-verify-in-repo` |
| Claim | The author claims the issue (see below) | `om-fix`, `om-auto-create-pr` |
| Spec | A feature gets a spec in `.ai/specs/` on a design-only PR before it is built | `om-auto-write-spec`, `om-spec-writing` |
| Implement | Minimal change plus tests, validation gate green | `om-root-cause` + `om-fix`, `om-auto-implement-spec`, `om-auto-create-pr` |
| PR | Ready PR against `master` with normalized labels | `om-open-pr` |
| Review loop | Review against `CODE_REVIEW.md`; fixes until approved | `om-auto-review-pr`, `om-review-prs` |
| Merge | Squash-merge once approved and checks are green | `om-merge-buddy` + `om-approve-merge-pr`, or a human |

`om-auto-fix-issue <id>` runs the chain end to end (bug: verify, root cause, fix, PR, review; feature: spec, implement, review). Deployment is outside this document.

## Labels

Pipeline labels are mutually exclusive; a PR carries at most one: `review` → (`changes-requested` ↔ `review`) → `merge-queue`; `blocked` and `do-not-merge` are set by humans and stop the flow.

| Group | Labels | Exclusivity |
|---|---|---|
| Pipeline | `review`, `changes-requested`, `qa`, `qa-failed`, `merge-queue`, `blocked`, `do-not-merge` | one at a time |
| Category | `bug`, `feature`, `refactor`, `security`, `dependencies`, `documentation` | additive |
| Meta | `needs-qa`, `skip-qa`, `qa-approved`, `qa-self-verified`, `in-progress`, `ci-monitoring`, `claim-reset` | additive |

Existing size/area labels (`easy`/`medium`/`hard`, `backend`/`frontend`) are kept as they are. `do-not-close` is human-only and protects an issue from automated closure. Priority and risk labels and the automerge queue are not enabled.

QA gate: off. `needs-qa`/`qa-approved` exist as advisory labels only and do not block merging.

## Claim protocol

Before mutating an issue or PR, an agent reads its lock, assignees and `in-progress` label. A claim is an atomic lock ref (`refs/om-locks/...`) plus an `in-progress` label and a claim comment, released when the work finishes, on success and failure alike. `in-progress` means actively working; `ci-monitoring` means the work is reported and only a CI-result follow-up is owed, and blocks nobody. To recover a stalled runner: stop it, then add the human-only `claim-reset` label; removing `in-progress` alone does not clear the lock.

Agents report (labels, review, comments) as soon as their work is done, without waiting for CI; CI wait is bounded by `ci.maxWaitMinutes` (40).

## Validation gate

Run in order; any non-zero exit blocks the PR. Each command runs only when its area changed against `origin/master`:

- Go (`server/`): `gofmt -l`, `go vet ./...`, `go test -race ./...` (needs Postgres from `docker-compose.dev.yml`)
- Flutter (`app/`): `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`

The exact commands live in `.ai/agentic.config.json`.

## Per-skill deviations

Repo-specific rules for a skill go in `.ai/skills/<skill-name>/SKILL.md`, which takes precedence over the installed skill but cannot relax its safety rules.
