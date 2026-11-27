#!/usr/bin/env bash
# Before the designer reworks the mockups of a revised plan: remember the plan commit and put the
# previous prototype (em-mockups/issue-<n>, without its copy of the plan) back into the work tree.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
echo plan > "$S/task-id"
git add -A
git diff --cached --quiet || git commit -q -m "Revise the plan after review"
base=$(git rev-parse HEAD)
echo "$base" > "$S/mock-base"
branch=em-mockups/issue-$(cat "$S/issue")
if ! git ls-remote -q --exit-code origin "refs/heads/$branch" >/dev/null; then
  echo "no previous prototype: start from the plan"
  exit 0
fi
git fetch -q origin "$branch"
from=$(git merge-base HEAD FETCH_HEAD)
if git diff "$from" FETCH_HEAD -- . ':(exclude).ai/specs' | git apply --index; then
  echo "previous prototype ($branch) applied on top of the revised plan:"
  git diff --cached --stat "$base" | tail -n 30
else
  git reset -q --hard "$base"
  echo "the previous prototype ($branch) does not apply to the revised plan: start from the plan," \
    "reading the old one with git show FETCH_HEAD:<path>"
fi
