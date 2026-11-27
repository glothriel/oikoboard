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

# The task lists (.ai/specs/*.tasks.md) this branch adds or changes against the main branch,
# committed or not (agents check their plan before cezar commits it at the end of their turn).
plan_tasks_files() {
  local base; base=$(main_base)
  if git rev-parse -q --verify "$base" >/dev/null; then
    {
      git diff --name-only "$(git merge-base "$base" HEAD)" -- '.ai/specs/*.tasks.md'
      git ls-files --others --exclude-standard -- '.ai/specs/*.tasks.md'
    } | sort -u
  else
    ls .ai/specs/*.tasks.md 2>/dev/null || true
  fi
}

# comment <file>: post a file as a comment on target() (issues and PRs alike).
comment() { gh api "repos/$(repo)/issues/$(target)/comments" -F "body=@$1" >/dev/null; }

# merge_pr <pr> <merge|squash> [sha]: merge through the API. GitHub answers 405 "Base/Head branch was
# modified" for a while after a push, so retry; a PR that is already merged counts as done.
merge_pr() {
  local pr=$1 method=$2 sha=${3:-} i out
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if out=$(gh api -X PUT "repos/$(repo)/pulls/$pr/merge" -f merge_method="$method" ${sha:+-f sha="$sha"} 2>&1); then
      return 0
    fi
    if [ "$(gh pr view "$pr" -R "$(repo)" --json state --jq .state)" = MERGED ]; then return 0; fi
    echo "merge of #$pr not possible yet ($i/10): $out" >&2
    sleep $((i * 3))
  done
  echo "could not merge #$pr: $out" >&2
  return 1
}
