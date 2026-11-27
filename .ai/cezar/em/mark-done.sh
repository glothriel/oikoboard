#!/usr/bin/env bash
# The reviewer approved: tick the task, squash the task's commits (cezar autosaves every turn)
# into one "<id>: <title>" commit, push, tell the PR.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
id=$(cat "$S/task-id")
tasks=$(cat "$S/tasks-file")
sed -i "s/^## \[ \] $id:/## [x] $id:/" "$tasks"
git reset -q --soft "$(cat "$S/base")"
git add -A
git commit -qm "$(cat "$S/task-title")"
bash "$d/push.sh"
# A review task (R<n>) owes the human reviewer an answer per point.
if [ -s "$S/answer.md" ]; then bash "$d/post-comment.sh" developer "$S/answer.md"; fi
echo "✅ approved after $(cat "$S/rounds") round(s) of changes ($(git rev-parse --short HEAD))" > "$S/done.md"
bash "$d/post-comment.sh" workflow "$S/done.md"
