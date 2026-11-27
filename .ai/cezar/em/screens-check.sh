#!/usr/bin/env bash
# screens-check.sh <plan|task>: are screenshots required? Prints "needed" or "none".
# They are when the plan names, or the task's diff touches, a path under a prefix listed in
# screens.paths (one per line). No screens.paths: never.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
paths=$d/screens.paths
if [ ! -s "$paths" ]; then echo none; exit 0; fi
case $1 in
  plan) hits=$(grep -hoFf "$paths" $(plan_tasks_files) 2>/dev/null || true) ;;
  task) hits=$(git diff --name-only "$(cat "$S/base")" | grep -Ff "$paths" || true) ;;
  *) echo "usage: screens-check.sh plan|task"; exit 2 ;;
esac
if [ -n "$hits" ]; then echo needed; else echo none; fi
