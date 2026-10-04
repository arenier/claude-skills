#!/usr/bin/env bash
set -euo pipefail

# Gather everything a review needs, into a work directory:
#
#   pr.json      metadata (title, author, state, base/head, files, commits, CI)
#   diff.patch   the full diff
#   head/<path>  every touched file in its PR (or branch) version
#   rules/       the repo's own written rules, READ FROM THE BASE BRANCH so the
#                author of the change cannot rewrite the rules that judge it
#                (.claude/rules/**, .github/instructions/**, CLAUDE.md /
#                AGENTS.md, the docs they link to, a commitlint config)
#   rules.json   what was found there
#   facts.md     mechanical facts: stop conditions, size, title, CI, which rule
#                applies to which touched path, grep-level hits
#
#   ./collect.sh [PR#]
#
# PR mode (a number): reviews that PR.
# Local mode (no number): reviews the current branch against the default branch,
# before it is pushed. Refused on the default branch itself.
#
# Read-only on GitHub and on the working tree: nothing needs a clean tree.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR="${1:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "\`gh\` (GitHub CLI) requis. Installation : \`brew install gh\`." >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "\`gh\` installé mais non authentifié. Lance \`gh auth login\` puis relance." >&2
  exit 1
fi

# Never assume `main` / `master`.
DEFAULT="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null \
  || git remote show origin | sed -n 's/.*HEAD branch: //p')"

if [[ -n "$PR" ]]; then
  WORKDIR="${PR_REVIEW_DIR:-${TMPDIR:-/tmp}/pr-review-${PR}}"
else
  BRANCH="$(git branch --show-current)"
  if [[ -z "$BRANCH" || "$BRANCH" == "$DEFAULT" ]]; then
    echo "Tu es sur la branche par défaut, il n'y a rien à relire. Précise un numéro de PR : /pr-review <PR#>." >&2
    exit 1
  fi
  git fetch -q origin "$DEFAULT"
  WORKDIR="${PR_REVIEW_DIR:-${TMPDIR:-/tmp}/pr-review-${BRANCH//\//-}}"
fi
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/head"
echo "$DEFAULT" > "$WORKDIR/default_branch"

if [[ -n "$PR" ]]; then
  gh pr view "$PR" --json number,title,body,author,state,isDraft,baseRefName,headRefName,headRefOid,additions,deletions,files,commits,statusCheckRollup,labels \
    > "$WORKDIR/pr.json"
  gh pr diff "$PR" > "$WORKDIR/diff.patch"
  # A red job: its cause decides whether a finding exists, so fetch the failing log tail now.
  for run in $(python3 - "$WORKDIR/pr.json" <<'PY'
import json, re, sys
seen = []
for c in json.load(open(sys.argv[1])).get("statusCheckRollup") or []:
    if (c.get("conclusion") or c.get("state") or "").upper() in {"FAILURE", "TIMED_OUT", "ERROR", "STARTUP_FAILURE"}:
        m = re.search(r"/actions/runs/(\d+)", c.get("detailsUrl") or c.get("targetUrl") or "")
        if m and m.group(1) not in seen:
            seen.append(m.group(1))
print(" ".join(seen[:3]))
PY
  ); do
    gh run view "$run" --log-failed 2>/dev/null | tail -60 > "$WORKDIR/ci-${run}.log" || true
  done
  BASE_REF="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["baseRefName"])' "$WORKDIR/pr.json")"
  HEAD_SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["headRefOid"])' "$WORKDIR/pr.json")"

  # The local checkout is almost never the PR branch: reading a touched file from
  # disk would show the default branch's version and produce findings about code
  # the PR has already changed. Fetch each touched file at the PR head commit.
  missing=0
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    encoded="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$path")"
    mkdir -p "$WORKDIR/head/$(dirname "$path")"
    if ! gh api -H "Accept: application/vnd.github.raw" \
         "repos/{owner}/{repo}/contents/${encoded}?ref=${HEAD_SHA}" \
         > "$WORKDIR/head/$path" 2>/dev/null; then
      rm -f "$WORKDIR/head/$path"   # deleted by the PR
      missing=$((missing + 1))
    fi
  done < <(python3 -c 'import json,sys; [print(f["path"]) for f in json.load(open(sys.argv[1]))["files"]]' "$WORKDIR/pr.json")
else
  BASE_REF="$DEFAULT"
  MERGE_BASE="$(git merge-base HEAD "origin/$DEFAULT")"
  git diff "$MERGE_BASE"...HEAD > "$WORKDIR/diff.patch"
  python3 - "$MERGE_BASE" "$BRANCH" "$DEFAULT" "$(gh api user --jq .login 2>/dev/null || true)" > "$WORKDIR/pr.json" <<'PY'
import json, subprocess, sys
base, branch, default, login = sys.argv[1:5]
def git(*a): return subprocess.run(["git", *a], capture_output=True, text=True, check=True).stdout
adds = dels = 0
files = []
for line in git("diff", "--numstat", f"{base}...HEAD").splitlines():
    a, d, path = line.split("\t", 2)
    adds += int(a) if a.isdigit() else 0
    dels += int(d) if d.isdigit() else 0
    files.append({"path": path})
subjects = git("log", "--format=%s", f"{base}..HEAD").splitlines()
json.dump({
    "number": None, "title": subjects[0] if len(subjects) == 1 else branch, "body": "",
    "author": {"login": login}, "state": "OPEN", "isDraft": False,
    "baseRefName": default, "headRefName": branch, "headRefOid": git("rev-parse", "HEAD").strip(),
    "additions": adds, "deletions": dels, "files": files,
    "commits": [{"messageHeadline": s} for s in subjects], "statusCheckRollup": [], "labels": [],
}, sys.stdout)
PY
  missing=0
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    mkdir -p "$WORKDIR/head/$(dirname "$path")"
    if ! git show "HEAD:${path}" > "$WORKDIR/head/$path" 2>/dev/null; then
      rm -f "$WORKDIR/head/$path"
      missing=$((missing + 1))
    fi
  done < <(python3 -c 'import json,sys; [print(f["path"]) for f in json.load(open(sys.argv[1]))["files"]]' "$WORKDIR/pr.json")
fi

python3 "$HERE/rules.py" fetch "$WORKDIR" "$BASE_REF"
python3 "$HERE/analyze.py" "$WORKDIR" > "$WORKDIR/facts.md"

cat "$WORKDIR/facts.md"
echo ""
echo "Fichiers en version PR : ${WORKDIR}/head/ (${missing} supprimé(s))"
echo "Règles et docs lus sur la base : ${WORKDIR}/rules/"
echo "WORKDIR=${WORKDIR}"
