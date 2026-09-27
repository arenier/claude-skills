#!/usr/bin/env bash
set -euo pipefail

# Post the rendered review comment, or update the previous one. Only after an
# explicit go from the user.
#
#   ./post.sh <PR#> [workdir]

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR="${1:-}"
[[ -z "$PR" ]] && { echo "usage: $0 <PR#> [workdir]" >&2; exit 2; }
WORKDIR="${2:-${PR_REVIEW_DIR:-${TMPDIR:-/tmp}/pr-review-${PR}}}"

exec "$HERE/../../scripts/upsert-comment.sh" "$PR" "<!-- pr-review -->" "$WORKDIR/comment.md"
