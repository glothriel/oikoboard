# cezar workflows: issue to PR

Agent pipeline from a labelled issue to a reviewed PR, run by [cezar](https://cezar.run). The flow,
the branches and labels are [centurion](https://github.com/glothriel/centurion)'s (see its README).
Humans act only on GitHub: label `agent` on an issue, reviews on the `stage:plan` / `stage:final` PRs,
label `resume` on an issue to continue after an escalation, and the final merge.

What lives here:

- `centurion/`: the vendored tool (`centurion/centurion/`, `VERSION` = the centurion commit, do not
  edit), the entry `run.py`, and `project.py`: oikoboard's settings (spec sections, UI paths,
  how to build the app for screenshots).
- `rules.md`: oikoboard's rules every agent follows (spec contents, code conventions, merge clashes,
  screenshots).
- `workflows/centurion-*.yaml`: generated, do not edit. After changing `project.py` or vendoring a new
  centurion (`python3 .ai/cezar/centurion/run.py vendor <centurion checkout>`), run
  `python3 .ai/cezar/centurion/run.py generate`. `check` (part of the validation commands in
  `.ai/agentic.config.json`) fails when they are out of date.
- `.claude/skills/ui-mockups/SKILL.md`: how to screenshot this app (mock login, coordinates, widgets).
