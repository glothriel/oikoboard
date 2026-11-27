# cezar EM workflow: gate scripts

Helper scripts for the cezar workflow `.ai/cezar/workflows/em-impl.yaml`. Not used by the app or by CI.

The workflow implements an approved plan task by task. The flow is fixed by the graph; agents only fill
in the steps (develop, review, give a verdict). Per task:

1. `next-task.sh` picks the first open task (`## [ ] T<n>: <title>`) of the plan this branch adds:
   `.ai/specs/<name>.tasks.md`, next to its spec `.ai/specs/<name>.md`.
2. A developer agent implements it; `verify.sh` runs the validation commands from
   `.ai/agentic.config.json`. Red: the same developer session fixes it.
3. A reviewer agent reviews the task's diff against the spec and gives a verdict.
   `changes`: the findings go to the PR (`post-comment.sh`), the same developer session fixes or
   justifies each one, and the same reviewer session re-reviews. `round-guard.sh` caps the rounds
   (`CEZ_EM_MAX_ROUNDS`, default 3).
4. `approve`: `mark-done.sh` ticks the task, squashes its commits into one `T<n>: <title>` commit,
   comments on the PR and pushes to the PR branch.
5. Out of rounds or fixes: `escalate.sh` pushes what there is, comments and labels the PR `needs-human`.

Every PR comment carries a banner with the role that wrote it (🔴 reviewer, 🔵 developer, 🟢 workflow),
since all of them are posted by the same GitHub identity.

Run state (current task, findings, replies, round counter) lives in `state/`, which git ignores.
