#!/usr/bin/env bash
# post-comment.sh <reviewer|developer|planner|workflow> <file>: one comment with a role banner,
# since every comment is posted by the same GitHub identity.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
role=$1 file=$2
task=$(cat "$S/task-id" 2>/dev/null || echo plan)
rounds=$(cat "$S/rounds" 2>/dev/null || echo 0)
case $role in
  reviewer)  head="> [!CAUTION]
> 🔴 **REVIEWER** · $task · round $((rounds + 1))" ;;
  developer) head="> [!NOTE]
> 🔵 **DEVELOPER** · $task" ;;
  planner)   head="> [!IMPORTANT]
> 🟣 **PLANNER** · $task" ;;
  workflow)  head="> [!TIP]
> 🟢 **WORKFLOW** · $task" ;;
  *) echo "unknown role $role"; exit 2 ;;
esac
printf '%s\n\n%s\n' "$head" "$(cat "$file")" > "$S/comment.md"
cat "$S/comment.md"
comment "$S/comment.md"
