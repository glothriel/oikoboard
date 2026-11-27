#!/usr/bin/env bash
# The reviewer approved: tick the task, squash the task's commits (cezar autosaves every turn)
# into one "<id>: <title>" commit, tell the PR, push.
set -euo pipefail
d=$(dirname "$0") s=.ai/cezar/em/state
id=$(cat "$s/task-id")
tasks=$(cat "$s/tasks-file")
sed -i "s/^## \[ \] $id:/## [x] $id:/" "$tasks"
git reset -q --soft "$(cat "$s/base")"
git add -A
git commit -qm "$(cat "$s/task-title")"
echo "✅ approved after $(cat "$s/rounds") round(s) of changes" > "$s/done.md"
bash "$d/post-comment.sh" workflow "$s/done.md"
bash "$d/push.sh"
