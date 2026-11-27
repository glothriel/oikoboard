#!/usr/bin/env bash
# ask-issue.sh intent|plan: post on the issue.
#   intent  the intent with the open questions (intent.md + questions.md); waits for the human
#   plan    planner questions that block the plan (questions.md); waits for the human
# Waiting means dropping the trigger label, so that adding it again (after answering) starts a new run.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
case ${1:?intent or plan} in
  intent)
    {
      echo "> [!IMPORTANT]"
      echo "> 🟣 **PLANNER** · intent, questions before the spec"
      echo
      cat "$S/intent.md"
      echo
      echo "### Questions"
      echo
      cat "$S/questions.md"
    } > "$S/comment.md" ;;
  plan)
    {
      echo "> [!IMPORTANT]"
      echo "> 🟣 **PLANNER** · questions before planning"
      echo
      cat "$S/questions.md"
    } > "$S/comment.md" ;;
  *) echo "usage: ask-issue.sh intent|plan"; exit 2 ;;
esac
printf '\nAnswer in a comment, then add the `agent` label again.\n' >> "$S/comment.md"
cat "$S/comment.md"
comment "$S/comment.md"
gh issue edit "$(cat "$S/issue")" -R "$(repo)" --remove-label agent >/dev/null
