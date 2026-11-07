#!/usr/bin/env bash
# One-time cleanup of the public pip-island repo, run from your Mac:
#   1. rewrites every branch and tag so no commit names Claude as author or co-author
#      (and drops the Claude-Session links), without changing any file,
#   2. deletes the old, already-merged PR branches and drops "claude/" from branch names,
#   3. force-pushes the result,
#   4. deletes every release except the latest, and cleans the latest one's notes.
#
#   bash scripts/scrub-history.sh            show the plan, change nothing
#   bash scripts/scrub-history.sh --push     do it
#
# Needs git and the GitHub CLI (gh), logged in with write access to the repo.
set -euo pipefail

REPO="${PIP_RELEASE_REPO:-frazz1234/pip-island}"
REMOTE="${PIP_REMOTE_URL:-https://github.com/$REPO.git}"
NAME="${SCRUB_NAME:-Alexandre Fradet}"
EMAIL="${SCRUB_EMAIL:-api@zaparound.com}"
# PR branches that are already merged into main.
OLD_BRANCHES="claude/instagram-reels claude/readme-new-features readme-banner readme-download-guide"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone -q --bare "$REMOTE" "$work/repo.git"
cd "$work/repo.git"

for b in $OLD_BRANCHES; do git update-ref -d "refs/heads/$b" 2>/dev/null || true; done

# Lines dropped from every commit message.
cat > "$work/msg.sh" <<'EOF'
grep -viE '^[[:space:]]*(Co-authored-by:|Claude-Session:|Generated (with|by) \[?Claude|🤖)' \
  | grep -viE 'claude\.ai/code|noreply@anthropic\.com' \
  | awk 'NF { if (blank && seen) print ""; print; seen = 1; blank = 0; next } { blank = 1 }'
EOF

export FILTER_BRANCH_SQUELCH_WARNING=1 SCRUB_NAME="$NAME" SCRUB_EMAIL="$EMAIL"
git filter-branch -f \
  --env-filter '
    if [ "$GIT_AUTHOR_EMAIL" = noreply@anthropic.com ]; then
      GIT_AUTHOR_NAME="$SCRUB_NAME"; GIT_AUTHOR_EMAIL="$SCRUB_EMAIL"; fi
    if [ "$GIT_COMMITTER_EMAIL" = noreply@anthropic.com ]; then
      GIT_COMMITTER_NAME="$SCRUB_NAME"; GIT_COMMITTER_EMAIL="$SCRUB_EMAIL"; fi
    export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL' \
  --msg-filter "bash '$work/msg.sh'" \
  --tag-name-filter cat -- --branches --tags >/dev/null 2>&1

# claude/foo → foo
renamed=""
for ref in $(git for-each-ref --format='%(refname:short)' 'refs/heads/claude/'); do
  new="${ref#claude/}"
  git show-ref -q --verify "refs/heads/$new" && new="$new-2"
  git branch -m "$ref" "$new"
  renamed="$renamed $ref"
done

left="$(git log --branches --tags --format='%an%n%cn%n%B' | grep -ciE 'claude-session|co-authored-by|noreply@anthropic|^claude$' || true)"
echo "Branches after cleanup: $(git for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ')"
echo "Lines still naming Claude as author or co-author: $left"
[ "$left" = 0 ] || { echo "Something was missed; nothing pushed." >&2; exit 1; }

if [ "${1:-}" != --push ]; then
  echo
  echo "Nothing changed yet. Run again with --push to update GitHub."
  exit 0
fi

git push -q --force "$REMOTE" 'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
for b in $OLD_BRANCHES $renamed; do git push -q "$REMOTE" --delete "$b" 2>/dev/null || true; done
echo "✓ History rewritten and pushed."

# The release script lives on the cleanup branch; take it from there.
notes="$work/clean-release-notes.sh"
git show "vigilant-dijkstra-j7krct:scripts/clean-release-notes.sh" > "$notes" 2>/dev/null \
  || git show "main:scripts/clean-release-notes.sh" > "$notes"
PIP_RELEASE_REPO="$REPO" bash "$notes" --prune
PIP_RELEASE_REPO="$REPO" bash "$notes" --apply
echo "✓ Only the latest release is left, with clean notes."
echo
echo "Pull request pages (#1–#5) still show their original commits: GitHub keeps those."
echo "Run 'git fetch --all && git reset --hard origin/main' in any local copy of this repo."
