#!/usr/bin/env bash
# Out of review rounds or fixes: push what there is, ask a human, and say how to go on.
#   plan: the plan PR goes to the human as it is (stage:plan); a review continues as usual.
#   task: the human comments on the task PR (or pushes a fix), then labels the issue `resume`.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
task=$(cat "$S/task-id" 2>/dev/null || echo '?')
n=$(cat "$S/issue" 2>/dev/null || echo '?')
git add -A
git commit -qm "$task: work in progress" || true
bash "$d/push.sh"
{
  echo "⛔ stuck on $task after $(cat "$S/rounds" 2>/dev/null || echo 0) review round(s). The exchange so far is in the comments above."
  echo
  if [ "$task" = plan ]; then
    echo "Review this PR as usual: **approve** to start the implementation, or **request changes** for the planner."
  else
    echo "Say what to do in a comment here (or push a fix to \`$(cat "$S/head-ref" 2>/dev/null || echo "this branch")\`), then add the \`resume\` label to issue #$n: the developer carries on from this branch and reads this PR."
  fi
} > "$S/escalate.md"
bash "$d/post-comment.sh" workflow "$S/escalate.md"
gh api "repos/$(repo)/issues/$(target)/labels" -f 'labels[]=needs-human' >/dev/null
if [ "$task" = plan ]; then
  gh pr ready "$(target)" -R "$(repo)" >/dev/null 2>&1 || true
  gh api "repos/$(repo)/issues/$(target)/labels" -f 'labels[]=stage:plan' >/dev/null
fi
