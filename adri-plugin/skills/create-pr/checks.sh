#!/usr/bin/env bash
set -uo pipefail

# Run the repo's lint and tests on what the branch affects, and keep the output
# so the Tests section quotes what was actually observed.
#
#   ./checks.sh
#
# Prints the tail of the output and a final `CHECKS=` line:
#   CHECKS=none    no package.json, nothing to run
#   CHECKS=passed  exit code 0
#   CHECKS=failed  anything else (the full log path is printed)

BASE_BRANCH="${BASE_BRANCH:-main}"

if [[ ! -f package.json ]]; then
  echo "Pas de package.json : ni lint ni test à lancer."
  echo "CHECKS=none"
  exit 0
fi

LOG="$(mktemp -t create-pr-checks.XXXXXX)"
yarn nx affected -t lint test --base="$BASE_BRANCH" >"$LOG" 2>&1
status=$?

tail -n 40 "$LOG"
echo ""
echo "sortie complète : ${LOG}"
if (( status == 0 )); then
  echo "CHECKS=passed"
else
  echo "CHECKS=failed (exit ${status})"
fi
exit "$status"
