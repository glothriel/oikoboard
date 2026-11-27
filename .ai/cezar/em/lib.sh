# Sourced by the gate scripts. Run state lives in $S (git-ignored).
#
# Branches of one issue <n>:
#   feature/issue-<n>          everything for the issue; one PR from it to the main branch at the end
#   em/issue-<n>-plan          spec + tasks, PR into the feature branch
#   em/issue-<n>-<task id>     one task, PR into the feature branch
S=.ai/cezar/em/state
mkdir -p "$S"

# The repository and the issue/PR the scripts talk to: $EM_PR if set, the PR this run works on
# once there is one, else the issue or PR the run was started for.
repo() { echo "${CEZ_GITHUB_REPO:?no GitHub repository for this run}"; }
target() {
  if [ -n "${EM_PR:-}" ]; then echo "$EM_PR"; return; fi
  cat "$S/pr" 2>/dev/null || echo "${CEZ_GITHUB_NUMBER:?no GitHub issue or PR for this run}"
}

# origin/<main branch>: what feature branches start from and finally merge into.
main_base() { git rev-parse -q --verify --abbrev-ref origin/HEAD 2>/dev/null || echo origin/master; }
main_branch() { local b; b=$(main_base); echo "${b#origin/}"; }

# The task lists (.ai/specs/*.tasks.md) this branch adds or changes against the main branch.
plan_tasks_files() {
  local base; base=$(main_base)
  if git rev-parse -q --verify "$base" >/dev/null; then
    git diff --name-only "$base"...HEAD -- '.ai/specs/*.tasks.md'
  else
    ls .ai/specs/*.tasks.md 2>/dev/null || true
  fi
}

# comment <file>: post a file as a comment on target() (issues and PRs alike).
comment() { gh api "repos/$(repo)/issues/$(target)/comments" -F "body=@$1" >/dev/null; }
