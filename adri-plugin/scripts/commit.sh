#!/usr/bin/env bash
set -euo pipefail

# Commit exactly the given paths, with a Conventional Commits subject and the
# repo's co-author trailer.
#
#   ./commit.sh -m "fix(recognition): reject empty shelf photos" [-b body.txt] -- <path>...
#
# Refuses to commit on main (protected, direct push rejected), refuses a subject
# that fails conventional.sh, and refuses `.` or an empty path list: staging the
# whole tree picks up screenshots, local config and dev-server artifacts.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAILER="${COMMIT_TRAILER:-Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>}"
BASE_BRANCH="${BASE_BRANCH:-main}"

usage() {
  echo "usage: $0 -m \"<subject>\" [-b <body-file>] -- <path>..." >&2
  exit 2
}

SUBJECT=""
BODY_FILE=""
while (( $# > 0 )); do
  case "$1" in
    -m) SUBJECT="${2:-}"; shift 2 ;;
    -b) BODY_FILE="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *) usage ;;
  esac
done
[[ -z "$SUBJECT" || $# -eq 0 ]] && usage

for path in "$@"; do
  case "$path" in
    .|./|-A|--all|:/) echo "erreur : refus d'ajouter '${path}' — lister les fichiers du changement." >&2; exit 1 ;;
  esac
done

if [[ "$(git branch --show-current)" == "$BASE_BRANCH" ]]; then
  echo "erreur : sur ${BASE_BRANCH}. Créer d'abord la branche : git checkout -b <type>/<résumé>" >&2
  exit 1
fi

if ! problems="$("$HERE/conventional.sh" "$SUBJECT")"; then
  echo "erreur : sujet refusé :" >&2
  while IFS= read -r line; do echo "  - ${line}" >&2; done <<<"$problems"
  exit 1
fi

git add -- "$@"

if git diff --cached --quiet; then
  echo "erreur : rien à commiter pour ces chemins." >&2
  exit 1
fi

MSG="$(mktemp)"
trap 'rm -f "$MSG"' EXIT
{
  echo "$SUBJECT"
  if [[ -n "$BODY_FILE" ]]; then
    echo ""
    cat "$BODY_FILE"
  fi
  echo ""
  echo "$TRAILER"
} > "$MSG"

git commit -q -F "$MSG"
git log -1 --format='%h %s'
git show --stat --format= HEAD
