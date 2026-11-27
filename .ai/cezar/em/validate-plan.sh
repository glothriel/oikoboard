#!/usr/bin/env bash
# Check the plan this branch adds against the format in planner.md. Lists every problem, exit 1 if any.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
errors=()
mapfile -t plans < <(plan_tasks_files)
if [ "${#plans[@]}" -ne 1 ]; then
  echo "expected exactly one .ai/specs/*.tasks.md added on this branch, found ${#plans[@]}: ${plans[*]:-none}"
  exit 1
fi
tasks=${plans[0]}
spec=${tasks%.tasks.md}.md
[ -f "$spec" ] || errors+=("missing spec $spec next to $tasks")
if [ -f "$spec" ]; then
  for section in "Goal" "Requirements" "Out of scope" "Decisions"; do
    grep -qiE "^## .*$section" "$spec" || errors+=("$spec: missing section '## $section'")
  done
fi
mapfile -t ids < <(grep -oE '^## \[[ x]\] T[0-9]+:' "$tasks" | grep -oE 'T[0-9]+')
[ "${#ids[@]}" -gt 0 ] || errors+=("$tasks: no tasks ('## [ ] T1: <title>')")
for i in "${!ids[@]}"; do
  [ "${ids[$i]}" = "T$((i + 1))" ] || errors+=("$tasks: task #$((i + 1)) is ${ids[$i]}, expected T$((i + 1))")
done
bad=$(grep -E '^## ' "$tasks" | grep -vE '^## \[[ x]\] [TR][0-9]+: .+' || true)
[ -z "$bad" ] || errors+=("$tasks: headings not in the '## [ ] T<n>: <title>' form: $bad")
missing=$(awk '/^## \[[ x]\] /{ if (id && !ac) print id; match($0, /[TR][0-9]+/); id=substr($0, RSTART, RLENGTH); ac=0 } /Acceptance criteria/{ ac=1 } END{ if (id && !ac) print id }' "$tasks")
[ -z "$missing" ] || errors+=("$tasks: no 'Acceptance criteria' in: $(echo $missing)")
open=$(grep -nE '\b(TBD|TODO)\b|\?\?\?' "$spec" "$tasks" 2>/dev/null || true)
[ -z "$open" ] || errors+=("unresolved placeholders: $open")
if [ "${#errors[@]}" -gt 0 ]; then printf -- '- %s\n' "${errors[@]}"; exit 1; fi
echo "plan ok: $spec, ${#ids[@]} task(s)"
