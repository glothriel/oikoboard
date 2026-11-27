#!/usr/bin/env bash
# em-plan start: fetch the issue (with its comments) for the planner, reset state.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
n=${CEZ_GITHUB_NUMBER:?em-plan starts from a GitHub issue}
echo plan > "$S/task-id"
echo 0 > "$S/rounds"
echo "$n" > "$S/issue"
gh issue view "$n" -R "$(repo)" --json title --jq .title > "$S/issue-title"
gh issue view "$n" -R "$(repo)" --comments > "$S/issue.md"
echo "issue #$n: $(cat "$S/issue-title")"
