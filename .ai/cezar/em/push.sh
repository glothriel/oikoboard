#!/usr/bin/env bash
# Push to the PR head branch when the run was started from a PR; otherwise nothing to do.
set -euo pipefail
if [ -n "${CEZ_PR_HEAD_REF:-}" ]; then git push origin "HEAD:$CEZ_PR_HEAD_REF"; else echo "(no PR head: not pushing)"; fi
