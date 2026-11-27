#!/usr/bin/env bash
# em-pr start: classify the PR's latest human review. Prints one word:
#   approve-plan | changes-plan | changes-final | resume | skip
# and keeps the review (body + inline comments) in $S/human-review.md for whoever acts on it.
#   stage:plan  = the plan PR (em/issue-<n>-plan -> feature/issue-<n>)
#   stage:final = the final PR (feature/issue-<n> -> main branch); approving it means nothing here,
#                 the human merges it.
#   resume      = label `resume` on the issue (after an escalation or a failed run): back into the
#                 task loop at the first open task of feature/issue-<n>.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
if [[ ${CEZ_GITHUB_EVENT:-} == issue.* ]]; then
  n=${CEZ_GITHUB_NUMBER:?}
  gh issue edit "$n" -R "$(repo)" --remove-label resume --remove-label needs-human >/dev/null || true
  if ! git ls-remote -q --exit-code origin "refs/heads/feature/issue-$n" >/dev/null; then
    echo "no feature/issue-$n to resume: add the agent label to start from the issue" >&2
    echo skip; exit 0
  fi
  echo "$n" > "$S/issue"
  echo "feature/issue-$n" > "$S/feature"
  rm -f "$S/pr" "$S/head-ref"
  final=$(gh pr list -R "$(repo)" --head "feature/issue-$n" --state open --json number --jq '.[0].number // empty')
  if [ -n "$final" ]; then echo "$final" > "$S/final-pr"; fi
  echo "resume issue #$n"
  echo resume; exit 0
fi
pr=${CEZ_GITHUB_NUMBER:?em-pr starts from a pull request}
echo "$pr" > "$S/pr"
echo "${CEZ_PR_HEAD_REF:?em-pr needs the PR head checkout}" > "$S/head-ref"
labels=$(gh pr view "$pr" -R "$(repo)" --json labels --jq '.labels[].name')
if grep -qx 'stage:plan' <<<"$labels"; then stage=plan feature=$CEZ_PR_BASE_REF
elif grep -qx 'stage:final' <<<"$labels"; then stage=final feature=$CEZ_PR_HEAD_REF
else echo skip; exit 0; fi
echo "$feature" > "$S/feature"
echo "${feature#feature/issue-}" > "$S/issue"
review=$(gh api "repos/$(repo)/pulls/$pr/reviews?per_page=100" \
  --jq '[.[] | select(.state != "PENDING")] | last // empty | [.id, .state, .user.login, .author_association] | @tsv')
if [ -z "$review" ]; then echo skip; exit 0; fi
IFS=$'\t' read -r id state user assoc <<<"$review"
# Only people with a say in the repository drive the workflow.
case $assoc in OWNER|MEMBER|COLLABORATOR) ;; *) echo skip; exit 0 ;; esac
echo "$user" > "$S/reviewer"
body=$(gh api "repos/$(repo)/pulls/$pr/reviews/$id" --jq '.body // ""')
inline=$(gh api "repos/$(repo)/pulls/$pr/reviews/$id/comments?per_page=100" \
  --jq '.[] | "- `\(.path):\(.line // .original_line // "file")`: \(.body)"')
{
  echo "Review by @$user ($state):"
  echo
  if [ -n "$body" ]; then echo "$body"; echo; fi
  if [ -n "$inline" ]; then echo "Inline comments:"; echo "$inline"; fi
} > "$S/human-review.md"
case $state in
  APPROVED) [ "$stage" = plan ] && echo approve-plan || echo skip ;;
  CHANGES_REQUESTED|COMMENTED)
    if [ -z "$body$inline" ]; then echo skip; else echo "changes-$stage"; fi ;;
  *) echo skip ;;
esac
