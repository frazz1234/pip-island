#!/usr/bin/env bash
# Cleans Pip's public release notes: drops merge lines ("Merge pull request #16 from
# frazz1234/claude/…"), co-author and session lines, so only the change summary is left.
#
#   scripts/clean-release-notes.sh             show what would change on every release
#   scripts/clean-release-notes.sh --apply     rewrite the notes on GitHub (needs gh, logged in)
#   git log -1 --pretty=%B | scripts/clean-release-notes.sh --filter
#                                              clean one message (use it in release.sh)
#   scripts/clean-release-notes.sh --prune     delete every release and tag except the latest
set -euo pipefail

REPO="${PIP_RELEASE_REPO:-frazz1234/pip-island}"

clean() {
  # Drop the lines that name the tool or the branch, then trim blank lines.
  grep -viE '^[[:space:]]*(Merge (pull request|branch|remote-tracking branch)\b|Co-authored-by:|Claude-Session:|Generated (with|by) \[?Claude|🤖)' \
    | grep -viE 'claude\.ai/code|noreply@anthropic\.com' \
    | awk 'NF { if (blank && seen) print ""; print; seen = 1; blank = 0; next } { blank = 1 }'
}

case "${1:-}" in
  --filter)
    clean || true
    exit 0
    ;;
  ""|--apply|--prune) ;;
  *) echo "Usage: $0 [--apply | --filter | --prune]" >&2; exit 2 ;;
esac

command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh" >&2; exit 1; }

if [ "${1:-}" = --prune ]; then
  latest="$(gh release view --repo "$REPO" --json tagName --jq .tagName)"
  echo "Keeping $latest. Deleting every other release and its tag…"
  gh release list --repo "$REPO" --limit 1000 --json tagName --jq '.[].tagName' | while read -r tag; do
    [ "$tag" = "$latest" ] && continue
    gh release delete "$tag" --repo "$REPO" --cleanup-tag --yes && echo "  ✗ $tag" || true
  done
  # Tags left without a release.
  git ls-remote --tags "https://github.com/$REPO.git" | awk '{print $2}' | grep -v '\^{}$' | sed 's#refs/tags/##' \
    | while read -r tag; do
        [ "$tag" = "$latest" ] && continue
        gh api -X DELETE "repos/$REPO/git/refs/tags/$tag" >/dev/null 2>&1 && echo "  ✗ tag $tag" || true
      done
  echo "Done. Only $latest is left."
  exit 0
fi

changed=0
while IFS=$'\t' read -r id tag; do
  old="$(gh api "repos/$REPO/releases/$id" --jq '.body // ""')"
  new="$(printf '%s\n' "$old" | clean || true)"
  [ -n "$new" ] || new="Pip ${tag#v}"
  [ "$old" = "$new" ] && continue
  changed=$((changed + 1))
  echo "── $tag"
  diff <(printf '%s\n' "$old") <(printf '%s\n' "$new") | sed -n 's/^[<>] .*/  &/p' || true
  if [ "${1:-}" = --apply ]; then
    gh api -X PATCH "repos/$REPO/releases/$id" -f body="$new" >/dev/null
    echo "  ✓ updated"
  fi
done < <(gh api "repos/$REPO/releases" --paginate --jq '.[] | "\(.id)\t\(.tag_name)"')

if [ "$changed" = 0 ]; then
  echo "All release notes are already clean."
elif [ "${1:-}" != --apply ]; then
  echo
  echo "$changed release(s) would change. Run again with --apply to update them."
fi
