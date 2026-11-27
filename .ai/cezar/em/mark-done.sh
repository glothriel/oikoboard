#!/usr/bin/env bash
# The reviewer approved: tick the task, squash the task's commits (cezar autosaves every turn),
# update the task PR and merge it into the feature branch.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
id=$(cat "$S/task-id")
tasks=$(cat "$S/tasks-file")
sed -i "s/^## \[ \] $id:/## [x] $id:/" "$tasks"
git reset -q --soft "$(cat "$S/base")"
git add -A
git commit -qm "$(cat "$S/task-title")"
git push -q --force origin "HEAD:refs/heads/$(cat "$S/head-ref")"
# A review task (R<n>) owes the human reviewer an answer per point, on the final PR they reviewed.
if [ -s "$S/answer.md" ]; then
  bash "$d/post-comment.sh" developer "$S/answer.md"
  if [ -s "$S/final-pr" ]; then EM_PR=$(cat "$S/final-pr") bash "$d/post-comment.sh" developer "$S/answer.md"; fi
fi
echo "✅ approved after $(cat "$S/rounds") round(s) of changes; merging into \`$(cat "$S/feature")\`." > "$S/done.md"
bash "$d/post-comment.sh" workflow "$S/done.md"
merge_pr "$(target)" squash "$(git rev-parse HEAD)"
gh api -X DELETE "repos/$(repo)/git/refs/heads/$(cat "$S/head-ref")" >/dev/null || true
echo "$id merged"
