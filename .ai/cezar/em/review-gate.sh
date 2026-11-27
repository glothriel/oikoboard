#!/usr/bin/env bash
# em-pr start: classify the PR's latest human review. Prints one word:
#   approve-plan | changes-plan | changes-impl | skip
# and keeps the review (body + inline comments) in $S/human-review.md for whoever acts on it.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
pr=${CEZ_GITHUB_NUMBER:?em-pr starts from a pull request}
echo "$pr" > "$S/pr"
echo "${CEZ_PR_HEAD_REF:?em-pr needs the PR head checkout}" > "$S/head-ref"
labels=$(gh pr view "$pr" -R "$(repo)" --json labels --jq '.labels[].name')
if grep -qx 'stage:plan' <<<"$labels"; then stage=plan
elif grep -qx 'stage:impl' <<<"$labels"; then stage=impl
else echo skip; exit 0; fi
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
