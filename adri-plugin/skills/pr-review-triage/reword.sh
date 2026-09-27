#!/usr/bin/env bash
set -euo pipefail

# Rewrite the message of one commit on the current branch without touching the
# working tree or the index.
#
#   ./reword.sh <commit> <message-file>
#
# `git rebase -i` is unavailable here, and `git reset --hard` would destroy
# uncommitted local changes. Plumbing rebuilds the commit and every commit after
# it with identical trees, authors and dates, then moves the branch only if it
# has not moved meanwhile. Does not push: the force-push command is printed, to
# run only on explicit request.

TARGET="${1:-}"
MSG_FILE="${2:-}"
if [[ -z "$TARGET" || -z "$MSG_FILE" ]]; then
  echo "usage: $0 <commit> <message-file>" >&2
  exit 2
fi

BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null)" || { echo "erreur : HEAD détachée." >&2; exit 1; }
OLD_HEAD="$(git rev-parse HEAD)"
C1="$(git rev-parse --verify "${TARGET}^{commit}")"

git merge-base --is-ancestor "$C1" "$OLD_HEAD" \
  || { echo "erreur : ${TARGET} n'est pas dans l'historique de ${BRANCH}." >&2; exit 1; }
BASE="$(git rev-parse --verify "${C1}^" 2>/dev/null)" \
  || { echo "erreur : commit racine, non pris en charge." >&2; exit 1; }
if [[ -n "$(git rev-list --merges "${BASE}..${OLD_HEAD}")" ]]; then
  echo "erreur : commit de merge après ${TARGET}, historique non linéaire." >&2
  exit 1
fi

STATUS_BEFORE="$(git status --porcelain)"
TMP_MSG="$(mktemp)"
trap 'rm -f "$TMP_MSG"' EXIT

rebuild() {  # $1 = source commit, $2 = new parent, $3 = message file
  GIT_AUTHOR_NAME="$(git log -1 --format=%an "$1")" \
  GIT_AUTHOR_EMAIL="$(git log -1 --format=%ae "$1")" \
  GIT_AUTHOR_DATE="$(git log -1 --format=%aI "$1")" \
  GIT_COMMITTER_DATE="$(git log -1 --format=%cI "$1")" \
  git commit-tree "$(git rev-parse "$1^{tree}")" -p "$2" -F "$3"
}

NEW="$(rebuild "$C1" "$BASE" "$MSG_FILE")"
while IFS= read -r c; do
  git log -1 --format=%B "$c" > "$TMP_MSG"
  NEW="$(rebuild "$c" "$NEW" "$TMP_MSG")"
done < <(git rev-list --reverse "${C1}..${OLD_HEAD}")

# The third argument makes update-ref refuse if the branch moved meanwhile.
git update-ref -m "reword ${C1:0:12}" "refs/heads/${BRANCH}" "$NEW" "$OLD_HEAD"

if ! git diff --quiet "$OLD_HEAD" "$NEW"; then
  echo "erreur : le contenu diffère après réécriture — restaurer : git update-ref refs/heads/${BRANCH} ${OLD_HEAD}" >&2
  exit 1
fi
if [[ "$(git status --porcelain)" != "$STATUS_BEFORE" ]]; then
  echo "attention : l'état de l'arbre de travail a changé." >&2
fi

echo "Réécrit : ${OLD_HEAD:0:12} -> ${NEW:0:12} (contenu identique, arbre de travail intact)"
git log --oneline "${BASE}..${NEW}"
echo ""
echo "Pousser, sur accord explicite seulement :"
echo "  git push --force-with-lease=${BRANCH}:${OLD_HEAD} origin ${BRANCH}"
