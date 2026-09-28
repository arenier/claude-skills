#!/usr/bin/env bash
set -euo pipefail

# Gather everything a review of one PR needs, into a work directory:
#
#   pr.json      metadata (title, author, state, base/head, files, commits, CI)
#   diff.patch   the full diff
#   head/<path>  every touched file in its PR version (not the local checkout)
#   facts.md     mechanical facts: stop conditions, size, title check, CI,
#                ADR routing per file, and the grep-level checks
#
#   ./collect.sh [PR#]
#
# Without a PR number, takes the only open PR; with several open, lists them
# and exits 3 so the choice goes back to the user. Read-only on GitHub.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR="${1:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "\`gh\` (GitHub CLI) requis. Installation : \`brew install gh\`." >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "\`gh\` installé mais non authentifié. Lance \`gh auth login\` puis relance." >&2
  exit 1
fi

if [[ -z "$PR" ]]; then
  open_prs="$(gh pr list --state open --json number,title --jq '.[] | "\(.number)\t\(.title)"')"
  count="$(grep -c . <<<"$open_prs" || true)"
  if [[ "$count" -eq 0 ]]; then
    echo "Aucune PR ouverte." >&2
    exit 1
  elif [[ "$count" -gt 1 ]]; then
    echo "Plusieurs PR ouvertes, laquelle relire ?" >&2
    echo "$open_prs" >&2
    exit 3
  fi
  PR="$(cut -f1 <<<"$open_prs")"
fi

WORKDIR="${PR_REVIEW_DIR:-${TMPDIR:-/tmp}/pr-review-${PR}}"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/head"

gh pr view "$PR" --json number,title,body,author,state,isDraft,baseRefName,headRefName,headRefOid,additions,deletions,files,commits,statusCheckRollup,labels \
  > "$WORKDIR/pr.json"
gh pr diff "$PR" > "$WORKDIR/diff.patch"

# The local checkout is almost never the PR branch: reading a touched file from
# disk would show main's version and produce findings about code the PR has
# already changed. Fetch each touched file at the PR head commit instead.
HEAD_SHA="$(gh pr view "$PR" --json headRefOid --jq .headRefOid)"
missing=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  encoded="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$path")"
  mkdir -p "$WORKDIR/head/$(dirname "$path")"
  if ! gh api -H "Accept: application/vnd.github.raw" \
       "repos/{owner}/{repo}/contents/${encoded}?ref=${HEAD_SHA}" \
       > "$WORKDIR/head/$path" 2>/dev/null; then
    rm -f "$WORKDIR/head/$path"   # deleted by the PR
    missing=$((missing + 1))
  fi
done < <(gh pr view "$PR" --json files --jq '.files[].path')

python3 "$HERE/analyze.py" "$WORKDIR" > "$WORKDIR/facts.md"

cat "$WORKDIR/facts.md"
echo ""
echo "Fichiers en version PR : ${WORKDIR}/head/ (${missing} supprimé(s) par la PR)"
echo "WORKDIR=${WORKDIR}"
