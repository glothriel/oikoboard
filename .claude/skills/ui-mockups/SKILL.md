---
name: ui-mockups
description: Mockups of a planned UI as screenshots of the real Flutter app on the mock backend (prototype first), published on a PR or issue. Use when asked for mockups, screens or a UI proposal, and in the centurion workflows when a plan changes the app's UI.
---

# UI mockups (oikoboard)

Mockups belong to the plan: the designer shows the views a plan adds or changes on the plan PR.
Tasks take no screenshots; they reuse the prototype through their "Mockup:" bullets.

Show the **real look and feel** with the app's own widgets and theme, not a hand-drawn imitation.
No server: the app runs on its mock backend (`--dart-define=OIKO_API=mock`, in-memory sample data).
All paths are relative to the repository root.

The screenshot tool is centurion's: its general how-to (steps file format, captions, publishing,
hand-over) is `.ai/cezar/centurion/centurion/prompts/screenshots.md`. This skill adds what is
specific to oikoboard.

## 1. Decide the views

- Every view the plan adds or changes, in each state that matters (empty, filled, editor open, error
  shown...). Phone size (390×800) unless the view is desktop only.
- Mockups for a plan: build only what is needed to show the views. Reuse existing patterns
  (`app/lib/modules/todo`, `calendar`): editors as `showSideSheet` / `SideSheetScaffold`, FAB for the
  primary action, `MemberAvatar`/`familyProvider` for people, `Card`, `ChoiceChip`, `SegmentedButton`.
  Hard-coded or deterministic sample data in the screen file is fine for a prototype; strings still go
  through `context.l10n` (keys in `app_en.arb` and `app_pl.arb`, then `flutter gen-l10n`).
- Use only made-up sample data. The repository is public.

## 2. Take the screenshots

Write a steps file (scratch location, e.g. `.ai/cezar/centurion/state/steps.json`) and run:

```sh
python3 .ai/cezar/centurion/run.py screens .ai/cezar/centurion/state/steps.json   # PNGs in .ai/cezar/centurion/state/screens/
SCREENS_NO_BUILD=1 python3 .ai/cezar/centurion/run.py screens ...                 # re-shoot without rebuilding (~80 s saved)
```

(Inside a workflow run, use `.ai/cezar/centurion/state/runtime/run.py`, the run's own copy.) It
builds the web app on the mock backend (`flutter build web --dart-define=OIKO_API=mock`), serves
`app/build/web`, starts headless Chrome (`CHROME_BIN` overrides) and runs the steps:

```json
[{ "name": "task-editor-keep-forever",
   "actions": [{ "click": [157, 510] }, { "wait": 2500 },
               { "shot": "home" }, { "click": [195, 245] }, { "wait": 1500 }] }]
```

- Every screen starts from a fresh load on the "Who are you? (mock mode)" picker. At 390×800 the
  members are at y≈510: Mama x≈81, Tata x≈157, Ola x≈233, Kuba x≈309. The home view has the bottom
  navigation (Wall x≈65, Lists x≈195, Calendar x≈325 at y≈750).
- Flutter web is a canvas: only coordinate clicks, keyboard and wheel work. Find coordinates with
  `{ "shot": "<step>" }` (saves `<name>.<step>.png`), look at it, then adjust. Positions move whenever
  the UI changes, so re-check after every change.
- **Look at every final PNG** before publishing: right view, nothing clipped or overlapping, no debug UI.
  Fix and re-shoot until each one reads well.
- Optional captions: `.ai/cezar/centurion/state/screens/captions.md` (one line per screenshot: what it
  shows, what is hard-coded, what is not shown).

## 3. Publish

In the centurion workflows the workflow publishes them: leave the final PNGs and the captions in
`.ai/cezar/centurion/state/screens/` and do nothing else. It pushes them to the side branch
`centurion-screens/issue-<n>` and comments on the PR with SHA-pinned image links.

Outside the workflows (mockups for an issue):
`python3 .ai/cezar/centurion/run.py screens-publish designer --issue <issue> --pr <issue or PR number>`.

## 4. Hand over

- A plan prototype is kept on the side branch `centurion-mockups/issue-<n>` (the workflow commits it)
  and the developers reuse it, so build it in the files where the plan puts the views, with real
  widgets. Put the open product questions you hit while designing into the captions.
- A task whose plan has a "Mockup:" bullet reuses that prototype and matches its look.
