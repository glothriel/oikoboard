# Repository rules for the em workflows (oikoboard)

Read by the planner, the designer, the developers and both reviewers. They come on top of
`AGENTS.md`, `CODE_REVIEW.md` and `planner.md`. The reviewers treat a broken rule as a finding.
The reviewers review the plan and the code, not the screenshots: those are for the human.

## Spec

- `## Backward compatibility`: what this change means for existing data, the API and installed
  app versions (see `BACKWARD_COMPATIBILITY.md`), or "None" with one line why.
- A change to the app's UI lists the views it adds or changes under `## UI`, by screen name.

## Code

- Schema changes are a new numbered goose migration; never edit an applied one.
- Every new or changed UI string is a key in both `app/lib/l10n/app_en.arb` and `app_pl.arb`.
- A new app feature works in the mock backend too (`Mock*` repositories, `OIKO_API=mock`).

## Screenshots of the UI

Every view a change adds or changes is shown as a screenshot of the real app on the mock backend
(no server): `bash .ai/cezar/em/screens.sh <steps.json>`, how-to in `.claude/skills/ui-mockups/SKILL.md`.

- Plan: a designer prototypes the new and changed views and posts screenshots on the plan PR,
  so the look is reviewed with the plan. The prototype code is kept on `em-mockups/issue-<n>`
  (never merged) and every task that builds one of those views says so in a "Mockup:" bullet.
- Task with a "Mockup:" bullet: reuse the prototype and match its look; adapt the code to the task
  rather than copying it line by line. A deliberate difference from the mockup is explained in the
  task's screenshot captions.
- Task: after a task that touches `app/lib/` is green, its developer screenshots every view the task
  changed and they are posted on the task PR. A changed view without a screenshot is not done.
- Use only made-up sample data (the repository is public). One screenshot per view and state that
  matters (empty, filled, editor open...), phone size unless the view is desktop only.
- Look at every screenshot before publishing: wrong screen, clipped or overlapping text, debug UI.
