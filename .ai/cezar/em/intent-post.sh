#!/usr/bin/env bash
# The intent has no open questions: post it on the issue for the record and go on planning.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
{
  echo "> [!IMPORTANT]"
  echo "> 🟣 **PLANNER** · intent"
  echo
  cat "$S/intent.md"
  echo
  echo "No open questions: writing the spec and the plan. Anything off here can be corrected on the plan PR."
} > "$S/comment.md"
cat "$S/comment.md"
comment "$S/comment.md"
