#!/usr/bin/env bash
# Create feature/issue-<n> from the main branch (once), push the plan to em/issue-<n>-plan and open
# (or reuse) its draft PR into the feature branch. Not labelled yet, so human reviews during the AI
# plan review trigger nothing.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
n=$(cat "$S/issue")
feature=feature/issue-$n
ref=em/issue-$n-plan
echo "$feature" > "$S/feature"
echo "$ref" > "$S/head-ref"
if ! git ls-remote -q --exit-code origin "refs/heads/$feature" >/dev/null; then
  git push -q origin "$(git rev-parse "$(main_base)"):refs/heads/$feature"
fi
git push -q --force origin "HEAD:refs/heads/$ref"
pr=$(gh pr list -R "$(repo)" --head "$ref" --state open --json number --jq '.[0].number // empty')
if [ -z "$pr" ]; then
  body="Plan for #$n, written by the cezar \`em-plan\` workflow (\`.ai/cezar/em/\`).

Merges into \`$feature\`. After it, every task gets its own PR into \`$feature\`, and \`$feature\`
goes to \`$(main_branch)\` in one final PR."
  url=$(gh pr create -R "$(repo)" --draft --base "$feature" --head "$ref" \
    --title "Plan: $(cat "$S/issue-title")" --body "$body")
  pr=${url##*/}
fi
echo "$pr" > "$S/pr"
echo "PR #$pr: $ref -> $feature"
