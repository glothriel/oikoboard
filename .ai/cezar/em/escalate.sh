#!/usr/bin/env bash
# Out of review rounds or verify fixes: push what there is, ask a human on the PR.
set -euo pipefail
d=$(dirname "$0") s=.ai/cezar/em/state
task=$(cat "$s/task-id" 2>/dev/null || echo '?')
{
  echo "⛔ stuck on $task after $(cat "$s/rounds" 2>/dev/null || echo 0) review round(s)."
  echo
  echo "The developer/reviewer exchange is in the comments above. Answer with a PR review to continue."
} > "$s/escalate.md"
bash "$d/post-comment.sh" workflow "$s/escalate.md"
git add -A
git commit -qm "$task: work in progress" || true
bash "$d/push.sh"
if [ -n "${CEZ_GITHUB_NUMBER:-}" ]; then gh pr edit "$CEZ_GITHUB_NUMBER" -R "$CEZ_GITHUB_REPO" --add-label needs-human; fi
