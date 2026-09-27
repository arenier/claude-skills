#!/usr/bin/env bash
set -euo pipefail

# Post a PR comment, or update the one already carrying the same marker.
#
#   ./upsert-comment.sh <PR#> "<!-- pr-review -->" <body-file>
#
# The marker must be the first line of the body. The comment updated is the
# most recent one by the authenticated user that starts with the marker, so the
# thread keeps a single, up-to-date comment per skill instead of a pile.
# Prints the comment URL.

PR="${1:-}"
MARKER="${2:-}"
BODY_FILE="${3:-}"

if [[ -z "$PR" || -z "$MARKER" || -z "$BODY_FILE" ]]; then
  echo "usage: $0 <PR#> <marker> <body-file>" >&2
  exit 2
fi

if [[ "$(head -n1 "$BODY_FILE")" != "$MARKER" ]]; then
  echo "erreur : la première ligne de ${BODY_FILE} doit être ${MARKER}" >&2
  exit 1
fi

ME="$(gh api user --jq .login)"

EXISTING="$(gh api "repos/{owner}/{repo}/issues/${PR}/comments" --paginate \
  --jq ".[] | select(.user.login == \"${ME}\" and (.body | startswith(\"${MARKER}\"))) | .id" \
  | tail -n1)"

if [[ -n "$EXISTING" ]]; then
  gh api -X PATCH "repos/{owner}/{repo}/issues/comments/${EXISTING}" \
    -F body=@"$BODY_FILE" --jq '"mis à jour " + .html_url'
else
  gh api -X POST "repos/{owner}/{repo}/issues/${PR}/comments" \
    -F body=@"$BODY_FILE" --jq '"créé " + .html_url'
fi
