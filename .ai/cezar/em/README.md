# cezar EM workflows: gate scripts

Helper scripts for two cezar workflows. Not used by the app or by CI. The flow is fixed by the
workflow graphs; agents only fill in the steps (plan, develop, review, give a verdict). Humans act only
on GitHub: a label on an issue, and PR reviews.

| Workflow | Started by | Does |
|---|---|---|
| `.ai/cezar/workflows/em-plan.yaml` | label `agent` on an issue | writes a spec + task list, AI plan review, opens the PR as `stage:plan` |
| `.ai/cezar/workflows/em-pr.yaml` | a human review on a `stage:plan` / `stage:impl` PR | see below |

`em-pr` reads the latest review (`review-gate.sh`) and:

- **approve on `stage:plan`**: relabels the PR `stage:impl` and implements the plan task by task.
- **changes/comment on `stage:plan`**: a planner revises the spec and tasks and answers on the PR.
- **changes/comment on `stage:impl`**: the review becomes task `R<n>` in the plan and runs through the
  same task loop; the developer answers each point.
- anything else: nothing.

## Task loop

1. `next-task.sh` picks the first open task (`## [ ] T<n>: <title>`) of the plan this branch adds:
   `.ai/specs/<name>.tasks.md`, next to its spec `.ai/specs/<name>.md` (format: `planner.md`).
2. A developer agent implements it; `verify.sh` runs the validation commands from
   `.ai/agentic.config.json`. Red: the same developer session fixes it.
3. A reviewer agent reviews the task's diff against the spec. `changes`: the findings go to the PR,
   the same developer session fixes or justifies each one, the same reviewer session re-reviews.
   `round-guard.sh` caps the rounds (`CEZ_EM_MAX_ROUNDS`, default 3).
4. `approve`: `mark-done.sh` ticks the task, squashes its commits into one `T<n>: <title>` commit,
   pushes to the PR branch and comments.
5. Out of rounds or fixes: `escalate.sh` pushes what there is, comments and labels `needs-human`.

The plan gets the same treatment in `em-plan`: planner and plan reviewer keep their sessions across
rounds, and `validate-plan.sh` checks the format before any review.

Every comment carries a banner with the role that wrote it (🟣 planner, 🔴 reviewer, 🔵 developer,
🟢 workflow), since all of them are posted by the same GitHub identity.

Run state (current task, findings, answers, round counter) lives in `state/`, which git ignores.
