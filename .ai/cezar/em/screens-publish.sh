#!/usr/bin/env bash
# screens-publish.sh <role> [--optional]: publish $S/screens/<name>.png on the current PR.
# GitHub has no API to attach images to a comment, so the PNGs are committed to the side branch
# em-screens/issue-<n> (never merged; plumbing only, the work tree is untouched) and the comment
# links them by commit SHA. Captions come from $S/screens/captions.md. Intermediate shots
# (<name>.<step>.png) are dropped. Without screenshots: exit 1, or 0 with --optional.
set -euo pipefail
d=$(dirname "$0")
. "$d/lib.sh"
role=$1 optional=${2:-}
shopt -s nullglob
pngs=()
for f in "$S"/screens/*.png; do
  base=$(basename "$f" .png)
  [[ $base == *.* ]] || pngs+=("$f")
done
if [ "${#pngs[@]}" -eq 0 ]; then
  if [ "$optional" = --optional ]; then echo "no new screenshots"; exit 0; fi
  echo "no screenshots in $S/screens: take one per changed view with .ai/cezar/em/screens.sh"
  exit 1
fi
task=$(cat "$S/task-id" 2>/dev/null || echo plan)
branch=em-screens/issue-$(cat "$S/issue")
prefix=$task/$(date -u +%Y%m%d-%H%M%S)

idx=$(mktemp)
trap 'rm -f "$idx"' EXIT
parent=$(git ls-remote origin "refs/heads/$branch" | cut -f1)
if [ -n "$parent" ]; then
  git fetch -q origin "$branch"
  GIT_INDEX_FILE=$idx git read-tree "$parent"
else
  GIT_INDEX_FILE=$idx git read-tree --empty
fi
for f in "${pngs[@]}"; do
  blob=$(git hash-object -w "$f")
  GIT_INDEX_FILE=$idx git update-index --add --cacheinfo "100644,$blob,$prefix/$(basename "$f")"
done
tree=$(GIT_INDEX_FILE=$idx git write-tree)
commit=$(git commit-tree "$tree" ${parent:+-p "$parent"} -m "screens: issue $(cat "$S/issue") $prefix")
git push -q origin "$commit:refs/heads/$branch"

{
  if [ -s "$S/screens/captions.md" ]; then cat "$S/screens/captions.md"; echo; fi
  for f in "${pngs[@]}"; do
    name=$(basename "$f" .png)
    echo "**$name**"
    echo
    echo "![$name](https://raw.githubusercontent.com/$(repo)/$commit/$prefix/$name.png)"
    echo
  done
} > "$S/screens.md"
bash "$d/post-comment.sh" "$role" "$S/screens.md"

mkdir -p "$S/screens-published/$prefix"
mv "${pngs[@]}" "$S/screens-published/$prefix/"
if [ -n "${CEZ_ARTIFACTS_DIR:-}" ]; then mkdir -p "$CEZ_ARTIFACTS_DIR" && cp "$S/screens-published/$prefix/"*.png "$CEZ_ARTIFACTS_DIR/"; fi
rm -f "$S"/screens/*.png "$S/screens/captions.md"
echo "published ${#pngs[@]} screenshot(s) at $commit"
