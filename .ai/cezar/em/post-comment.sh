#!/usr/bin/env bash
# post-comment.sh <reviewer|developer|workflow> <file>: one PR comment with a role banner.
# Posts to the PR the run was started for (CEZ_GITHUB_NUMBER); without one, only prints it.
set -euo pipefail
s=.ai/cezar/em/state
role=$1 file=$2
task=$(cat "$s/task-id" 2>/dev/null || echo plan)
rounds=$(cat "$s/rounds" 2>/dev/null || echo 0)
case $role in
  reviewer)  head="> [!CAUTION]
> 🔴 **REVIEWER** · $task · round $((rounds + 1))" ;;
  developer) head="> [!NOTE]
> 🔵 **DEVELOPER** · $task · answer to round $rounds" ;;
  workflow)  head="> [!TIP]
> 🟢 **WORKFLOW** · $task" ;;
  *) echo "unknown role $role"; exit 2 ;;
esac
body=$(printf '%s\n\n%s\n' "$head" "$(cat "$file")")
printf '%s\n' "$body"
if [ -n "${CEZ_GITHUB_NUMBER:-}" ] && [ -n "${CEZ_GITHUB_REPO:-}" ]; then
  printf '%s\n' "$body" | gh pr comment "$CEZ_GITHUB_NUMBER" -R "$CEZ_GITHUB_REPO" --body-file -
else
  echo "(no PR for this run: comment not posted)"
fi
