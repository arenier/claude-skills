#!/usr/bin/env bash
set -euo pipefail

# Validate a PR title and body, push the branch, and open the PR.
#
#   ./open.sh "<title>" <body-file>
#
# Nothing is pushed unless every check passes; all problems are reported at
# once. Checks:
#   - not on main, no PR already open for this branch
#   - title passes conventional.sh
#   - body has no empty section and no N/A filler
#   - every `Closes #N` names an issue that exists and is open
#   - body ends with the Claude Code footer
# Uncommitted changes are reported as a warning: they will not be in the PR.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../../scripts"
BASE_BRANCH="${BASE_BRANCH:-main}"
FOOTER='🤖 Generated with [Claude Code](https://claude.com/claude-code)'

TITLE="${1:-}"
BODY_FILE="${2:-}"
if [[ -z "$TITLE" || -z "$BODY_FILE" ]]; then
  echo "usage: $0 \"<title>\" <body-file>" >&2
  exit 2
fi

problems=()
BRANCH="$(git branch --show-current)"

[[ "$BRANCH" == "$BASE_BRANCH" ]] && problems+=("sur ${BASE_BRANCH} : créer d'abord la branche")

if existing="$(gh pr view "$BRANCH" --json url,state --jq 'select(.state == "OPEN") | .url' 2>/dev/null)" \
   && [[ -n "$existing" ]]; then
  problems+=("une PR est déjà ouverte pour ${BRANCH} : ${existing} (la mettre à jour par gh pr edit --body-file)")
fi

if ! title_problems="$("$SCRIPTS/conventional.sh" "$TITLE")"; then
  while IFS= read -r line; do problems+=("titre : ${line}"); done <<<"$title_problems"
fi

# A heading directly followed by another heading (or the end of the body) is a
# section with nothing in it.
empty_sections="$(awk '
  /^## / { if (h != "" && !content) print h; h = $0; content = 0; next }
  NF     { content = 1 }
  END    { if (h != "" && !content) print h }
' "$BODY_FILE")"
while IFS= read -r h; do
  [[ -n "$h" ]] && problems+=("section vide : ${h} (la supprimer)")
done <<<"$empty_sections"

if grep -qiE '^[[:space:]]*(-[[:space:]]*)?(n/?a|néant|aucun\.?|rien à signaler\.?)[[:space:]]*$' "$BODY_FILE"; then
  problems+=("ligne de remplissage (N/A, néant, aucun…) : supprimer la section")
fi

while IFS= read -r n; do
  [[ -z "$n" ]] && continue
  state="$(gh issue view "$n" --json state --jq .state 2>/dev/null || echo MISSING)"
  [[ "$state" != "OPEN" ]] && problems+=("Closes #${n} : issue à l'état ${state}")
done < <(grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+' "$BODY_FILE" | grep -oE '[0-9]+' || true)

last_line="$(grep -v '^[[:space:]]*$' "$BODY_FILE" | tail -n1)"
[[ "$last_line" != "$FOOTER" ]] && problems+=("le corps doit finir par : ${FOOTER}")

if (( ${#problems[@]} > 0 )); then
  echo "PR non ouverte. À corriger :" >&2
  printf '  - %s\n' "${problems[@]}" >&2
  exit 1
fi

if ! git diff HEAD --quiet; then
  echo "attention : les changements non commités ne font pas partie de la PR :" >&2
  git diff HEAD --stat >&2
fi

git push -u origin HEAD
gh pr create --base "$BASE_BRANCH" --title "$TITLE" --body-file "$BODY_FILE"
