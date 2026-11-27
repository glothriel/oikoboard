#!/usr/bin/env bash
# Run the repository's validation gate: every command in .ai/agentic.config.json, in order.
set -euo pipefail
python3 -c 'import json; print("\n".join(json.load(open(".ai/agentic.config.json"))["validation"]["commands"]))' |
while IFS= read -r cmd; do
  echo "\$ $cmd"
  bash -c "$cmd" 2>&1
done
