#!/usr/bin/env bash
# em-cleanup: an issue's work is over (final PR merged or closed, or the plan PR closed unmerged).
# Delete every branch of the issue: feature/issue-<n>, em/issue-<n>-*, em-mockups/issue-<n>,
# em-screens/issue-<n> (screenshots linked from old comments stop showing once GitHub drops the commits).
# Open PRs into the feature branch are closed. A closed PR's branch can be restored from its page.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
pr=${CEZ_GITHUB_NUMBER:?em-cleanup starts from a pull request}
read -r state head labels < <(gh pr view "$pr" -R "$(repo)" --json state,headRefName,labels \
  --jq '[.state, .headRefName, ([.labels[].name] | join(","))] | @tsv')
case ",$labels," in
  *,stage:final,*) n=${head#feature/issue-} ;;
  *,stage:plan,*)
    # merging the plan PR is how implementation starts: not the end
    if [ "$state" = MERGED ]; then echo "plan PR merged: nothing to clean"; exit 0; fi
    n=${head#em/issue-}; n=${n%-plan} ;;
  *) echo "not an em PR: nothing to clean"; exit 0 ;;
esac
if [ "$state" = OPEN ]; then echo "PR #$pr is open: nothing to clean"; exit 0; fi
case $n in ''|*[!0-9]*) echo "cannot tell the issue from branch $head"; exit 1 ;; esac
echo "$n" > "$S/issue"
echo cleanup > "$S/task-id"

for open in $(gh pr list -R "$(repo)" --base "feature/issue-$n" --state open --json number --jq '.[].number'); do
  gh pr close "$open" -R "$(repo)" --comment "Issue #$n is done (#$pr ${state,,}); closing." >/dev/null
  echo "closed PR #$open"
done
deleted=()
while read -r ref; do
  b=${ref#refs/heads/}
  case $b in
    "feature/issue-$n" | "em/issue-$n-"* | "em-mockups/issue-$n" | "em-screens/issue-$n") ;;
    *) continue ;;
  esac
  gh api -X DELETE "repos/$(repo)/git/refs/heads/$b" >/dev/null && deleted+=("$b") && echo "deleted $b"
done < <(git ls-remote --heads origin | cut -f2)

if [ "${#deleted[@]}" -gt 0 ]; then
  printf 'PR #%s %s: deleted the branches of this issue: %s\n' "$pr" "${state,,}" \
    "$(printf '`%s` ' "${deleted[@]}")" > "$S/cleanup.md"
  EM_PR=$n bash "$d/post-comment.sh" workflow "$S/cleanup.md" >/dev/null
fi
echo "issue #$n: ${#deleted[@]} branch(es) deleted"
