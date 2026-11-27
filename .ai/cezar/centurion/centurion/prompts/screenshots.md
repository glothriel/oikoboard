# Screenshots and UI mockups (centurion)

Show the **real look and feel** with the app's own components and theme, not a hand-drawn imitation.
The repository says how the app is built and served for screenshots (`.ai/cezar/centurion/project.py`,
usually on a mock or sample backend, so no server is needed) and, in its rules, how to get around in
it (login, where things are). All paths are relative to the repository root.

## 1. Decide the views

- Every view that is new or changed, in each state that matters (empty, filled, editor open, error
  shown...). Phone size (390×800) unless the view is desktop only.
- Mockups for a plan: build only what is needed to show the views. Reuse the app's existing patterns
  and components. Hard-coded or deterministic sample data in the view is fine for a prototype; strings
  still go through the app's translations.
- Use only made-up sample data: the screenshots are published.

## 2. Take the screenshots

Write a steps file (scratch location, e.g. `.ai/cezar/centurion/state/steps.json`) and run:

```sh
python3 .ai/cezar/centurion/state/runtime/run.py screens .ai/cezar/centurion/state/steps.json   # PNGs in .ai/cezar/centurion/state/screens/
SCREENS_NO_BUILD=1 python3 .ai/cezar/centurion/state/runtime/run.py screens ...                # re-shoot without rebuilding
```

It builds the app, serves it, starts headless Chrome (`chrome-headless-shell` on the PATH or under
`~/.local/opt/chrome-headless-shell-*/`; `CHROME_BIN` overrides; needs Node with `playwright-core`
installed globally) and runs the steps:

```json
[{ "name": "editor-filled", "width": 390, "height": 800,
   "actions": [{ "click": [157, 510] }, { "wait": 2500 },
               { "shot": "home" }, { "click": [195, 245] }, { "type": "Milk" }, { "key": "Enter" }] }]
```

- Actions: `click` [x, y], `wait` ms, `type` text, `key` name, `scroll` dy, `shot` name. Optional per
  screen: `width`, `height`, `loadWait` (ms after load, default 4000); per click or key: `after` (ms,
  default 1200).
- Every screen starts from a fresh load of the app. The final state is saved as `<name>.png`;
  `{ "shot": "<step>" }` saves an intermediate `<name>.<step>.png` (not published), useful to find
  coordinates.
- An app that draws on a canvas has no DOM to query: only coordinate clicks, keyboard and wheel work.
  Find coordinates with intermediate shots, look at them, adjust. Positions move whenever the UI
  changes, so re-check after every change.
- **Look at every final PNG** before you finish: right view, nothing clipped or overlapping, no debug
  UI. Fix and re-shoot until each one reads well.
- Optional captions: `.ai/cezar/centurion/state/screens/captions.md` (one line per screenshot: what it
  shows, what is hard-coded, what is not shown).

## 3. Publish

In the workflows, the workflow publishes them: leave the final PNGs and the captions in
`.ai/cezar/centurion/state/screens/` and do nothing else. It commits them to the side branch
`centurion-screens/issue-<n>` (never merged) and comments on the PR with SHA-pinned image links.

Outside the workflows (mockups for an issue):
`python3 .ai/cezar/centurion/run.py screens-publish designer --issue <n> --pr <issue or PR number>`.

## 4. Hand over

- A plan prototype is kept on the side branch `centurion-mockups/issue-<n>` and the developers reuse
  it, so build it in the files where the plan puts the views, with real components.
- A task whose plan has a "Mockup:" bullet matches that prototype's look; explain any deliberate
  difference in the captions.
- In a task, the screenshots show the real implementation: never stub data or hide parts of the view
  just to make the shot look right.
