#!/usr/bin/env bash
# Count review rounds of the current task (or plan); fail past CEZ_EM_MAX_ROUNDS (default 3).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
max=${CEZ_EM_MAX_ROUNDS:-3}
n=$(( $(cat "$S/rounds" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$S/rounds"
if [ "$n" -gt "$max" ]; then echo "$(cat "$S/task-id"): still open after $max review rounds"; exit 1; fi
echo "$(cat "$S/task-id"): review round $n/$max"
