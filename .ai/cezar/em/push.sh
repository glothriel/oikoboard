#!/usr/bin/env bash
# Push the run's work to the PR branch (the plan branch this run opened, or the PR it was started for).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
ref=$(cat "$S/head-ref" 2>/dev/null || echo "${CEZ_PR_HEAD_REF:-}")
if [ -z "$ref" ]; then echo "(no PR branch: not pushing)"; exit 0; fi
git push -q origin "HEAD:refs/heads/$ref"
echo "pushed to $ref"
