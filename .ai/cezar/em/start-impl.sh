#!/usr/bin/env bash
# The plan was approved: move the PR to stage:impl and say so.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
gh pr edit "$(target)" -R "$(repo)" --remove-label stage:plan --add-label stage:impl >/dev/null
echo workflow > "$S/task-id"
echo "▶️ Plan approved by @$(cat "$S/reviewer"). Implementing it task by task on this PR." > "$S/start.md"
bash "$d/post-comment.sh" workflow "$S/start.md"
