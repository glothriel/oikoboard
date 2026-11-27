#!/usr/bin/env bash
# Count review rounds of the current task; fail past CEZ_EM_MAX_ROUNDS (default 3).
set -euo pipefail
s=.ai/cezar/em/state
max=${CEZ_EM_MAX_ROUNDS:-3}
n=$(( $(cat "$s/rounds") + 1 ))
echo "$n" > "$s/rounds"
if [ "$n" -gt "$max" ]; then echo "$(cat "$s/task-id"): still open after $max review rounds"; exit 1; fi
echo "$(cat "$s/task-id"): review round $n/$max"
