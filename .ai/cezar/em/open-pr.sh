#!/usr/bin/env bash
# Push the plan to em/issue-<n> and open (or reuse) its draft PR. The PR is not labelled yet, so
# human reviews during the AI plan review trigger nothing.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
n=$(cat "$S/issue")
ref=em/issue-$n
echo "$ref" > "$S/head-ref"
git push -q --force origin "HEAD:refs/heads/$ref"
pr=$(gh pr list -R "$(repo)" --head "$ref" --state open --json number --jq '.[0].number // empty')
if [ -z "$pr" ]; then
  body="Plan for #$n, written by the cezar \`em-plan\` workflow (\`.ai/cezar/em/\`). The same PR later carries the implementation.

Closes #$n"
  url=$(gh pr create -R "$(repo)" --draft --base "${CEZ_BASE:-master}" --head "$ref" \
    --title "$(cat "$S/issue-title")" --body "$body")
  pr=${url##*/}
fi
echo "$pr" > "$S/pr"
echo "PR #$pr on $ref"
