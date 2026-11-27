#!/usr/bin/env bash
# Every task is done: hand the PR back to the human who reviewed it last.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
echo workflow > "$S/task-id"
reviewer=$(cat "$S/reviewer")
{
  echo "✅ All tasks done. Ready for your review, @$reviewer."
  echo
  echo "- **Approve** and merge when happy."
  echo "- **Request changes** or **comment**: your review becomes a new task and goes through the same loop."
} > "$S/ready.md"
bash "$d/post-comment.sh" workflow "$S/ready.md"
gh api "repos/$(repo)/pulls/$(target)/requested_reviewers" -f "reviewers[]=$reviewer" >/dev/null || true
