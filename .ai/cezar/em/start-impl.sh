#!/usr/bin/env bash
# The plan was approved: merge the plan PR into the feature branch; the task loop takes over.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
echo plan > "$S/task-id"
echo "▶️ Plan approved by @$(cat "$S/reviewer"). Merging it into \`$(cat "$S/feature")\`; every task follows as its own PR into that branch." > "$S/start.md"
bash "$d/post-comment.sh" workflow "$S/start.md"
merge_pr "$(target)" merge
gh api -X DELETE "repos/$(repo)/git/refs/heads/$(cat "$S/head-ref")" >/dev/null || true
# From here on each task opens its own PR.
rm -f "$S/pr" "$S/head-ref"
echo "merged plan PR into $(cat "$S/feature")"
