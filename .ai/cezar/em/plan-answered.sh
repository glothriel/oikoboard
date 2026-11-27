#!/usr/bin/env bash
# The planner revised the plan after a human review: push, answer, ask for another look.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
echo plan > "$S/task-id"
bash "$d/push.sh"
[ -s "$S/answer.md" ] || echo "Revised the plan; see the latest commits." > "$S/answer.md"
bash "$d/post-comment.sh" planner "$S/answer.md"
gh api "repos/$(repo)/pulls/$(target)/requested_reviewers" -f "reviewers[]=$(cat "$S/reviewer")" >/dev/null || true
