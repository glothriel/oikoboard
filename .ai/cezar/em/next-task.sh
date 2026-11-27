#!/usr/bin/env bash
# Pick the first open task ("## [ ] <id>: <title>") of the plan this branch adds, reset per-task state.
# exit 0 + "<id>: <title>" = a task to do; exit 1 = no open task left.
set -euo pipefail
s=.ai/cezar/em/state
mkdir -p "$s"
base=origin/${CEZ_PR_BASE_REF:-${CEZ_BASE:-master}}
if git rev-parse -q --verify "$base" >/dev/null; then
  plans=$(git diff --name-only "$base"...HEAD -- '.ai/specs/*.tasks.md')
else
  plans=$(ls .ai/specs/*.tasks.md 2>/dev/null || true)
fi
tasks=$(grep -l '^## \[ \] ' $plans 2>/dev/null | head -1 || true)
if [ -z "$tasks" ]; then echo "no open tasks"; exit 1; fi
awk '/^## /{ if (p) exit } /^## \[ \] /{ p=1 } p' "$tasks" > "$s/task-body.md"
head=$(head -1 "$s/task-body.md")
id=$(sed -E 's/^## \[ \] ([^:]+):.*/\1/' <<<"$head")
title=$(sed -E 's/^## \[ \] [^:]+: *//' <<<"$head")
{
  echo "# Current task: $id"
  echo
  echo "- Spec: \`${tasks%.tasks.md}.md\`"
  echo "- Full task list: \`$tasks\` (tasks marked [x] are done; do not start later ones)"
  echo
  cat "$s/task-body.md"
} > "$s/current-task.md"
echo "$tasks" > "$s/tasks-file"
echo "$id" > "$s/task-id"
echo "$id: $title" > "$s/task-title"
git rev-parse HEAD > "$s/base"
echo 0 > "$s/rounds"
rm -f "$s/review.md" "$s/reply.md"
echo "$id: $title"
