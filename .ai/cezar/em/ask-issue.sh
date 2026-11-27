#!/usr/bin/env bash
# The planner is blocked on questions: ask them on the issue and drop the trigger label, so that
# adding it again (after answering) starts a new plan run.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
{
  echo "> [!IMPORTANT]"
  echo "> 🟣 **PLANNER** · questions before planning"
  echo
  cat "$S/questions.md"
  echo
  echo "Answer in a comment, then add the \`agent\` label again."
} > "$S/comment.md"
cat "$S/comment.md"
comment "$S/comment.md"
gh issue edit "$(cat "$S/issue")" -R "$(repo)" --remove-label agent >/dev/null
