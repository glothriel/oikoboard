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
| `.ai/cezar/workflows/em-plan.yaml` | label `agent` on an issue | creates the feature branch, writes a spec + task list, AI plan review, opens the plan PR as `stage:plan` |
| `.ai/cezar/workflows/em-pr.yaml` | a human review on a `stage:plan` / `stage:final` PR | see below |

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

Every comment carries a banner with the role that wrote it (🟣 planner, 🔴 reviewer, 🔵 developer,
🟢 workflow), since all of them are posted by the same GitHub identity.

Run state (current task, findings, answers, round counter) lives in `state/`, which git ignores.
