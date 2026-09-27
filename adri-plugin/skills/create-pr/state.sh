#!/usr/bin/env bash
set -euo pipefail

# Report the real state of the work before a PR is written: branch, commits,
# committed and uncommitted scope, untracked files, open issues, and whether a
# PR already exists for this branch.
#
#   ./state.sh
#
# Read-only. The diff itself is printed at the end: the PR body is written from
# it, not from the conversation.

BASE_BRANCH="${BASE_BRANCH:-main}"
BRANCH="$(git branch --show-current)"

section() { printf '\n=== %s ===\n' "$1"; }

section "Branch"
echo "current: ${BRANCH:-<detached>}"
if [[ "$BRANCH" == "$BASE_BRANCH" ]]; then
  echo "ON_BASE=yes  -> créer la branche avant tout"
else
  echo "ON_BASE=no"
fi

section "Commits on the branch (${BASE_BRANCH}..HEAD)"
git log "${BASE_BRANCH}..HEAD" --oneline || true

section "Committed scope (${BASE_BRANCH}...HEAD)"
git diff "${BASE_BRANCH}...HEAD" --stat || true

section "Uncommitted, tracked"
git diff HEAD --stat

section "Untracked"
git ls-files --others --exclude-standard

section "Existing PR for this branch"
if [[ -n "$BRANCH" && "$BRANCH" != "$BASE_BRANCH" ]] \
   && url="$(gh pr view "$BRANCH" --json url,state --jq '.state + " " + .url' 2>/dev/null)"; then
  echo "$url"
else
  echo "aucune"
fi

section "Open issues"
gh issue list --state open --limit 50 --json number,title \
  --jq '.[] | "#\(.number)  \(.title)"' || echo "(impossible de lister les issues)"

section "Checks available"
if [[ -f package.json ]]; then
  echo "package.json présent -> lancer checks.sh"
else
  echo "pas de package.json -> rien à lancer ; le dire dans la section Tests"
fi

section "Diff (${BASE_BRANCH}...HEAD, then uncommitted)"
git diff "${BASE_BRANCH}...HEAD" || true
git diff HEAD
