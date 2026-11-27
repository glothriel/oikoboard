#!/usr/bin/env bash
# Out of review rounds or fixes: push what there is, ask a human.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
task=$(cat "$S/task-id" 2>/dev/null || echo '?')
{
  echo "⛔ stuck on $task after $(cat "$S/rounds" 2>/dev/null || echo 0) review round(s)."
  echo
  echo "The exchange so far is in the comments above. Answer with a PR review to continue."
} > "$S/escalate.md"
git add -A
git commit -qm "$task: work in progress" || true
bash "$d/push.sh"
bash "$d/post-comment.sh" workflow "$S/escalate.md"
gh api "repos/$(repo)/issues/$(target)/labels" -f 'labels[]=needs-human' >/dev/null
