#!/usr/bin/env bash
# Start the next task: move to the tip of the feature branch (earlier tasks are merged there), pick
# its first open task ("## [ ] <id>: <title>") and reset per-task state.
# Prints "<id>: <title>", or "NONE" when every task is done. Non-zero exit only on errors.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
feature=$(cat "$S/feature")
git fetch -q origin "$feature"
git reset -q --hard "origin/$feature"
tasks=$(grep -l '^## \[ \] ' $(plan_tasks_files) 2>/dev/null | head -1 || true)
if [ -z "$tasks" ]; then echo "NONE"; exit 0; fi
awk '/^## /{ if (p) exit } /^## \[ \] /{ p=1 } p' "$tasks" > "$S/task-body.md"
head=$(head -1 "$S/task-body.md")
id=$(sed -E 's/^## \[ \] ([^:]+):.*/\1/' <<<"$head")
title=$(sed -E 's/^## \[ \] [^:]+: *//' <<<"$head")
{
  echo "# Current task: $id"
  echo
  echo "- Spec: \`${tasks%.tasks.md}.md\`"
  echo "- Full task list: \`$tasks\` (tasks marked [x] are done; do not start later ones)"
  echo
  cat "$S/task-body.md"
} > "$S/current-task.md"
echo "$tasks" > "$S/tasks-file"
echo "$id" > "$S/task-id"
echo "$id: $title" > "$S/task-title"
echo "em/issue-$(cat "$S/issue")-$(tr '[:upper:]' '[:lower:]' <<<"$id")" > "$S/head-ref"
git rev-parse HEAD > "$S/base"
echo 0 > "$S/rounds"
rm -f "$S/pr" "$S/review.md" "$S/reply.md" "$S/answer.md"
echo "$id: $title"
