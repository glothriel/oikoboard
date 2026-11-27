#!/usr/bin/env bash
# The AI plan review approved: hand the plan PR to a human (ready + stage:plan).
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
bash "$d/push.sh"
pr=$(target)
gh pr ready "$pr" -R "$(repo)" >/dev/null
gh pr edit "$pr" -R "$(repo)" --add-label stage:plan >/dev/null
gh issue edit "$(cat "$S/issue")" -R "$(repo)" --remove-label agent >/dev/null || true
cat > "$S/ready.md" <<'EOF'
📋 Plan ready for your review.

- **Approve**: implementation starts, task by task, on this PR.
- **Request changes** or **comment**: the planner revises the spec and tasks and answers here.
EOF
bash "$d/post-comment.sh" workflow "$S/ready.md"
