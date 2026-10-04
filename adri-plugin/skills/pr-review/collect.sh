#!/usr/bin/env bash
set -euo pipefail

# Gather everything a review needs into a work directory (see collect.py).
#
#   ./collect.sh [PR#] [--ci-file ci.json]
#
# A thin wrapper: the logic is Python and talks to GitHub through ghapi.py, so it
# runs the same with `gh` (a developer's machine) and without it (a cloud routine).

exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/collect.py" "$@"
