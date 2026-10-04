#!/usr/bin/env python3
"""Mechanical facts about a PR (or a branch), from the files collect.sh gathered.

    python3 analyze.py <workdir>

Everything here is deterministic: stop conditions, size thresholds, title form,
CI state, which of the repo's own rules apply to which touched path, and the
grep-level hits for the off-diff checks. Deciding whether a hit is a finding is
left to the reviewer.

Nothing in this file knows a repository. The criteria are whatever the reviewed
repo wrote in its rules (see rules.py); this script only routes the diff to them.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from rules import route  # noqa: E402

TITLE_SHAPE = re.compile(r"^[a-z]+(\([^)]+\))?!?: \S.*$")
FAILING = {"FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "ERROR"}
PENDING = {"PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}
TEST_FILE = re.compile(r"(?:[._]|^|/)(?:spec|test)s?[._/]|(?:^|/)(?:tests?|__tests__)/|_test\.go$")
SOURCE_FILE = re.compile(r"\.(?:[jt]sx?|py|go|rs|rb|java|kt|php|cs)$")
MIGRATION = re.compile(r"(?i)migration")
SCHEMA = re.compile(r"(?i)(entit(y|ies)|schema|\.model\.|/models?/|\.prisma$|\.sql$)")
CATALOG = re.compile(r"(?i)(^|/)(locales?|i18n|translations?|messages?|lang)(/|\.)|\.(po|xlf|arb)$")
ACCESS = re.compile(r"(?i)(auth|guard|permission|policy|acl|rbac|sso|realm)")
DESTRUCTIVE = re.compile(r"(?i)\b(DROP\s+(TABLE|COLUMN)|ALTER\s+TYPE|TRUNCATE|deleteAll|DELETE\s+FROM)\b")
LOCK_WORDS = re.compile(r"(?i)(interdit|verrouill|forbidden|locked|lock\b|ne pas utiliser|never use|must not|\bpas de\b|\bjamais\b|\bni\b|\bnever\b)")
PERF_WORDS = re.compile(r"(?i)(n\+1|dataloader|batch|performance|perf\b|over-?fetch)")
TENANT_WORDS = re.compile(r"(?i)(tenant|multi-?tenan|customerId|organi[sz]ationId|workspaceId)")
BACKTICK = re.compile(r"`([^`\n]+)`")
WHERE = re.compile(r"(?i)(\.where\(|\.andWhere\(|\.orWhere\(|\bWHERE\b|\bwhere:)")
LOOPING = re.compile(r"Promise\.all\(|\.(?:forEach|map)\(\s*async|for\s*\(.*\bof\b|for\s+await|while\s*\(")
KV = re.compile(r'^\s*["\']?([\w.\-]+)["\']?\s*[:=]\s*["\'](.*?)["\'],?\s*$')


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


def norm(value):
    """Catalog values compared without case, surrounding space or trailing punctuation."""
    return re.sub(r"[\s.!?:;…]+$", "", value.strip().casefold())


def json_duplicate_keys(text):
    """Keys defined twice in the same JSON object: the last one silently wins."""
    dups = []

    def hook(pairs):
        seen = set()
        for k, _ in pairs:
            if k in seen:
                dups.append(k)
            seen.add(k)
        return dict(pairs)

    try:
        json.loads(text, object_pairs_hook=hook)
    except ValueError:
        pass
    return dups


def tracked_files():
    r = subprocess.run(["git", "ls-files"], capture_output=True, text=True)
    return r.stdout.splitlines() if r.returncode == 0 else []


def zone(path):
    """Top-level area of a path: `dir/sub` under monorepo-style roots, else `dir`."""
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


def title_check(title, commitlint):
    """Shape only. The type and scope enums are the repo's own (its commitlint config)."""
    shape = "forme `type(scope): sujet` respectée" if TITLE_SHAPE.match(title) else "⚠️ forme `type(scope): sujet` non respectée"
    if commitlint:
        return f"{shape} · config `{commitlint[0]}` à lire pour l'enum de types et de scopes"
    return f"{shape} · pas de commitlint dans ce repo : forme seule vérifiée"


def main():
    workdir = Path(sys.argv[1])
    pr = json.loads((workdir / "pr.json").read_text())
    patch = (workdir / "diff.patch").read_text()
    default_branch = (workdir / "default_branch").read_text().strip() if (workdir / "default_branch").exists() else "main"
    local = pr.get("number") is None

    files = pr.get("files") or []
    paths = [f["path"] for f in files]
    size = pr["additions"] + pr["deletions"]
    added = list(added_lines(patch))
    routed, everywhere, meta = route(workdir, paths)
    out = []
    w = out.append

    subject = f"branche `{pr['headRefName']}` vs `{default_branch}`" if local else f"PR #{pr['number']} · {pr['title']}"
    w(f"# Faits mécaniques — {subject}\n")

    w("## Arrêts et signalements\n")
    author = (pr.get("author") or {}).get("login", "")
    labels = {label["name"].lower() for label in pr.get("labels") or []}
    stops, notes = [], []
    if not local and pr["state"] != "OPEN":
        stops.append(f"STOP : PR à l'état {pr['state']}, rien à relire.")
    if "dependabot" in author.lower() or labels & {"dependencies", "dependabot"}:
        stops.append("STOP : PR Dependabot, hors périmètre de ce skill. Le dire, sans fiche.")
    if pr["isDraft"]:
        notes.append("Draft : verdict indicatif.")
    if not local and pr["baseRefName"] != default_branch:
        notes.append(f"Base `{pr['baseRefName']}` ≠ `{default_branch}` : PR empilée, le diff peut inclure la PR parente.")
    if not meta["rules"] and not meta.get("indexes"):
        notes.append("Aucune règle écrite trouvée sur la base (ni `.claude/rules/**`, ni `.github/instructions/**`, ni `CLAUDE.md`) : "
                     "relecture sur l'intention, le titre et les catégories génériques seulement. Le dire dans la fiche.")
    for line in stops + notes or ["Aucun."]:
        w(f"- {line}")

    w("\n## Taille et déclencheurs\n")
    zones = sorted({zone(p) for p in paths})
    w(f"- Périmètre : {len(paths)} fichiers · +{pr['additions']}/-{pr['deletions']} lignes · zones : {', '.join(zones) or 'aucune'}")
    w("- Lecture : " + ("fichier par fichier (> 2000 lignes)" if size > 2000 else "d'un bloc"))
    volume = len(paths) > 40 or size > 2500
    w(f"- Fan-out : {'à PROPOSER (> 40 fichiers ou > 2500 lignes), attendre le go' if volume else 'non (relecture inline)'}")
    w("- Second avis, critères d'enjeu candidats (à confirmer par les règles du repo, ceux de doute restent à juger) :")
    hints = []
    if volume:
        hints.append("volume (> 40 fichiers ou > 2500 lignes)")
    access = [p for p in paths if ACCESS.search(p)]
    if access:
        hints.append("accès / permissions : " + ", ".join(f"`{p}`" for p in access[:4]))
    destructive = sorted({f"`{p}:{n}`" for p, n, t in added if DESTRUCTIVE.search(t)})
    if destructive:
        hints.append("écriture destructive : " + ", ".join(destructive[:4]))
    migrations = [p for p in paths if MIGRATION.search(p)]
    if migrations and not destructive:
        hints.append("migration touchée")
    for h in hints or ["aucun"]:
        w(f"  - {h}")

    w("\n## Titre\n")
    w(f"- {title_check(pr['title'], meta.get('commitlint'))}")

    w("\n## CI (read-only, ne colore pas le verdict)\n")
    w(f"- {ci_state(pr.get('statusCheckRollup'))}")
    for log in sorted(workdir.glob("ci-*.log")):
        w(f"- cause du job rouge : fin du log dans `{log}` (60 dernières lignes) — à lire pour décider s'il existe un constat")

    w("\n## Règles du dépôt à confronter\n")
    w("Source : la branche de base, jamais la branche relue. Ce sont **elles** les critères ; rien d'autre n'est reproché.\n")
    if meta.get("indexes"):
        w(f"- Index : {', '.join(f'`{i}`' for i in meta['indexes'])}")
    if meta["rules"]:
        w(f"- Règles lues sur la base ({len(meta['rules'])}) : {', '.join(f'`{r}`' for r in meta['rules'])}")
        if everywhere:
            w(f"- Sans `paths` (valent partout) : {', '.join(f'`{r}`' for r in everywhere)}")
        w("\n| Fichier touché | Règles qui s'y appliquent |\n|---|---|")
        for p in paths:
            w(f"| `{p}` | {', '.join(f'`{r}`' for r in routed[p]) or '—'} |")
    else:
        w("- Aucune règle `.claude/rules/**` ni `.github/instructions/**`.")
    if meta.get("docs"):
        w("")
        w(f"- Docs liés par l'index ou les règles, lus aussi sous `{workdir}/rules/` ({len(meta['docs'])}) : "
          + ", ".join(f"`{d}`" for d in meta["docs"][:12]) + (" …" if len(meta["docs"]) > 12 else ""))
    if meta.get("skipped_docs"):
        w(f"- ⚠️ {meta['skipped_docs']} doc(s) lié(s) non récupérés (plafond) : lire à la demande sur la base.")

    rule_texts = {r: (workdir / "rules" / r).read_text() for r in meta["rules"]}
    doc_texts = {d: (workdir / "rules" / d).read_text() for d in meta.get("docs", []) if (workdir / "rules" / d).exists()}
    all_texts = {**rule_texts, **doc_texts}

    def mentioning(rx):
        return [r for r, text in rule_texts.items() if rx.search(text)]

    def head_text(p):
        f = workdir / "head" / p
        return f.read_text(errors="replace") if f.exists() else ""

    w("\n## Vérifications hors-diff (résultats bruts, à juger)\n")
    w("Chacune ne s'applique que si les règles du repo la rendent pertinente ; la fiche dit ce qu'elle a donné, y compris « rien ». "
      "Les `grep` sont faits ici : il reste à confirmer chaque candidat par la lecture.\n")

    w("### 0. Fichiers déjà cités dans les règles ou les docs du dépôt (fichiers « brûlés »)\n")
    burned = []
    for p in paths:
        for name, text in all_texts.items():
            if p in text:
                burned.append(f"- `{p}` cité dans `{name}`")
    w("\n".join(burned[:30]) or "rien")
    w("")

    w("### 1. Jumeaux (fix-twins)\n")
    twins = [r for r in rule_texts if re.search(r"(?i)twin|jumeau", r + rule_texts[r][:400])]
    w(f"Règle du repo : {', '.join(f'`{r}`' for r in twins) if twins else 'aucune (pas de règle fix-twins)'}")
    w("jugement : déduire la **signature** du défaut corrigé (aucun script ne la connaît), puis la `grep` dans tout le repo et auditer chaque appelant.\n")

    w("### 2. Comportement verrouillé par un test ?\n")
    test_files = {p for p in paths if TEST_FILE.search(p)}
    local_tests = [t for t in tracked_files() if TEST_FILE.search(t) and t not in test_files]
    rows = []
    for p in paths:
        if not SOURCE_FILE.search(p) or p in test_files:
            continue
        base = Path(p).name.split(".")[0]
        touched = [t for t in test_files if base in Path(t).name or base in head_text(t)]
        mentioning_specs = []
        for t in local_tests:
            try:
                if re.search(rf"\b{re.escape(base)}\b", Path(t).read_text(errors="replace")):
                    mentioning_specs.append(t)
            except OSError:
                pass
        rows.append(f"- `{p}` — test touché : {', '.join(f'`{t}`' for t in touched[:3]) or 'non'} · "
                    f"specs existantes qui le mentionnent (checkout courant) : {', '.join(f'`{t}`' for t in mentioning_specs[:4]) or 'aucune'}"
                    f"{' …' if len(mentioning_specs) > 4 else ''}")
    w("\n".join(rows) or "aucun fichier source touché")
    w("\njugement : le test couvre-t-il le changement, **cas d'erreur** compris ? (Les specs existantes sont lues dans le checkout courant : identiques à la PR pour tout fichier non touché.)\n")

    w("### 3. Schéma / entité ↔ migration\n")
    schema = [p for p in paths if SCHEMA.search(p) and not MIGRATION.search(p)]
    w(f"- Schéma / entités candidats : {', '.join(f'`{p}`' for p in schema) or 'aucun'}")
    w(f"- Migrations touchées : {', '.join(f'`{p}`' for p in migrations) or 'aucune'}")
    w("- S'applique seulement si les règles du repo disent qu'il **écrit ses migrations** (un schéma vendoré n'en a pas : le dire).")
    if schema and not migrations:
        w("- ⚠️ schéma touché SANS migration dans le diff → 🔴 si le repo écrit ses migrations")
    w("")

    w("### 4. Clé de tenant dans chaque branche\n")
    tenant = mentioning(TENANT_WORDS)
    w(f"Règles qui parlent de tenant : {', '.join(f'`{r}`' for r in tenant) if tenant else 'aucune → non concerné'}")
    if tenant:
        keys = sorted({k for r in tenant for line in rule_texts[r].splitlines() if TENANT_WORDS.search(line)
                       for k in BACKTICK.findall(line) if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{2,}", k)})
        w(f"Clés candidates lues dans ces règles : {', '.join(f'`{k}`' for k in keys) or 'aucune identifiée'}")
        rows = []
        for p, n, text in added:
            if WHERE.search(text):
                has = any(re.search(rf"\b{re.escape(k)}\b", text) for k in keys)
                rows.append(f"- `{p}:{n}` — {'clé présente' if has else '⚠️ clé absente de la ligne'} — `{text.strip()[:100]}`")
        w("\n".join(rows[:30]) or "aucune clause `WHERE` ajoutée")
        w("jugement : une clé absente de la ligne peut venir d'un scope de base ; lire la méthode entière, et les lectures voisines du même service.")
    w("")

    w("### 5. API verrouillée ou interdite introduite\n")
    locks = mentioning(LOCK_WORDS)
    w(f"Règles qui verrouillent ou interdisent : {', '.join(f'`{r}`' for r in locks) if locks else 'aucune → non concerné'}")
    if locks:
        hits = []
        for r in locks:
            tokens = sorted({k for line in rule_texts[r].splitlines() if LOCK_WORDS.search(line) for k in BACKTICK.findall(line) if len(k) >= 3})
            for tok in tokens:
                pat = re.compile(r"(?<![\w.])" + re.escape(tok) + r"(?![\w])")
                for p, n, text in added:
                    if pat.search(text):
                        hits.append(f"- `{p}:{n}` — `{tok}` (cité par `{r}`) — `{text.strip()[:90]}`")
        w("\n".join(hits[:30]) or "aucune API citée comme interdite par ces règles n'apparaît dans les lignes ajoutées")
        if len(hits) > 30:
            w(f"- … +{len(hits) - 30} autres")
        w("jugement : les mots entre backticks des lignes d'interdit sont cherchés tels quels ; la ligne introduit-elle l'API, ou la mentionne-t-elle (commentaire, chaîne) ? Lire aussi la règle pour les interdits qu'aucun mot ne désigne.")
    w("")

    w("### 6. Performance / chargement de données\n")
    perf = mentioning(PERF_WORDS)
    w(f"Règles de performance : {', '.join(f'`{r}`' for r in perf) if perf else 'aucune → non concerné'}")
    if perf:
        rows = [f"- `{p}:{n}` — `{t.strip()[:100]}`" for p, n, t in added if LOOPING.search(t)]
        w("\n".join(rows[:30]) or "aucun motif de boucle asynchrone ou de `Promise.all` ajouté")
        w("jugement : `grep` le batch / loader existant avant d'en exiger un nouveau ; lire la règle pour les motifs propres au dépôt.")
    w("")

    w("### 7. Réutilisation plutôt que duplication (catalogues de messages)\n")
    cat_added = [(p, n, t) for p, n, t in added if CATALOG.search(p) and t.strip()]
    if cat_added:
        catalogs = [t for t in tracked_files() if CATALOG.search(t) and re.search(r"\.(json|ya?ml|po|xlf|arb|properties)$", t)]
        index = {}
        for c in sorted(set(catalogs) | {p for p, _, _ in cat_added}):
            src = head_text(c) or (Path(c).read_text(errors="replace") if Path(c).exists() else "")
            for i, line in enumerate(src.splitlines(), 1):
                m = KV.search(line)
                if m:
                    index.setdefault(norm(m.group(2)), []).append((c, i, m.group(1)))
        rows = []
        for p, n, text in cat_added[:60]:
            m = KV.search(text)
            if not m:
                continue
            key, val = m.group(1), norm(m.group(2))
            others = [(c, i, k) for c, i, k in index.get(val, []) if not (c == p and i == n)]
            if val and others:
                same_key = [o for o in others if o[0] == p and o[2] == key]
                tag = "🟠 même clé définie deux fois dans ce catalogue" if same_key else "🟡 valeur déjà présente"
                rows.append(f"- `{p}:{n}` `{key}` — {tag} : " + ", ".join(f"`{c}:{i}` (`{k}`)" for c, i, k in others[:3]))
        for p in sorted({p for p, _, _ in cat_added}):
            if p.endswith(".json"):
                dups = json_duplicate_keys(head_text(p))
                rows += [f"- `{p}` — 🟠 clé en double dans le même objet : `{k}`" for k in dups[:10]]
        w("Lignes ajoutées dans les catalogues :")
        for p, n, t in cat_added[:20]:
            w(f"- `{p}:{n}` — `{t.strip()[:110]}`")
        if len(cat_added) > 20:
            w(f"- … +{len(cat_added) - 20} autres lignes")
        w("\nDoublons trouvés (valeur comparée sans casse ni ponctuation finale, catalogues du checkout courant + fichiers touchés) :")
        w("\n".join(rows) or "aucun")
        w("\njugement : un doublon de valeur justifie-t-il vraiment de réutiliser la clé existante (même contexte d'usage) ?")
    else:
        w("aucun catalogue de messages touché")

    print("\n".join(out))


if __name__ == "__main__":
    main()
