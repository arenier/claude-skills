#!/usr/bin/env python3
"""Discover a repository's own written rules and route a diff to them.

    python3 rules.py fetch <workdir> <base-ref>     # collect.sh calls this
    python3 rules.py route <workdir>                # debugging: print the routing

The skill carries no criterion of its own: the review criteria are whatever the
reviewed repo wrote down. This module finds them, from the BASE branch (never
the branch under review, whose author could rewrite the rules that judge it):

  - `.claude/rules/**/*.md`        Claude Code rules, `paths:` frontmatter
  - `.github/instructions/**`      Copilot instructions, `applyTo:` frontmatter
  - `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`   the indexes
  - the Markdown docs those indexes link to (ADR, guides), one level deep
  - a commitlint config, if there is one

`fetch` copies them under <workdir>/rules/ at their repo paths. A rule whose
frontmatter globs match a touched path applies to that path; a rule without
`paths` / `applyTo` applies everywhere.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

INDEXES = ["CLAUDE.md", "AGENTS.md", ".github/copilot-instructions.md"]
RULE_GLOBS = [r"^\.claude/rules/.+\.md$", r"^\.github/instructions/.+\.md$"]
COMMITLINT = re.compile(r"^(commitlint\.config\.[cm]?[jt]s|\.commitlintrc(\.[a-z]+)?)$")
LINK = re.compile(r"\]\(([^)#\s]+\.md)(?:#[^)]*)?\)")
MAX_DOCS = 80


def gh_api(endpoint, raw=False):
    cmd = ["gh", "api"] + (["-H", "Accept: application/vnd.github.raw"] if raw else []) + [endpoint]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def tree(base_ref):
    out = gh_api(f"repos/{{owner}}/{{repo}}/git/trees/{base_ref}?recursive=1")
    if not out:
        return []
    return [e["path"] for e in json.loads(out).get("tree", []) if e.get("type") == "blob"]


def fetch_file(path, base_ref):
    from urllib.parse import quote
    return gh_api(f"repos/{{owner}}/{{repo}}/contents/{quote(path)}?ref={base_ref}", raw=True)


def resolve(index_path, target):
    """A link target, relative to the file that holds it, as a repo path."""
    if target.startswith(("http://", "https://", "mailto:")):
        return None
    base = Path(index_path).parent
    parts = []
    for part in (base / target.lstrip("/") if not target.startswith("/") else Path(target.lstrip("/"))).parts:
        if part == "..":
            if not parts:
                return None
            parts.pop()
        elif part != ".":
            parts.append(part)
    return "/".join(parts)


def fetch(workdir, base_ref):
    workdir = Path(workdir)
    out = workdir / "rules"
    out.mkdir(parents=True, exist_ok=True)
    paths = tree(base_ref)
    present = set(paths)
    wanted = [p for p in paths if any(re.match(g, p) for g in RULE_GLOBS)]
    wanted += [i for i in INDEXES if i in present]
    wanted += [p for p in paths if "/" not in p and COMMITLINT.match(p)]
    fetched = {}
    for p in wanted:
        body = fetch_file(p, base_ref)
        if body is not None:
            fetched[p] = body
    # Docs the indexes and rules point to: ADR, guides, policies. One level deep.
    linked = []
    for p, body in list(fetched.items()):
        if not p.endswith(".md"):
            continue
        for target in LINK.findall(body):
            doc = resolve(p, target)
            if doc and doc in present and doc not in fetched and doc not in linked:
                linked.append(doc)
    for doc in linked[:MAX_DOCS]:
        body = fetch_file(doc, base_ref)
        if body is not None:
            fetched[doc] = body
    for p, body in fetched.items():
        dest = out / p
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(body)
    (workdir / "rules.json").write_text(json.dumps({
        "base_ref": base_ref,
        "rules": sorted(p for p in fetched if any(re.match(g, p) for g in RULE_GLOBS)),
        "indexes": [i for i in INDEXES if i in fetched],
        "docs": sorted(set(fetched) - {p for p in fetched if any(re.match(g, p) for g in RULE_GLOBS)} - set(INDEXES)),
        "commitlint": [p for p in fetched if COMMITLINT.match(p)],
        "skipped_docs": max(0, len(linked) - MAX_DOCS),
    }, indent=2))
    return fetched


def frontmatter_globs(text):
    """The path globs a rule declares: `paths:` (list) or `applyTo:` (comma list), else []."""
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return []
    block = m.group(1)
    globs = []
    apply = re.search(r"^applyTo:\s*(.+)$", block, re.M)
    if apply:
        globs += [g.strip().strip("\"'") for g in apply.group(1).split(",") if g.strip()]
    paths = re.search(r"^paths:\s*\n((?:\s+-\s*.+\n?)+)", block, re.M)
    if paths:
        globs += [re.sub(r"^\s*-\s*", "", line).strip().strip("\"'") for line in paths.group(1).splitlines() if line.strip()]
    return globs


def expand_braces(glob):
    m = re.search(r"\{([^{}]*)\}", glob)
    if not m:
        return [glob]
    return [x for alt in m.group(1).split(",") for x in expand_braces(glob[:m.start()] + alt + glob[m.end():])]


def glob_to_regex(glob):
    out, i = "", 0
    while i < len(glob):
        c = glob[i]
        if glob.startswith("**/", i):
            out += "(?:.*/)?"; i += 3
        elif glob.startswith("**", i):
            out += ".*"; i += 2
        elif c == "*":
            out += "[^/]*"; i += 1
        elif c == "?":
            out += "[^/]"; i += 1
        else:
            out += re.escape(c); i += 1
    return re.compile("^" + out + "$")


def matches(globs, path):
    return any(glob_to_regex(x).match(path) for g in globs for x in expand_braces(g))


def route(workdir, paths):
    """For each touched path, the rule files that apply. Rules without globs apply everywhere."""
    workdir = Path(workdir)
    meta = json.loads((workdir / "rules.json").read_text()) if (workdir / "rules.json").exists() else {"rules": []}
    routed = {p: [] for p in paths}
    everywhere = []
    for rule in meta["rules"]:
        globs = frontmatter_globs((workdir / "rules" / rule).read_text())
        if not globs:
            everywhere.append(rule)
            continue
        for p in paths:
            if matches(globs, p):
                routed[p].append(rule)
    return routed, everywhere, meta


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "fetch":
        got = fetch(sys.argv[2], sys.argv[3])
        print(f"{len(got)} fichier(s) de règles lus sur {sys.argv[3]}", file=sys.stderr)
    elif cmd == "route":
        wd = Path(sys.argv[2])
        pr = json.loads((wd / "pr.json").read_text())
        routed, everywhere, _ = route(wd, [f["path"] for f in pr.get("files") or []])
        print(json.dumps({"routed": routed, "everywhere": everywhere}, indent=2, ensure_ascii=False))
    else:
        print(__doc__)
        sys.exit(2)
