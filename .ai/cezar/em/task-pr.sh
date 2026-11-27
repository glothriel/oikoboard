#!/usr/bin/env bash
# The task's first green version: push it and open the task PR into the feature branch, where the
# reviewer and the developer then talk.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
ref=$(cat "$S/head-ref") feature=$(cat "$S/feature") n=$(cat "$S/issue")
git push -q --force origin "HEAD:refs/heads/$ref"
pr=$(gh pr list -R "$(repo)" --head "$ref" --state open --json number --jq '.[0].number // empty')
if [ -z "$pr" ]; then
  {
    echo "Task of #$n, implemented and reviewed by agents (cezar \`em-pr\`). Merged into \`$feature\` when the reviewer approves."
    echo
    cat "$S/task-body.md"
  } > "$S/task-pr.md"
  url=$(gh pr create -R "$(repo)" --base "$feature" --head "$ref" \
    --title "$(cat "$S/task-title")" --body-file "$S/task-pr.md")
  pr=${url##*/}
fi
echo "$pr" > "$S/pr"
echo "PR #$pr: $ref -> $feature"
