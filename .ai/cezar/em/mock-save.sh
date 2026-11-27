#!/usr/bin/env bash
# Keep the designer's prototype on em-mockups/issue-<n> (never merged), then drop it from the plan
# branch. Prints what the planner needs to point the tasks at it.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
n=$(cat "$S/issue")
base=$(cat "$S/mock-base")
branch=em-mockups/issue-$n
git add -A
git diff --cached --quiet || git commit -q -m "Mockup prototype for #$n (reference only, never merged)"
if git diff --quiet "$base" HEAD; then
  echo "no prototype code to keep"
  rm -f "$S/mock-branch"
else
  git push -q --force origin "HEAD:refs/heads/$branch"
  echo "$branch" > "$S/mock-branch"
  echo "prototype kept on $branch ($(git rev-parse --short HEAD)), against the plan commit $(git rev-parse --short "$base"):"
  git diff --stat "$base" HEAD | tail -n 30
fi
git reset -q --hard "$base"
