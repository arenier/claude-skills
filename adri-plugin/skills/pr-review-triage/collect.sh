#!/usr/bin/env bash
set -euo pipefail

# Gather every piece of review feedback on a PR, and the state it applies to.
#
#   ./collect.sh [PR#]
#
# Without a PR number, targets the PR of the current branch. Writes raw JSON to
# a work directory and prints sources.md: account and push rights, local
# checkout vs PR branch, CI, then the four places a review can live (issue
# comments, formal reviews, inline comments) each tagged with how many commits
# landed after it -- a point about code that has since moved may be stale.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR="${1:-}"

if ! gh auth status >/dev/null 2>&1; then
  echo "\`gh\` non authentifié. Lance \`gh auth login\` puis relance." >&2
  exit 1
fi

if [[ -z "$PR" ]]; then
  if ! PR="$(gh pr view --json number --jq .number 2>/dev/null)"; then
    echo "Aucune PR pour la branche courante : passer le numéro." >&2
    exit 1
  fi
fi

WORKDIR="${PR_TRIAGE_DIR:-${TMPDIR:-/tmp}/pr-review-triage-${PR}}"
mkdir -p "$WORKDIR"

gh pr view "$PR" --json number,title,url,state,isDraft,reviewDecision,headRefName,headRefOid,commits \
  > "$WORKDIR/pr.json"
gh api "repos/{owner}/{repo}/issues/${PR}/comments" --paginate --jq '.[] | @json' > "$WORKDIR/comments.jsonl"
gh api "repos/{owner}/{repo}/pulls/${PR}/reviews" --paginate --jq '.[] | @json' > "$WORKDIR/reviews.jsonl"
gh api "repos/{owner}/{repo}/pulls/${PR}/comments" --paginate --jq '.[] | @json' > "$WORKDIR/inline.jsonl"
gh pr checks "$PR" > "$WORKDIR/checks.txt" 2>&1 || true

{
  echo "login=$(gh api user --jq .login)"
  echo "can_push=$(gh api 'repos/{owner}/{repo}' --jq .permissions.push)"
  echo "local_branch=$(git branch --show-current)"
  echo "dirty=$(git status --porcelain | wc -l | tr -d ' ')"
} > "$WORKDIR/local.env"

python3 "$HERE/sources.py" "$WORKDIR" > "$WORKDIR/sources.md"
cat "$WORKDIR/sources.md"
echo ""
echo "WORKDIR=${WORKDIR}"
