#!/usr/bin/env bash
# Every task is merged into the feature branch: open (or update) the final PR into the main branch
# and hand it to the human, who merges it.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
feature=$(cat "$S/feature") n=$(cat "$S/issue") main=$(main_branch)
pr=$(gh pr list -R "$(repo)" --head "$feature" --base "$main" --state open --json number --jq '.[0].number // empty')
if [ -z "$pr" ]; then
  title=$(gh issue view "$n" -R "$(repo)" --json title --jq .title)
  {
    echo "Everything for #$n: the plan and one squashed commit per task, each reviewed by agents in its own PR into \`$feature\`."
    echo
    echo "Closes #$n"
  } > "$S/final-pr.md"
  url=$(gh pr create -R "$(repo)" --base "$main" --head "$feature" --title "$title" --body-file "$S/final-pr.md")
  pr=${url##*/}
fi
echo "$pr" > "$S/pr"
gh pr edit "$pr" -R "$(repo)" --add-label stage:final >/dev/null
echo final > "$S/task-id"
reviewer=$(cat "$S/reviewer")
{
  echo "✅ All tasks are merged into \`$feature\`. Ready for your review, @$reviewer."
  echo
  echo "- **Approve** and merge when happy."
  echo "- **Request changes** or **comment**: your review becomes a new task with its own PR into \`$feature\`."
} > "$S/ready.md"
bash "$d/post-comment.sh" workflow "$S/ready.md"
gh api "repos/$(repo)/pulls/$pr/requested_reviewers" -f "reviewers[]=$reviewer" >/dev/null || true
echo "final PR #$pr"
