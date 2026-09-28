#!/usr/bin/env bash
set -euo pipefail

# Check that a PR title or commit subject has the Conventional Commits form the
# repo expects: `type(scope): subject`, lowercase subject, ~70 characters max.
#
#   ./conventional.sh "feat(recognition): extract author/title pairs"
#
# Prints `ok`, or one line per problem (in French: it lands in French
# deliverables),, and exits non-zero on any problem.
# Whether the subject is imperative is not checked here: that is a judgment.

SUBJECT="${1:-}"
MAX_LENGTH="${MAX_LENGTH:-72}"
TYPES="feat|fix|docs|refactor|chore|test|perf|build|ci|style|revert"

if [[ -z "$SUBJECT" ]]; then
  echo "usage: $0 \"<subject>\"" >&2
  exit 2
fi

problems=()

if [[ ! "$SUBJECT" =~ ^($TYPES)(\([a-z0-9._/-]+\))?!?:\ (.+)$ ]]; then
  problems+=("forme attendue \`type(scope): sujet\`, type parmi ${TYPES//|/, }")
else
  text="${BASH_REMATCH[3]}"
  [[ "$text" =~ ^[[:upper:]] ]] && problems+=("le sujet commence par une majuscule")
  [[ "$text" == *. ]] && problems+=("le sujet finit par un point")
fi

(( ${#SUBJECT} > MAX_LENGTH )) && problems+=("${#SUBJECT} caractères, ${MAX_LENGTH} au plus")

if (( ${#problems[@]} == 0 )); then
  echo "ok"
  exit 0
fi
printf '%s\n' "${problems[@]}"
exit 1
