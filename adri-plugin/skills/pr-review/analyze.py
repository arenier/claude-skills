#!/usr/bin/env python3
"""Mechanical facts about a PR, from the files collect.sh gathered.

    python3 analyze.py <workdir>

Everything here is deterministic: stop conditions, size thresholds, title
form, CI state, and the profile-driven lookups. Deciding whether a hit is a
finding is left to the reviewer.

Nothing in this file knows a repository. What is specific to one (which
decisions govern which paths, which APIs are ruled out, which extra checks to
run) comes from the repo's own profile, `.claude/pr-review.json`, which
collect.sh copies to <workdir>/profile.json from the PR's base branch. Without
a profile the skill still works, on the generic checks only. See
`PROFILE.md` for the format.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONVENTIONAL = HERE / "../../scripts/conventional.sh"

# Generic: how to tell a test file, and a source file, in the usual ecosystems.
DEFAULT_TESTS = {
    "source": r"\.(?:[jt]sx?|py|go|rs|rb|java|kt|php|cs)$",
    "test": r"(?:[._]|^|/)(?:spec|test)s?[._/]|(?:^|/)(?:tests?|__tests__)/|_test\.go$",
}
FAILING = {"FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "ERROR"}
PENDING = {"PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}
IMPORT = re.compile(r"""^\s*(?:import\b.*?from\s*|import\s*|export\b.*?from\s*|from\s+\S+\s+import\b)['"]?([^'"\s]+)['"]?|require\(\s*['"]([^'"]+)['"]\s*\)""")


def added_lines(patch):
    """Yield (path, new_line_number, text) for every added line of a diff."""
    path, line = None, 0
    for raw in patch.splitlines():
        if raw.startswith("+++ "):
            target = raw[4:]
            path = None if target == "/dev/null" else re.sub(r"^b/", "", target)
        elif raw.startswith("@@"):
            m = re.search(r"\+(\d+)", raw)
            line = int(m.group(1)) if m else 0
        elif path and raw.startswith("+"):
            yield path, line, raw[1:]
            line += 1
        elif path and raw.startswith(" "):
            line += 1


def zone(path):
    """Top-level area of a path: `dir/sub` under apps/ and libs/ style roots, else `dir`."""
    parts = path.split("/")
    if len(parts) > 2 and parts[0] in ("apps", "libs", "packages", "services", "plugins"):
        return f"{parts[0]}/{parts[1]}"
    return parts[0] if len(parts) > 1 else "racine"


def ci_state(rollup):
    if not rollup:
        return "non lancée"
    failing, pending = [], False
    for c in rollup:
        name = c.get("name") or c.get("context") or "?"
        conclusion = (c.get("conclusion") or c.get("state") or "").upper()
        status = (c.get("status") or "").upper()
        if conclusion in FAILING:
            failing.append(name)
        elif conclusion in PENDING or (status and status != "COMPLETED"):
            pending = True
    if failing:
        return "rouge sur " + ", ".join(f"`{n}`" for n in failing)
    return "en attente" if pending else "verte"


def title_check(title):
    r = subprocess.run([str(CONVENTIONAL), title], capture_output=True, text=True)
    if r.returncode == 0:
        return "conforme (forme) — l'impératif reste à juger"
    return "⚠️ non conforme : " + " · ".join(r.stdout.split("\n")).strip(" ·")


def tracked_files():
    r = subprocess.run(["git", "ls-files"], capture_output=True, text=True)
    return r.stdout.splitlines() if r.returncode == 0 else []


def main():
    workdir = Path(sys.argv[1])
    pr = json.loads((workdir / "pr.json").read_text())
    patch = (workdir / "diff.patch").read_text()
    profile_file = workdir / "profile.json"
    profile = json.loads(profile_file.read_text()) if profile_file.exists() else {}
    default_branch = (workdir / "default_branch").read_text().strip() if (workdir / "default_branch").exists() else "main"

    files = pr.get("files") or []
    paths = [f["path"] for f in files]
    size = pr["additions"] + pr["deletions"]
    added = list(added_lines(patch))
    out = []
    w = out.append

    w(f"# Faits mécaniques — PR #{pr['number']} · {pr['title']}\n")

    w("## Arrêts et signalements\n")
    author = (pr.get("author") or {}).get("login", "")
    labels = {label["name"].lower() for label in pr.get("labels") or []}
    stops = []
    if pr["state"] != "OPEN":
        stops.append(f"STOP : PR à l'état {pr['state']}, rien à relire.")
    if "dependabot" in author.lower() or labels & {"dependencies", "dependabot"}:
        stops.append("STOP : PR Dependabot, hors périmètre de ce skill. Le dire, sans fiche.")
    notes = []
    if pr["isDraft"]:
        notes.append("Draft : verdict indicatif.")
    if pr["baseRefName"] != default_branch:
        notes.append(f"Base `{pr['baseRefName']}` ≠ `{default_branch}` : PR empilée, le diff peut inclure la PR parente.")
    if not profile:
        notes.append("Aucun profil `.claude/pr-review.json` sur la base : seules les vérifications génériques s'appliquent. "
                     "Les conventions du dépôt se découvrent à la lecture (étape 3).")
    for line in stops + notes or ["Aucun."]:
        w(f"- {line}")

    w("\n## Taille et déclencheurs\n")
    zones = sorted({zone(p) for p in paths})
    w(f"- Périmètre : {len(paths)} fichiers · +{pr['additions']}/-{pr['deletions']} lignes · zones : {', '.join(zones)}")
    w("- Lecture : " + ("fichier par fichier (> 2000 lignes)" if size > 2000 else "d'un bloc"))
    fan_out = len(paths) > 40 or size > 2500
    w(f"- Fan-out : {'à PROPOSER (> 40 fichiers ou > 2500 lignes), attendre le go' if fan_out else 'non (relecture inline)'}")
    stakes_re = profile.get("stakes")
    stakes = [p for p in paths if stakes_re and re.search(stakes_re, p)]
    reasons = []
    if stakes:
        reasons.append(f"touche {', '.join(f'`{p}`' for p in stakes[:5])}{' …' if len(stakes) > 5 else ''}")
    if size > 300:
        reasons.append(f"{size} lignes (> 300)")
    w(f"- Second avis, critère d'enjeu : {'rempli — ' + ' ; '.join(reasons) if reasons else 'non rempli'} (le critère de doute reste à juger)")

    if profile.get("notes"):
        w("\n## Notes du dépôt\n")
        w(profile["notes"])

    w("\n## Titre Conventional Commits\n")
    w(f"- {title_check(pr['title'])}")

    w("\n## CI (read-only, ne colore pas le verdict)\n")
    w(f"- {ci_state(pr.get('statusCheckRollup'))}")

    w("\n## Décisions à confronter\n")
    index = profile.get("index") or ["CLAUDE.md", "AGENTS.md"]
    w(f"Toujours, s'ils existent : {', '.join(f'`{i}`' for i in index)}.")
    if profile.get("decisions"):
        w(f"Décisions actées : `{profile['decisions']}/`.")
    if profile.get("rules"):
        w(f"Rules : `{profile['rules']}/` — une rule dont le frontmatter `paths` cible un fichier du diff s'applique à ce fichier.")
    routes = profile.get("routes") or []
    if routes:
        w("\n| Fichier | À confronter |\n|---|---|")
        refs = set()
        for p in paths:
            hits = [r for r in routes if re.search(r["paths"], p)]
            for r in hits:
                refs.update(r.get("refs") or [])
            w(f"| `{p}` | {' · '.join(r['read'] for r in hits) if hits else '—'} |")
        w(f"\nÀ lire : {', '.join(sorted(refs)) or 'aucun routé'}")
    else:
        w("\nPas de routage chemin → décision : lire l'index puis chercher les décisions qui concernent les zones touchées.")

    for req in profile.get("required", []):
        for f in files:
            p = f["path"]
            if re.search(req["paths"], p):
                head = workdir / "head" / p
                if not (head.exists() and req["contains"] in head.read_text()):
                    w(f"\n⚠️ `{p}` : {req['label']}")

    w("\n## Vérifications hors-diff (résultats bruts, à juger)\n")
    n = 0

    zones_re = profile.get("import_zones")
    if zones_re:
        n += 1
        w(f"### {n}. Imports ajoutés dans les zones contraintes\n")
        hits = []
        for p, ln, text in added:
            if re.search(zones_re, p):
                m = IMPORT.search(text)
                if m:
                    hits.append(f"- `{p}:{ln}` → `{m.group(1) or m.group(2)}`")
        w("\n".join(hits) or "rien")
        w("")

    n += 1
    w(f"### {n}. Jumeaux\n")
    w("jugement : chercher la signature du défaut corrigé dans tout le repo (`grep -rn`).\n")

    n += 1
    w(f"### {n}. Tests des fichiers source touchés\n")
    tests = {**DEFAULT_TESTS, **(profile.get("tests") or {})}
    test_files = {p for p in paths if re.search(tests["test"], p)}
    local = [t for t in tracked_files() if re.search(tests["test"], t)]
    rows = []
    for p in paths:
        if not re.search(tests["source"], p) or p in test_files:
            continue
        base = Path(p).name.split(".")[0]
        touched = any(base in Path(t).name for t in test_files)
        existing = any(base in Path(t).name for t in local)
        rows.append(f"- `{p}` — test touché : {'oui' if touched else 'non'} · test existant (checkout local) : {'oui' if existing else 'non'}")
    w("\n".join(rows) or "aucun fichier source touché")
    w("")

    locked = profile.get("locked") or []
    if locked:
        n += 1
        w(f"### {n}. Interdits du dépôt (lignes ajoutées)\n")
        hits = []
        for p, ln, text in added:
            for rule in locked:
                if rule.get("paths") and not re.search(rule["paths"], p):
                    continue
                if rule.get("ignore") and re.search(rule["ignore"], text.strip()):
                    continue
                if re.search(rule["pattern"], text):
                    hits.append(f"- `{p}:{ln}` — {rule['label']} — `{text.strip()[:100]}`")
        w("\n".join(hits) or "rien")
        w("")

    for pair in profile.get("companions", []):
        n += 1
        w(f"### {n}. {pair['label']}\n")
        changed = [p for p in paths if re.search(pair["changed"], p) and not (pair.get("except") and re.search(pair["except"], p))]
        companions = [p for p in paths if re.search(pair["companion"], p)]
        w(f"- Touchés : {', '.join(f'`{p}`' for p in changed) or 'aucun'}")
        w(f"- Accompagnement : {', '.join(f'`{p}`' for p in companions) or 'aucun'}")
        if changed and not companions:
            w(f"- ⚠️ {pair['warning']}")
        if pair.get("judge"):
            w(f"\njugement : {pair['judge']}")
        if pair.get("if_confirmed"):
            w(f"Si confirmé : {pair['if_confirmed']}")
        w("")

    for check in profile.get("checks", []):
        n += 1
        w(f"### {n}. {check['label']}\n")
        w(f"jugement : {check['judge']}")
        if check.get("if_confirmed"):
            w(f"Si confirmé : {check['if_confirmed']}")
        w("")

    print("\n".join(out))


if __name__ == "__main__":
    main()
