# Sourced by the gate scripts. Run state lives in $S (git-ignored).
S=.ai/cezar/em/state
mkdir -p "$S"

# The repository and the issue/PR the scripts talk to: the plan PR once one exists, else the
# issue or PR the run was started for.
repo() { echo "${CEZ_GITHUB_REPO:?no GitHub repository for this run}"; }
target() { cat "$S/pr" 2>/dev/null || echo "${CEZ_GITHUB_NUMBER:?no GitHub issue or PR for this run}"; }

# The task lists (.ai/specs/*.tasks.md) this branch adds or changes against its base.
plan_tasks_files() {
  local base=origin/${CEZ_PR_BASE_REF:-${CEZ_BASE:-master}}
  if git rev-parse -q --verify "$base" >/dev/null; then
    git diff --name-only "$base"...HEAD -- '.ai/specs/*.tasks.md'
  else
    ls .ai/specs/*.tasks.md 2>/dev/null || true
  fi
}

# comment <file>: post a file as a comment on target() (issues and PRs alike).
comment() { gh api "repos/$(repo)/issues/$(target)/comments" -F "body=@$1" >/dev/null; }
