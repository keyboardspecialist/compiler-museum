#!/bin/sh
# Publish the built site/ to the gh-pages branch for GitHub Pages.
# Run ./build.sh first; this syncs site/ into a gh-pages worktree, drops a
# .nojekyll (so Pages serves _-prefixed paths and skips jekyll), commits, pushes.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$here/site
wt=$here/.gh-pages

[ -d "$out" ] || { echo "deploy.sh: no site/ — run ./build.sh first" >&2; exit 1; }

git -C "$here" worktree add -B gh-pages "$wt" 2>/dev/null \
	|| git -C "$here" worktree add "$wt" gh-pages

rsync -a --delete --exclude .git "$out"/ "$wt"/
touch "$wt/.nojekyll"

git -C "$wt" add -A
if git -C "$wt" diff --cached --quiet; then
	echo "deploy.sh: gh-pages already up to date"
else
	git -C "$wt" commit -q -m "Deploy site $(git -C "$here" rev-parse --short HEAD)"
fi
git -C "$wt" push -u origin gh-pages

git -C "$here" worktree remove "$wt"
echo "deployed -> gh-pages  (https://keyboardspecialist.github.io/compiler-museum/)"
