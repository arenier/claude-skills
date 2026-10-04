#!/usr/bin/env bash
set -euo pipefail

# Targeted local checks, with the repository left exactly as found.
#
#   ./local-gate.sh status [workdir]
#   ./local-gate.sh checkout <PR#> --go -- <command...>
#   ./local-gate.sh worktree <PR#> --go -- <command...>
#
# status     Read-only. Does the current checkout measure the PR (branch == the PR's
#            headRefName)? Is the tree clean? Which scripts does package.json offer?
#            A command run on a checkout that is not the PR branch says nothing about
#            the PR: status says so before anything is run.
# checkout   Checks the PR branch out, runs the command, ALWAYS restores the starting
#            branch (success, failure or interrupt). Refuses on a dirty tree.
# worktree   Same, in an isolated worktree (a fresh one has no node_modules: the
#            command must install if it needs to). Always removed afterwards.
#
# `--go` is mandatory for checkout and worktree: it records that the user gave an
# explicit go for something costly. The cost itself (SKILL.md, references/local-gates.md)
# is announced BEFORE this runs.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cmd="${1:-}"
shift || true

case "$cmd" in
  status)
    WORKDIR="${1:-}"
    current="$(git rev-parse --abbrev-ref HEAD)"
    echo "Branche courante : ${current}"
    if [[ -n "$WORKDIR" && -f "$WORKDIR/pr.json" ]]; then
      head_ref="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["headRefName"])' "$WORKDIR/pr.json")"
      if [[ "$current" == "$head_ref" ]]; then
        echo "Checkout courant = branche de la PR (\`${head_ref}\`) : une vérification locale mesure bien la PR."
      else
        echo "⚠️ Checkout courant ≠ branche de la PR (\`${head_ref}\`) : une vérification locale ne dit RIEN de la PR. Ne pas la lancer, l'écrire dans la fiche."
      fi
    fi
    if [[ -z "$(git status --porcelain)" ]]; then echo "Arbre de travail : propre."; else echo "Arbre de travail : NON propre (checkout refusé tant qu'il l'est)."; fi
    if [[ -f package.json ]]; then
      echo "Scripts de package.json :"
      python3 - <<'PY'
import json
for name, command in sorted((json.load(open("package.json")).get("scripts") or {}).items()):
    print(f"  {name}: {command[:100]}")
PY
    fi
    ;;

  checkout|worktree)
    PR="${1:-}"; shift || true
    [[ "$PR" =~ ^[0-9]+$ ]] || { echo "usage: $0 $cmd <PR#> --go -- <command...>" >&2; exit 2; }
    [[ "${1:-}" == "--go" ]] || { echo "refus : --go absent (go explicite de l'utilisateur requis pour une vérification coûteuse)." >&2; exit 2; }
    shift
    [[ "${1:-}" == "--" ]] || { echo "usage: $0 $cmd <PR#> --go -- <command...>" >&2; exit 2; }
    shift
    (( $# > 0 )) || { echo "aucune commande à lancer." >&2; exit 2; }

    if [[ "$cmd" == "checkout" ]]; then
      if [[ -n "$(git status --porcelain)" ]]; then
        echo "Arbre de travail non propre. Commit/stash tes changements avant que je checkoute la PR." >&2
        exit 1
      fi
      start="$(git rev-parse --abbrev-ref HEAD)"
      restore() { git checkout -q "$start" 2>/dev/null || true; }
      trap restore EXIT
      gh pr checkout "$PR"
      "$@"
    else
      WT="${PR_REVIEW_WT_DIR:-${TMPDIR:-/tmp}}/pr-review-wt-${PR}"
      cleanup() { git worktree remove "$WT" --force 2>/dev/null || true; git branch -D "pr-${PR}" >/dev/null 2>&1 || true; }
      trap cleanup EXIT
      git fetch -q origin "pull/${PR}/head:pr-${PR}"
      git worktree add -q "$WT" "pr-${PR}"
      (cd "$WT" && "$@")
    fi
    ;;

  *)
    sed -n '3,22p' "${BASH_SOURCE[0]}" >&2
    exit 2
    ;;
esac
