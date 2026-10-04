#!/usr/bin/env python3
"""Gather everything a review needs, into a work directory.

    collect.py [PR#] [--ci-file ci.json]

  pr.json        metadata (title, author, state, base/head, files, commits, CI)
  diff.patch     the full diff
  head/<path>    every touched file in its PR (or branch) version
  rules/         the repo's own written rules, READ FROM THE BASE BRANCH so the
                 author of the change cannot rewrite the rules that judge it
  rules.json     what was found there
  ci-<run>.log   the tail of a failing run's log (only with `gh`)
  facts.md       mechanical facts (analyze.py)

PR mode (a number) reviews that PR. Local mode (no number) reviews the current
branch against the default branch, before it is pushed; refused on the default
branch itself. Read-only on GitHub and on the working tree.

Runs with `gh` or without it (a cloud routine has only the ambient token): every
call goes through ghapi.py. The CI state is read from the API; `--ci-file` takes a
JSON list of {name, conclusion, status} for a caller that read it another way (the
routine reads it through an MCP tool that the token cannot replace).
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import quote

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ghapi import GitHubError, api, default_branch, has_gh, paginate, repo  # noqa: E402
import rules  # noqa: E402

FAILING = {"FAILURE", "TIMED_OUT", "ERROR", "STARTUP_FAILURE"}


def git(*args, check=True):
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} : {r.stderr.strip()}")
    return r.stdout


def read_ci(sha, ci_file):
    """statusCheckRollup-shaped list, or (None, reason) when it cannot be read."""
    if ci_file:
        return json.loads(Path(ci_file).read_text()), None
    try:
        runs = api(f"repos/{{owner}}/{{repo}}/commits/{sha}/check-runs?per_page=100")["check_runs"]
        status = api(f"repos/{{owner}}/{{repo}}/commits/{sha}/status")["statuses"]
    except GitHubError as e:
        return None, str(e)
    rollup = [{"name": c["name"], "status": (c.get("status") or "").upper(), "conclusion": (c.get("conclusion") or "").upper(),
               "detailsUrl": c.get("details_url") or ""} for c in runs]
    rollup += [{"context": s["context"], "state": s["state"].upper(), "targetUrl": s.get("target_url") or ""} for s in status]
    return rollup, None


def pr_mode(number, workdir, ci_file):
    pr = api(f"repos/{{owner}}/{{repo}}/pulls/{number}")
    files = paginate(f"repos/{{owner}}/{{repo}}/pulls/{number}/files")
    commits = paginate(f"repos/{{owner}}/{{repo}}/pulls/{number}/commits")
    sha = pr["head"]["sha"]
    rollup, ci_error = read_ci(sha, ci_file)
    state = "MERGED" if pr.get("merged") else pr["state"].upper()
    meta = {
        "number": pr["number"], "title": pr["title"], "body": pr.get("body") or "",
        "author": {"login": (pr.get("user") or {}).get("login", "")}, "state": state, "isDraft": bool(pr.get("draft")),
        "baseRefName": pr["base"]["ref"], "headRefName": pr["head"]["ref"], "headRefOid": sha,
        "additions": pr["additions"], "deletions": pr["deletions"], "files": [{"path": f["filename"]} for f in files],
        "commits": [{"messageHeadline": c["commit"]["message"].splitlines()[0]} for c in commits],
        "statusCheckRollup": rollup, "labels": [{"name": label["name"]} for label in pr.get("labels") or []],
    }
    if ci_error:
        meta["ciError"] = ci_error
    (workdir / "pr.json").write_text(json.dumps(meta))
    (workdir / "diff.patch").write_text(api(f"repos/{{owner}}/{{repo}}/pulls/{number}", diff=True))

    # The local checkout is almost never the PR branch: reading a touched file from
    # disk would show the default branch's version and produce findings about code
    # the PR has already changed. Fetch each touched file at the PR head commit.
    missing = 0
    for f in files:
        dest = workdir / "head" / f["filename"]
        try:
            body = api(f"repos/{{owner}}/{{repo}}/contents/{quote(f['filename'])}?ref={sha}", raw=True)
        except GitHubError:
            missing += 1  # deleted by the PR, or too large for the contents API
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(body)

    if has_gh():  # a red job: its cause decides whether a finding exists
        runs = []
        for c in rollup or []:
            if (c.get("conclusion") or c.get("state") or "").upper() in FAILING:
                m = re.search(r"/actions/runs/(\d+)", c.get("detailsUrl") or c.get("targetUrl") or "")
                if m and m.group(1) not in runs:
                    runs.append(m.group(1))
        for run in runs[:3]:
            r = subprocess.run(["gh", "run", "view", run, "--log-failed"], capture_output=True, text=True)
            if r.returncode == 0:
                (workdir / f"ci-{run}.log").write_text("\n".join(r.stdout.splitlines()[-60:]) + "\n")
    return pr["base"]["ref"], missing


def local_mode(workdir, default):
    branch = git("branch", "--show-current").strip()
    if not branch or branch == default:
        raise SystemExit("Tu es sur la branche par défaut, il n'y a rien à relire. Précise un numéro de PR : /pr-review <PR#>.")
    git("fetch", "-q", "origin", default)
    base = git("merge-base", "HEAD", f"origin/{default}").strip()
    (workdir / "diff.patch").write_text(git("diff", f"{base}...HEAD"))
    adds = dels = 0
    files = []
    for line in git("diff", "--numstat", f"{base}...HEAD").splitlines():
        a, d, path = line.split("\t", 2)
        adds += int(a) if a.isdigit() else 0
        dels += int(d) if d.isdigit() else 0
        files.append({"path": path})
    subjects = git("log", "--format=%s", f"{base}..HEAD").splitlines()
    try:
        login = api("user")["login"]
    except GitHubError:
        login = ""
    (workdir / "pr.json").write_text(json.dumps({
        "number": None, "title": subjects[0] if len(subjects) == 1 else branch, "body": "", "author": {"login": login},
        "state": "OPEN", "isDraft": False, "baseRefName": default, "headRefName": branch,
        "headRefOid": git("rev-parse", "HEAD").strip(), "additions": adds, "deletions": dels, "files": files,
        "commits": [{"messageHeadline": s} for s in subjects], "statusCheckRollup": [], "labels": []}))
    missing = 0
    for f in files:
        r = subprocess.run(["git", "show", f"HEAD:{f['path']}"], capture_output=True, text=True)
        if r.returncode != 0:
            missing += 1
            continue
        dest = workdir / "head" / f["path"]
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(r.stdout)
    return default, missing


def main():
    args = sys.argv[1:]
    ci_file = None
    if "--ci-file" in args:
        i = args.index("--ci-file")
        ci_file = args[i + 1]
        del args[i:i + 2]
    number = args[0] if args else ""

    try:
        repo()  # fails early, with its reason, when there is no repository to talk to
        default = default_branch()
    except GitHubError:
        m = re.search(r"HEAD branch: (\S+)", git("remote", "show", "origin", check=False))
        default = m.group(1) if m else "main"

    if number:
        workdir = Path(os.environ.get("PR_REVIEW_DIR") or Path(os.environ.get("TMPDIR") or tempfile.gettempdir()) / f"pr-review-{number}")
    else:
        branch = git("branch", "--show-current").strip().replace("/", "-")
        workdir = Path(os.environ.get("PR_REVIEW_DIR") or Path(os.environ.get("TMPDIR") or tempfile.gettempdir()) / f"pr-review-{branch}")
    if workdir.exists():
        subprocess.run(["rm", "-rf", str(workdir)])
    (workdir / "head").mkdir(parents=True)
    (workdir / "default_branch").write_text(default + "\n")

    base_ref, missing = pr_mode(number, workdir, ci_file) if number else local_mode(workdir, default)
    got = rules.fetch(workdir, base_ref)
    print(f"{len(got)} fichier(s) de règles lus sur {base_ref}", file=sys.stderr)

    facts = subprocess.run([sys.executable, str(HERE / "analyze.py"), str(workdir)], capture_output=True, text=True)
    if facts.returncode != 0:
        raise SystemExit(facts.stderr)
    (workdir / "facts.md").write_text(facts.stdout)
    print(facts.stdout)
    print(f"Fichiers en version PR : {workdir}/head/ ({missing} supprimé(s) ou non lisibles)")
    print(f"Règles et docs lus sur la base : {workdir}/rules/")
    print(f"WORKDIR={workdir}")


if __name__ == "__main__":
    main()
