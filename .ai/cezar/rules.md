# Repository rules for the centurion workflows (oikoboard)

Read by the planner, the designer, the developers and both reviewers. They come on top of `AGENTS.md`
and centurion's role instructions. The reviewers treat a broken rule as a finding. The reviewers
review the plan and the code, not the mockup screenshots: those are for the human.

## Plan

- Server tasks first, then the app, unless the order does not matter.
- Spec `## Backward compatibility`: what this change means for existing data, the API and installed
  app versions (see `BACKWARD_COMPATIBILITY.md`), or "None" with one line why.
- A change to the app's UI lists the views it adds or changes under `## UI`, by screen name.

## Code

- Code review follows `CODE_REVIEW.md`.
- Schema changes are a new numbered goose migration; never edit an applied one.
- Every new or changed UI string is a key in both `app/lib/l10n/app_en.arb` and `app_pl.arb`.
- A new app feature works in the mock backend too (`Mock*` repositories, `OIKO_API=mock`).

## Merging master into the feature branch

- Conflicting migration numbers (both sides added `000NN_*`): master's migration keeps its number,
  renumber ours to the next free one (file name and any reference to it).
- Keep both sides' changes working; master is already released.

## UI mockups (plan only)

When a plan changes the app's UI, a designer prototypes the new and changed views in the real app on
the mock backend (no server) and posts screenshots on the plan PR, so the look is reviewed with the
plan: `python3 .ai/cezar/centurion/state/runtime/run.py screens <steps.json>`. How the tool works:
centurion's `screenshots.md` (in `.ai/cezar/centurion/centurion/prompts/`); oikoboard specifics
(mock login, coordinates, widgets to reuse): `.claude/skills/ui-mockups/SKILL.md`.

- The prototype code is kept on `centurion-mockups/issue-<n>` (never merged) and every task that
  builds one of those views says so in a "Mockup:" bullet.
- Task with a "Mockup:" bullet: reuse the prototype and match its look; adapt the code to the task
  rather than copying it line by line. Tasks take no screenshots.
- Use only made-up sample data (the repository is public). One screenshot per view and state that
  matters (empty, filled, editor open...), phone size unless the view is desktop only.
- Look at every screenshot before publishing: wrong screen, clipped or overlapping text, debug UI.
