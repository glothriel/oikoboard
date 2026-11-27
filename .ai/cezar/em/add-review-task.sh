#!/usr/bin/env bash
# A human reviewed the final PR: append the review as task R<n> to the plan on the feature branch,
# so it runs through the same task loop (own PR into the feature branch) as every other task.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
tasks=$(plan_tasks_files | head -1)
[ -n "$tasks" ] || { echo "no plan (.ai/specs/*.tasks.md) on this branch"; exit 1; }
n=$(( $(grep -cE '^## \[[ x]\] R[0-9]+:' "$tasks" || true) + 1 ))
{
  echo
  echo "## [ ] R$n: Address review by @$(cat "$S/reviewer")"
  echo "**Acceptance criteria:** every point below is fixed, or answered with a reason."
  echo
  sed 's/^/> /' "$S/human-review.md"
} >> "$tasks"
git add "$tasks"
git commit -qm "R$n: review by @$(cat "$S/reviewer")"
git push -q origin "HEAD:refs/heads/$(cat "$S/feature")"
mv "$S/pr" "$S/final-pr"
rm -f "$S/head-ref"
echo "added R$n to $tasks"
