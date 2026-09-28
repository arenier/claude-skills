#!/usr/bin/env bash
set -euo pipefail

# Post the triage reply, or update the one already on the PR: the same comment
# is updated at every round, so a reviewer who comes back reads one place.
#
#   ./reply.sh <PR#> [workdir]

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR="${1:-}"
[[ -z "$PR" ]] && { echo "usage: $0 <PR#> [workdir]" >&2; exit 2; }
WORKDIR="${2:-${PR_TRIAGE_DIR:-${TMPDIR:-/tmp}/pr-review-triage-${PR}}}"

exec "$HERE/../../scripts/upsert-comment.sh" "$PR" "<!-- pr-review-triage -->" "$WORKDIR/reply.md"
