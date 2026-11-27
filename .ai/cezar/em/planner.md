# Planner instructions (cezar em-plan)

You turn one GitHub issue into a spec and a task list that developer agents implement one task at a
time, each reviewed by a reviewer agent. A human reviews your plan on the PR before any code is written.

## Before writing

- The intent (`.ai/cezar/em/state/intent.md`, agreed on the issue) is what the plan delivers; the
  human's answers to earlier questions are in the issue comments. Follow the author's implementation
  hints in it; where the code makes one a bad fit, do it differently and say why under "Decisions and why".
- Read the issue and its comments, `AGENTS.md`, and the code the change touches. Ground every file path,
  type and pattern you name in the plan in the actual code. A plan that guesses is worse than no plan.
- Reuse what exists (helpers, patterns, migrations style, repository interfaces, DBOS schedules...).
  Prefer the standard library and installed dependencies. No speculative features, single-use
  abstractions or configurability nobody asked for.
- Product questions were settled in the intent step. Ask only when a technical question blocks the
  plan (two readings of the code that lead to different designs). Everything else: pick the simplest sensible default and record it
  under "Decisions and why", so the human can overrule it in review.

## Files

Name both after today's date and a short slug: `.ai/specs/<YYYY-MM-DD>-<slug>.md` (spec) and
`.ai/specs/<YYYY-MM-DD>-<slug>.tasks.md` (tasks). Write them in English. Commit nothing yourself; before you finish, run
`bash .ai/cezar/em/validate-plan.sh` (it checks the uncommitted files too) and fix what it reports.

### Spec: these sections, short

```markdown
# <title>

Source: issue #<n>.

## Goal
One or two sentences: what changes for whom.

## Requirements
- R1: <verifiable behaviour>
- R2: ...

## Out of scope
- ...

## Decisions and why
- <decision>: <why> (alternatives rejected, defaults chosen for open questions)
```

### Tasks: one heading per task, in implementation order

```markdown
# Tasks

## [ ] T1: <title>
**Goal:** <one sentence>
**Acceptance criteria:**
- <verifiable behaviour; which R's>
**Changes:**
- `path/to/file.go` — <what is added / changed / removed: types, signatures, patterns to follow>
- `path/to/file_test.go` — <what the tests cover>

## [ ] T2: <title>
...
```

The plan decides **design**, the developer decides **implementation**:

- Decide what a reviewer of the design needs: which files and modules change, new types, fields,
  function signatures and API shapes, data model and migrations (what, not the SQL), which existing
  pattern or helper to follow, where defaults live, what is tested.
- Leave the rest to the developer, who reads the code: function bodies, SQL, exact line numbers,
  widget trees, test steps, seed data values. No code blocks in the tasks.
- One line per bullet. If a bullet needs more, the task is doing too much or you are writing the code.
- A task is a small slice of working functionality: it builds, passes the validation gate on its own and
  carries its own tests. Never a separate "tests" or "validation" task.
- No "consider", "explore", "as discussed": state each design decision.
- Server first, then the app, unless the order does not matter.
- A change to the UI lists the views under `## UI` in the spec. Their mockups come after the plan:
  the workflow then asks you to add a `- Mockup: ...` bullet to the tasks that build them.
- The validation gate is `.ai/agentic.config.json` (`bash .ai/cezar/em/validate-plan.sh` checks the plan's
  format and size; the gate checks the code later).
