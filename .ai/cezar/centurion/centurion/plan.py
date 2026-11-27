"""The plan: a spec `.ai/specs/<name>.md` and its task list `.ai/specs/<name>.tasks.md`.

Task list format (prompts/planner.md):

    ## [ ] T1: <title>
    **Goal:** ...
    **Acceptance criteria:**
    - ...
    **Changes:**
    - `path` — ...

Done tasks are `## [x] ...`; review tasks appended from the final PR are `R<n>`.
"""

import re

MAX_BULLET = 240

_ANY_TASK = re.compile(r"^## \[[ x]\] ")
_T_TASK = re.compile(r"^## \[[ x]\] T[0-9]+:")
_GOOD_HEADING = re.compile(r"^## \[[ x]\] [TR][0-9]+: .+")
_ID = re.compile(r"[TR][0-9]+")
_OPEN = re.compile(r"^## \[ \] ")
_PLACEHOLDER = re.compile(r"\b(TBD|TODO)\b|\?\?\?")


def spec_for(tasks_path):
    return tasks_path[: -len(".tasks.md")] + ".md"


def check_plan(spec_path, spec_text, tasks_path, tasks_text, sections, max_bullet=MAX_BULLET):
    """Every problem of a plan, as messages; `spec_text` is None when the spec is missing.
    Returns (errors, number of T tasks)."""
    errors = []
    if spec_text is None:
        errors.append(f"missing spec {spec_path} next to {tasks_path}")
    else:
        for section in sections:
            if not re.search(r"^## .*" + re.escape(section), spec_text, re.I | re.M):
                errors.append(f"{spec_path}: missing section '## {section}'")

    lines = tasks_text.splitlines()
    ids = [re.search(r"T[0-9]+", line).group() for line in lines if _T_TASK.match(line)]
    if not ids:
        errors.append(f"{tasks_path}: no tasks ('## [ ] T1: <title>')")
    for i, task_id in enumerate(ids, 1):
        if task_id != f"T{i}":
            errors.append(f"{tasks_path}: task #{i} is {task_id}, expected T{i}")

    bad = [line for line in lines if line.startswith("## ") and not _GOOD_HEADING.match(line)]
    if bad:
        errors.append(f"{tasks_path}: headings not in the '## [ ] T<n>: <title>' form: " + "\n".join(bad))

    missing, current, has_ac = [], "", False
    for line in lines:
        if _ANY_TASK.match(line):
            if current and not has_ac:
                missing.append(current)
            m = _ID.search(line)
            current, has_ac = (m.group() if m else ""), False
        if "Acceptance criteria" in line:
            has_ac = True
    if current and not has_ac:
        missing.append(current)
    if missing:
        errors.append(f"{tasks_path}: no 'Acceptance criteria' in: {' '.join(missing)}")

    if any(line.startswith("```") for line in lines):
        errors.append(f"{tasks_path}: code blocks in tasks; the plan names types and signatures, the developer writes the code")

    long, current = [], ""
    for line in lines:
        if _ANY_TASK.match(line):
            m = _ID.search(line)
            current = m.group() if m else ""
        if line.startswith("- ") and len(line) > max_bullet:
            long.append(f"{current}: {line[:70]}...")
    if long:
        errors.append(f"{tasks_path}: bullets over {max_bullet} characters (one line per change; leave the "
                      f"implementation to the developer):\n" + "\n".join(long))

    hits = []
    for path, text in ((spec_path, spec_text), (tasks_path, tasks_text)):
        if text is None:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if _PLACEHOLDER.search(line):
                hits.append(f"{path}:{i}:{line}")
    if hits:
        errors.append("unresolved placeholders: " + "\n".join(hits))
    return errors, len(ids)


def has_open_task(text):
    return any(_OPEN.match(line) for line in text.splitlines())


def first_open_task(text):
    """(id, title, body) of the first `## [ ] <id>: <title>` task, or None. The body runs from
    its heading to the next `## ` heading."""
    body, inside = [], False
    for line in text.splitlines():
        if line.startswith("## ") and inside:
            break
        if _OPEN.match(line):
            inside = True
        if inside:
            body.append(line)
    if not body:
        return None
    m = re.match(r"^## \[ \] ([^:]+):\s*(.*)$", body[0])
    if not m:
        return None
    return m.group(1), m.group(2), "\n".join(body) + "\n"


def tick(text, task_id):
    return re.sub(r"^## \[ \] " + re.escape(task_id) + ":", f"## [x] {task_id}:", text, flags=re.M)


def review_task_count(text):
    return len(re.findall(r"^## \[[ x]\] R[0-9]+:", text, flags=re.M))


def append_review_task(text, reviewer, review):
    """Append the human review of the final PR as the next task R<n>. Returns (text, id)."""
    task_id = f"R{review_task_count(text) + 1}"
    if text and not text.endswith("\n"):
        text += "\n"
    quoted = "\n".join("> " + line for line in review.splitlines())
    text += (f"\n## [ ] {task_id}: Address review by @{reviewer}\n"
             "**Acceptance criteria:** every point below is fixed, or answered with a reason.\n\n"
             f"{quoted}\n")
    return text, task_id
