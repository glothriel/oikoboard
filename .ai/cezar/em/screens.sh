#!/usr/bin/env bash
# screens.sh <steps.json> [out dir]: screenshots of the app on the mock backend (no server needed).
# Builds the Flutter web app with OIKO_API=mock, serves it, runs the steps in headless Chrome
# (format in shot.mjs) and writes <out dir>/<name>.png (default .ai/cezar/em/state/screens).
# The mock login shows a "Who are you?" picker first: start every screen's actions there.
set -euo pipefail
d=$(cd "$(dirname "$0")" && pwd)
steps=$(realpath "$1")
out=$(realpath -m "${2:-.ai/cezar/em/state/screens}")
root=$(git rev-parse --show-toplevel)

chrome=${CHROME_BIN:-$(command -v chrome-headless-shell || ls -d "$HOME"/.local/opt/chrome-headless-shell-*/chrome-headless-shell 2>/dev/null | tail -1)}
[ -x "$chrome" ] || { echo "no chrome-headless-shell (set CHROME_BIN)"; exit 2; }

if [ "${SCREENS_NO_BUILD:-}" != 1 ]; then
  (cd "$root/app" && flutter build web --dart-define=OIKO_API=mock >/dev/null)
fi
port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
web=$(port) cdp=$(port) tmp=$(mktemp -d)
python3 -m http.server "$web" --bind 127.0.0.1 --directory "$root/app/build/web" >/dev/null 2>&1 &
pids=($!)
"$chrome" --no-sandbox --disable-gpu --disable-crash-reporter --hide-scrollbars \
  --remote-debugging-port="$cdp" --user-data-dir="$tmp/profile" about:blank >/dev/null 2>&1 &
pids+=($!)
trap 'kill "${pids[@]}" 2>/dev/null || true; wait 2>/dev/null || true; rm -rf "$tmp"' EXIT
for _ in $(seq 50); do curl -fs "http://127.0.0.1:$cdp/json/version" >/dev/null && break; sleep 0.2; done
node "$d/shot.mjs" "http://127.0.0.1:$cdp" "http://127.0.0.1:$web/" "$steps" "$out"
