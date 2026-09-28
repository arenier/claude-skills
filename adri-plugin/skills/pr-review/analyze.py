#!/usr/bin/env python3
"""Mechanical facts about a PR, from the files collect.sh gathered.

    python3 analyze.py <workdir>

Everything here is deterministic: stop conditions, size thresholds, title
form, CI state, the path -> ADR routing table, and grep-level hits for the
off-diff checks. Deciding whether a hit is a finding is left to the reviewer.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONVENTIONAL = HERE / "../../scripts/conventional.sh"

# Path pattern -> ADRs that govern it. Order matters only for display.
ROUTES = [
    (r"^libs/shared/", "0002 (lib partagée : n'importe aucun contexte, pas de common/utils)"),
    (r"^libs/[^/]+/domain/", "0002 (domain : ne dépend de rien, value objects)"),
    (r"^libs/[^/]+/application/", "0002 (dépend du domain seul, parle aux ports) · 0003 (pas d'event bus)"),
    (r"^libs/[^/]+/infrastructure/", "0002 (personne n'en dépend hors composition root) · 0006 (SQL, schéma, migrations ici)"),
    (r"^apps/api/", "0003 (seul module multi-contextes, DTO de frontière, aucune règle métier)"),
    (r"^apps/web/", "0002 (feature-slice : pas d'import dans une autre slice)"),
    (r"(?i)(vlm|shelf-?scanner)", "0005 (derrière ShelfScannerPort, tests sur réponses enregistrées)"),
    (r"(^|/)(package\.json|yarn\.lock|\.yarnrc\.yml|\.nvmrc|\.node-version)$", "0001 (Yarn 4, pins exacts, nodeLinker node-modules)"),
    (r"(^|/)(vite|vitest)\.config\.", "0007 (Vite/Vitest, SWC pour apps/api)"),
    (r"(^|/)(docker-compose[^/]*\.ya?ml|Dockerfile)$|(^|/)deploy[^/]*$", "0004 (Cloud Run + bucket) · 0006 (Postgres managé, pas de gcsfuse/SQLite)"),
]

# Signatures of APIs the ADRs rule out, looked for in added lines.
LOCKED = [
    (r"@nestjs/cqrs|@nestjs/event-emitter|\bEventEmitter\b", "event bus -> ADR 0003"),
    (r"\bjest\b|@jest/", "Jest -> ADR 0007"),
    (r"\bwebpack\b", "webpack -> ADR 0007"),
    (r"nodeLinker:\s*pnp|\bpnp\b", "PnP -> ADR 0001"),
    (r"yarn@1\.|\"yarn\":\s*\"1\.", "Yarn Classic -> ADR 0001"),
    (r"(?i)gcsfuse|sqlite", "gcsfuse / SQLite comme base -> ADR 0006"),
]
VERSION_RANGE = re.compile(r'"[^"]+"\s*:\s*"[\^~><*]')
IMPORT = re.compile(r"""^\s*(?:import\b.*?from\s*|import\s*|export\b.*?from\s*)['"]([^'"]+)['"]|require\(\s*['"]([^'"]+)['"]\s*\)""")
AS_CAST = re.compile(r"\bas\s+(?!const\b)[\w{\[(<]")
FAILING = {"FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "ERROR"}
PENDING = {"PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}


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
    parts = path.split("/")
    if parts[0] in ("apps", "libs") and len(parts) > 1:
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


def main():
    workdir = Path(sys.argv[1])
    pr = json.loads((workdir / "pr.json").read_text())
    patch = (workdir / "diff.patch").read_text()
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
    if pr["baseRefName"] != "main":
        notes.append(f"Base `{pr['baseRefName']}` ≠ main : PR empilée, le diff peut inclure la PR parente.")
    for line in stops + notes or ["Aucun."]:
        w(f"- {line}")

    w("\n## Taille et déclencheurs\n")
    zones = sorted({zone(p) for p in paths})
    w(f"- Périmètre : {len(paths)} fichiers · +{pr['additions']}/-{pr['deletions']} lignes · zones : {', '.join(zones)}")
    w("- Lecture : " + ("fichier par fichier (> 2000 lignes)" if size > 2000 else "d'un bloc"))
    fan_out = len(paths) > 40 or size > 2500
    w(f"- Fan-out : {'à PROPOSER (> 40 fichiers ou > 2500 lignes), attendre le go' if fan_out else 'non (relecture inline)'}")
    stakes = [p for p in paths if re.search(r"(?i)vlm|shelf-?scanner|/infrastructure/|migration|schema|postgres", p)]
    reasons = []
    if stakes:
        reasons.append(f"touche {', '.join(f'`{p}`' for p in stakes[:5])}{' …' if len(stakes) > 5 else ''}")
    if size > 300:
        reasons.append(f"{size} lignes (> 300)")
    w(f"- Second avis, critère d'enjeu : {'rempli — ' + ' ; '.join(reasons) if reasons else 'non rempli'} (le critère de doute reste à juger)")

    w("\n## Titre Conventional Commits\n")
    w(f"- {title_check(pr['title'])}")

    w("\n## CI (read-only, ne colore pas le verdict)\n")
    w(f"- {ci_state(pr.get('statusCheckRollup'))}")

    w("\n## Routage ADR\n")
    w("Toujours : `CLAUDE.md`.\n")
    w("| Fichier | À confronter |\n|---|---|")
    adrs = set()
    for p in paths:
        hits = [label for pattern, label in ROUTES if re.search(pattern, p)]
        adrs.update(re.findall(r"\b000\d\b", " ".join(hits)))
        w(f"| `{p}` | {' · '.join(hits) if hits else '—'} |")
    for f in files:
        p = f["path"]
        if re.match(r"^(apps|libs)/.+/package\.json$", p):
            head = workdir / "head" / p
            tagged = head.exists() and '"tags"' in head.read_text()
            if not tagged:
                w(f"\n⚠️ `{p}` : pas de `nx.tags` trouvés — un projet sans tags échappe aux frontières.")
    w(f"\nADR à lire : {', '.join(sorted(adrs)) or 'aucun routé (lire CLAUDE.md)'}")

    w("\n## Vérifications hors-diff (résultats bruts, à juger)\n")

    w("### 1. Imports ajoutés dans domain / application\n")
    hits = []
    for p, n, text in added:
        if re.match(r"^libs/[^/]+/(domain|application)/", p):
            m = IMPORT.search(text)
            if m:
                hits.append(f"- `{p}:{n}` → `{m.group(1) or m.group(2)}`")
    w("\n".join(hits) or "rien")

    w("\n### 2. Jumeaux\n")
    w("jugement : chercher la signature du défaut corrigé dans tout le repo (`grep -rn`).")

    w("\n### 3. Specs des fichiers source touchés\n")
    specs = {p for p in paths if re.search(r"\.(spec|test)\.[jt]sx?$", p)}
    rows = []
    for p in paths:
        if not re.search(r"\.[jt]sx?$", p) or p in specs:
            continue
        stem = re.sub(r"\.[jt]sx?$", "", p)
        touched = any(s.startswith(stem + ".") for s in specs)
        local = any(Path(stem + ext).exists() for ext in (".spec.ts", ".spec.tsx", ".test.ts", ".test.tsx"))
        rows.append(f"- `{p}` — spec touchée : {'oui' if touched else 'non'} · spec existante (checkout local) : {'oui' if local else 'non'}")
    w("\n".join(rows) or "aucun fichier source touché")

    w("\n### 4. Schéma / entité ↔ migration\n")
    schema = [p for p in paths if "/infrastructure/" in p and re.search(r"(?i)entit|schema|table|model", p) and "migration" not in p.lower()]
    migrations = [p for p in paths if "migration" in p.lower()]
    w(f"- Entités / schéma touchés : {', '.join(f'`{p}`' for p in schema) or 'aucun'}")
    w(f"- Migrations touchées : {', '.join(f'`{p}`' for p in migrations) or 'aucune'}")
    if schema and not migrations:
        w("- ⚠️ schéma touché SANS migration dans le diff → 🔴 si confirmé (ADR 0006)")

    w("\n### 5. APIs verrouillées (lignes ajoutées)\n")
    hits = []
    for p, n, text in added:
        for pattern, label in LOCKED:
            if re.search(pattern, text):
                hits.append(f"- `{p}:{n}` — {label} — `{text.strip()[:100]}`")
        if p.endswith("package.json") and VERSION_RANGE.search(text):
            hits.append(f"- `{p}:{n}` — plage de version -> ADR 0001 — `{text.strip()[:100]}`")
    w("\n".join(hits) or "rien")

    w("\n### 6. Assertions `as` (lignes ajoutées, hors `as const`)\n")
    hits = []
    for p, n, text in added:
        if not re.search(r"\.tsx?$", p):
            continue
        stripped = text.strip()
        if re.match(r"^(import|export)\b|^(//|\*|/\*)", stripped):
            continue
        if AS_CAST.search(stripped):
            hits.append(f"- `{p}:{n}` — `{stripped[:100]}`")
    w("\n".join(hits) or "rien")

    print("\n".join(out))


if __name__ == "__main__":
    main()
