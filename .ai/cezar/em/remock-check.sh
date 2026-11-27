#!/usr/bin/env bash
# After a human review of the plan: redo the mockups? Prints "needed" or "none".
# Needed when the plan touches the UI and either the planner asked for it ($S/mockups says "redo")
# or there are no mockups yet.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
if [ "$(bash "$d/screens-check.sh" plan)" != needed ]; then echo none; exit 0; fi
if grep -qx redo "$S/mockups" 2>/dev/null; then echo needed; exit 0; fi
if ! git ls-remote -q --exit-code origin "refs/heads/em-mockups/issue-$(cat "$S/issue")" >/dev/null; then
  echo needed
else
  echo none
fi
