#!/usr/bin/env python3
"""One GitHub transport for every script of the skill: `gh` when it is there, else the REST API.

A cloud routine has no `gh`, only `curl` and an ambient installation token
(`GITHUB_TOKEN` / `GH_TOKEN`). The scripts must run the same in both places, so
they never call `gh` themselves: they call `api()` here.

    from ghapi import api, repo, default_branch

Endpoints use the `{owner}` / `{repo}` placeholders, filled in from
`CCR_TRIGGER_REPO`, else the current git remote, else `gh repo view`.

Reading uses `gh` when it is installed and authenticated (the user's own
credentials), the token otherwise. Writing is a separate decision made by the
caller: `api(..., transport="token")` forces the token, which is how a routine
posts as `claude[bot]` rather than as a person.
"""
import functools
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

API = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")


class GitHubError(RuntimeError):
    def __init__(self, status, endpoint, body=""):
        super().__init__(f"GitHub {status} sur {endpoint} : {body[:200]}")
        self.status = status


def token():
    return os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""


@functools.lru_cache(maxsize=1)
def has_gh():
    if os.environ.get("PR_REVIEW_TRANSPORT") == "token" or not shutil.which("gh"):
        return False
    return subprocess.run(["gh", "auth", "status"], capture_output=True).returncode == 0


def repo():
    """(owner, name) of the repository under review."""
    slug = os.environ.get("CCR_TRIGGER_REPO", "")
    if not slug:
        r = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True)
        m = re.search(r"github\.com[:/]+([^/]+)/([^/]+?)(?:\.git)?/?$", r.stdout.strip())
        slug = f"{m.group(1)}/{m.group(2)}" if m else ""
    if "/" not in slug and shutil.which("gh"):
        r = subprocess.run(["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"], capture_output=True, text=True)
        slug = r.stdout.strip()
    if "/" not in slug:
        raise GitHubError(0, "repo", "dépôt introuvable : ni CCR_TRIGGER_REPO, ni remote git, ni gh")
    owner, name = slug.split("/", 1)
    return owner, name


def _fill(endpoint):
    if "{owner}" in endpoint or "{repo}" in endpoint:
        owner, name = repo()
        endpoint = endpoint.replace("{owner}", owner).replace("{repo}", name)
    return endpoint


def api(endpoint, *, raw=False, diff=False, method="GET", data=None, transport="auto"):
    """Call the API and return the decoded JSON, or the text with raw=True / diff=True.

    transport: "auto" (gh if usable, else token), "gh", or "token".
    """
    endpoint = _fill(endpoint)
    use_gh = transport == "gh" or (transport == "auto" and has_gh())
    accept = "application/vnd.github.v3.diff" if diff else "application/vnd.github.raw" if raw else "application/vnd.github+json"
    if use_gh:
        cmd = ["gh", "api", "-H", f"Accept: {accept}", "-X", method, endpoint]
        if data is not None:
            cmd += ["--input", "-"]
        r = subprocess.run(cmd, input=json.dumps(data) if data is not None else None, capture_output=True, text=True)
        if r.returncode != 0:
            raise GitHubError(1, endpoint, r.stderr)
        text = r.stdout
    else:
        if not token():
            raise GitHubError(0, endpoint, "ni gh authentifié, ni GITHUB_TOKEN / GH_TOKEN")
        url = endpoint if endpoint.startswith("http") else f"{API}/{endpoint.lstrip('/')}"
        req = urllib.request.Request(url, method=method, headers={
            "Authorization": f"Bearer {token()}", "Accept": accept, "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "pr-review-skill"})
        if data is not None:
            req.data = json.dumps(data).encode()
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                text = resp.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as e:
            raise GitHubError(e.code, endpoint, e.read().decode("utf-8", errors="replace")) from None
    if raw or diff:
        return text
    return json.loads(text) if text.strip() else None


def paginate(endpoint, transport="auto"):
    """Every page of a list endpoint (100 per page)."""
    out, page = [], 1
    sep = "&" if "?" in endpoint else "?"
    while True:
        batch = api(f"{endpoint}{sep}per_page=100&page={page}", transport=transport)
        out += batch
        if len(batch) < 100:
            return out
        page += 1


def default_branch():
    return api("repos/{owner}/{repo}")["default_branch"]


if __name__ == "__main__":
    # Smoke test: python3 ghapi.py repos/{owner}/{repo}
    print(json.dumps(api(sys.argv[1]), indent=2)[:2000])
