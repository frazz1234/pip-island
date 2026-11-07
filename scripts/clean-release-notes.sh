#!/usr/bin/env bash
# Cleans Pip's public release notes: drops merge lines ("Merge pull request #16 from
# frazz1234/claude/…"), co-author and session lines, so only the change summary is left.
#
#   scripts/clean-release-notes.sh             show what would change on every release
#   scripts/clean-release-notes.sh --apply     rewrite the notes on GitHub (needs gh, logged in)
#   git log -1 --pretty=%B | scripts/clean-release-notes.sh --filter
#                                              clean one message (use it in release.sh)
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
  ""|--apply) ;;
  *) echo "Usage: $0 [--apply | --filter]" >&2; exit 2 ;;
esac

command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh" >&2; exit 1; }

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
