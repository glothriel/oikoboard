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
ref=em/issue-$(cat "$S/issue")-$(tr '[:upper:]' '[:lower:]' <<<"$id")
echo "$ref" > "$S/head-ref"
git rev-parse HEAD > "$S/base"
echo 0 > "$S/rounds"
rm -f "$S/pr" "$S/review.md" "$S/reply.md" "$S/answer.md"
# An earlier attempt at this task (escalated, or its run died) left its branch: carry on from it.
if git fetch -q origin "$ref" 2>/dev/null && git merge-base --is-ancestor HEAD FETCH_HEAD; then
  git reset -q --hard FETCH_HEAD
  pr=$(gh pr list -R "$(repo)" --head "$ref" --state open --json number --jq '.[0].number // empty')
  {
    echo
    echo "## Resumed"
    echo
    echo "An earlier attempt at this task is already in the work tree (\`git diff \$(cat .ai/cezar/em/state/base)\`)."
    if [ -n "$pr" ]; then
      echo "Its PR #$pr has the exchange so far, including any human comments: \`gh pr view $pr --comments\`."
      echo "Finish the task from there; do not start over."
    fi
  } >> "$S/current-task.md"
  if [ -n "$pr" ]; then
    gh pr edit "$pr" -R "$(repo)" --remove-label needs-human >/dev/null 2>&1 || true
  fi
  echo "$id: $title (resumed from $ref)"
  exit 0
fi
echo "$id: $title"
