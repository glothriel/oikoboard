# cezar EM workflows: gate scripts

Helper scripts for two cezar workflows. Not used by the app or by CI. The flow is fixed by the
workflow graphs; agents only fill in the steps (plan, develop, review, give a verdict). Humans act only
on GitHub: a label on an issue, and PR reviews.

Branches of issue `<n>`:

```
main branch
 └─ feature/issue-<n>                   created by em-plan
     ├─ em/issue-<n>-plan    PR -> feature   stage:plan, human review; merged by the workflow on approve
     ├─ em/issue-<n>-t1      PR -> feature   developer/reviewer talk; merged by the workflow on approve
     ├─ em/issue-<n>-t2 ...
     └─ PR feature/issue-<n> -> main         stage:final, human review; merged by the human
```

| Workflow | Started by | Does |
|---|---|---|
| `.ai/cezar/workflows/em-plan.yaml` | label `agent` on an issue | settles the intent (open questions go to the issue, see below), creates the feature branch, writes a spec + task list, mockups, AI plan review, opens the plan PR as `stage:plan` |
| `.ai/cezar/workflows/em-pr.yaml` | a human review on a `stage:plan` / `stage:final` PR | see below |

`em-plan` starts with the intent (`intent.md`): what the issue wants, scope and assumptions. With
open product questions it posts them with the intent on the issue, drops the `agent` label and stops;
answer in a comment and add the label again (the next run reads the answers). Without questions it
posts the intent for the record and goes on to the spec.

`em-pr` reads the latest review (`review-gate.sh`) and:

- **approve on `stage:plan`**: merges the plan PR into the feature branch, runs the task loop, then
  opens the final PR (`stage:final`).
- **changes/comment on `stage:plan`**: a planner revises the spec and tasks and answers on the PR.
- **changes/comment on `stage:final`**: the review becomes task `R<n>` in the plan and runs through the
  same task loop (own PR into the feature branch); the developer answers each point on the final PR.
- anything else: nothing. Approving the final PR is the human's cue to merge it.

## Task loop

1. `next-task.sh` resets to the tip of the feature branch and picks the first open task (`## [ ] T<n>: <title>`) of the plan this branch adds:
   `.ai/specs/<name>.tasks.md`, next to its spec `.ai/specs/<name>.md` (format: `planner.md`).
2. A developer agent implements it; `verify.sh` runs the validation commands from
   `.ai/agentic.config.json`. Red: the same developer session fixes it. Green: `task-pr.sh` opens the
   task PR into the feature branch.
3. A reviewer agent reviews the task's diff against the spec. `changes`: the findings go to the PR,
   the same developer session fixes or justifies each one, the same reviewer session re-reviews.
   `round-guard.sh` caps the rounds (`CEZ_EM_MAX_ROUNDS`, default 3).
4. `approve`: `mark-done.sh` ticks the task, squashes its commits into one `T<n>: <title>` commit
   and merges the task PR into the feature branch.
5. Out of rounds or fixes: `escalate.sh` pushes what there is, comments and labels `needs-human`.

The plan gets the same treatment in `em-plan`: planner and plan reviewer keep their sessions across
rounds, and `validate-plan.sh` checks the format before any review.

## Repository rules

Generic scripts, repository-specific rules (both live here, so a fork of this directory into another
repository only needs these files changed):

- `rules.md`: rules every agent gets (spec contents, code conventions, screenshots).
- `spec.sections`: sections `validate-plan.sh` requires in a spec.
- `screens.paths`: path prefixes that count as UI; a plan or task touching them needs screenshots.

## Screenshots

`screens.sh` builds the app on the mock backend, serves it and drives headless Chrome with a steps file
written by the agent (`shot.mjs`; how-to in `.claude/skills/ui-mockups/SKILL.md`). `screens-publish.sh`
commits the PNGs to the side branch `em-screens/issue-<n>` (never merged) and comments with SHA-pinned
links, since GitHub has no API to attach images.

- `em-plan`: when the plan touches the UI, a designer prototypes the views and posts mockups on the plan
  PR. `mock-save.sh` keeps the prototype code on `em-mockups/issue-<n>` (never merged) and the planner
  adds a "Mockup:" bullet to the tasks that build those views, so the developers reuse it.
- `em-pr`: when a task's diff touches the UI, its developer posts screenshots of every changed view on
  the task PR before the review; no screenshots, no review. The reviewers do not look at them: they
  are for the human.

Every comment carries a banner with the role that wrote it (🟣 planner, 🟠 designer, 🔴 reviewer,
🔵 developer, 🟢 workflow), since all of them are posted by the same GitHub identity.

Run state (current task, findings, answers, round counter) lives in `state/`, which git ignores.
