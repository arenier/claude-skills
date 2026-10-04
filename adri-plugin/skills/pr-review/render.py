#!/usr/bin/env python3
"""Render the review sheet and the PR comment from the reviewer's findings.

    python3 render.py <workdir> [--routine [--sha <head sha>]]

With --routine, only the comment is printed, in the layout a routine posts
(folded sheet, `<!-- pr-review-auto: SHA -->` as the last line).

Reads <workdir>/pr.json and <workdir>/rules.json (from collect.sh) and
<workdir>/review.json (written by the reviewer), prints the sheet then the ready-to-paste comment, and writes
the comment to <workdir>/comment.md for post.sh.

The judgment is in review.json. What is mechanical lives here: the verdict
from the severities, the Réserves line, the section order, which <details>
open, which empty sections disappear.
"""
import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # no __pycache__ inside the installed plugin
sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze import ci_for, title_check, zone  # noqa: E402

SEVERITIES = {
    "blocker": ("🔴", "Bloquants", "Bloquants"),
    "major": ("🟠", "À corriger avant merge", "À corriger"),
    "minor": ("🟡", "Suggestions (non bloquant)", "Suggestions"),
    "question": ("💬", "Questions à l'auteur", "Questions"),
}
REQUIRED = {
    "blocker": ("title", "location", "breaks", "rule", "fix"),
    "major": ("title", "location", "breaks", "rule", "fix"),
    "minor": ("title", "location", "fix"),
    "question": ("title",),
}
FIELDS = ("intention", "contexts", "migrations", "tests", "locks", "tenant", "twins", "rules", "second_opinion", "summary")
LOCATION = re.compile(r"^\S+:\d+(-\d+)?$")
MARKER = "<!-- pr-review -->"


def floors(review):
    """Severity floors the review's own fields impose, so a verdict cannot contradict them.

    The convention: a field that reports a problem starts with its marker (🔴 or ⚠️)
    or says SANS migration / NON corrigé. Returns (needed severity, why) pairs.
    """
    out = []
    for field, label in (("locks", "verrou de stack"), ("tenant", "clé de tenant")):
        if str(review.get(field, "")).strip().startswith("🔴"):
            out.append(("blocker", f"« {label} » signale un 🔴"))
    if "SANS migration" in str(review.get("migrations", "")):
        out.append(("blocker", "entité modifiée SANS migration"))
    if str(review.get("tests", "")).strip().startswith("⚠️"):
        out.append(("major", "logique ou correctif sans test"))
    if "NON corrigé" in str(review.get("twins", "")):
        out.append(("major", "jumeau identifié, ni corrigé ni signalé"))
    return out


def check_location(workdir, location):
    """The finding's path must be a touched file (read in its PR version) or an existing file; the line must exist."""
    path, _, rest = location.rpartition(":")
    line = int(rest.split("-")[0])
    head = workdir / "head" / path
    if head.exists():
        n = len(head.read_text(errors="replace").splitlines())
        return None if line <= n else f"ligne {line} au-delà de la fin de `{path}` ({n} lignes en version PR)"
    touched = {f["path"] for f in json.loads((workdir / "pr.json").read_text()).get("files") or []}
    if path in touched:
        return None  # deleted by the PR: no PR version to measure
    return None if Path(path).exists() else f"`{path}` n'est ni touché par la PR ni présent dans le checkout"


def validate(review, workdir=None):
    problems = [f"champ manquant : {f}" for f in FIELDS if not str(review.get(f, "")).strip()]
    for i, f in enumerate(review.get("findings", []), 1):
        sev = f.get("severity")
        if sev not in SEVERITIES:
            problems.append(f"constat {i} : severity doit être {', '.join(SEVERITIES)}")
            continue
        problems += [f"constat {i} ({sev}) : champ manquant : {k}" for k in REQUIRED[sev] if not str(f.get(k, "")).strip()]
        if "location" in REQUIRED[sev] and f.get("location") and not LOCATION.match(f["location"]):
            problems.append(f"constat {i} : location « {f['location']} » n'est pas un path:line")
        elif workdir and f.get("location"):
            bad = check_location(workdir, f["location"])
            if bad:
                problems.append(f"constat {i} : {bad}")
    sevs = {f.get("severity") for f in review.get("findings", [])}
    for needed, why in floors(review):
        ok = "blocker" in sevs if needed == "blocker" else bool(sevs & {"blocker", "major"})
        if not ok:
            problems.append(f"plancher de sévérité : {why} exige au moins un constat {'🔴' if needed == 'blocker' else '🟠 ou 🔴'}")
    return problems


def verdict(findings):
    sevs = {f["severity"] for f in findings}
    if "blocker" in sevs:
        return "🔴", "Changements demandés"
    if "major" in sevs:
        return "🟡", "Approuvable avec réserves"
    return "🟢", "Approuvable"


def reserves(findings, with_location):
    top = [f for f in findings if f["severity"] in ("blocker", "major")]
    if not top:
        return "aucune"
    shown = [f"{f['title']} (`{f['location']}`)" if with_location else f["title"] for f in top[:3]]
    extra = f" · +{len(top) - 3} autres" if len(top) > 3 else ""
    return " · ".join(shown) + extra


def fence_for(text):
    longest = max((len(m) for m in re.findall(r"`+", text)), default=0)
    return "`" * max(3, longest + 1)


def sheet_title(pr):
    if pr.get("number") is None:
        return f"## Review — branche `{pr['headRefName']}` vs `{pr['baseRefName']}`"
    return f"## Review — PR #{pr['number']} · {pr['title']}"


def checks_run(review):
    local = str(review.get("local_checks", "")).strip()
    base = "lecture de code + lecture CI (read-only)"
    return f"{base} + {local}" if local else f"{base}. **Ni lint, ni test, ni build lancés localement.**"


def sheet_rows(pr, review, rules, findings, icon, label):
    draft = " (PR en draft : verdict indicatif)" if pr["isDraft"] else ""
    paths = [f["path"] for f in pr.get("files") or []]
    zones = ", ".join(sorted({zone(p) for p in paths}))
    rows = [
        ("Verdict", f"{icon} {label}{draft}"),
        ("Réserves", reserves(findings, with_location=True)),
        ("Intention", review["intention"]),
        ("Périmètre", f"{len(paths)} fichiers · +{pr['additions']}/-{pr['deletions']} lignes · zones : {zones}"),
        ("Contextes touchés", review["contexts"]),
        ("Titre", title_check(pr["title"], rules.get("commitlint"))),
        ("CI", f"{ci_for(pr)} — read-only, ne colore pas le verdict"),
        ("Migrations", review["migrations"]),
        ("Tests", review["tests"]),
        ("Verrous de stack", review["locks"]),
        ("Multi-tenant", review["tenant"]),
        ("Jumeaux (fix-twins)", review["twins"]),
        ("Règles confrontées", review["rules"]),
        ("Vérifications lancées", checks_run(review)),
        ("Second avis à froid", review["second_opinion"]),
    ]
    return ["| Champ | Valeur |", "|---|---|"] + ["| **%s** | %s |" % (k, str(v).replace("|", "\\|")) for k, v in rows]


def sheet(pr, review, rules, findings, icon, label):
    out = [sheet_title(pr), ""] + sheet_rows(pr, review, rules, findings, icon, label)
    out += ["", "### Constats", ""]

    if not findings:
        out = out[:-2] + ["Aucun constat : le diff est conforme aux règles confrontées ci-dessus.", ""]
    n = 0
    for sev, (emoji, heading, _) in SEVERITIES.items():
        group = [f for f in findings if f["severity"] == sev]
        if not group:
            continue
        out += [f"#### {emoji} {heading}", ""]
        for f in group:
            n += 1
            if sev in ("blocker", "major"):
                out += [
                    f"{n}. **{f['title']}** — `{f['location']}`",
                    f"   - **Ce qui casse** : {f['breaks']}",
                    f"   - **Règle** : {f['rule']}",
                    f"   - **Correctif** : {f['fix']}",
                ]
            elif sev == "minor":
                out.append(f"- {f['title']} — `{f['location']}` — {f['fix']}")
            else:
                out.append(f"- {f['title']}")
        out.append("")
    style = review.get("style") or ["Rien à signaler."]
    out += ["#### ✍️ Style & altitude", ""] + [f"- {s}" for s in style]
    return "\n".join(out)


def comment(pr, review, findings, icon, label):
    ci = ci_for(pr)
    out = [MARKER, f"**Review** · {icon} {label}", "", f"> **Réserves** — {reserves(findings, with_location=False)}", "", review["summary"], ""]
    if pr["isDraft"]:
        out += ["PR en draft : verdict indicatif.", ""]
    if ci != "verte":
        out += [f"CI {ci} — hors verdict.", ""]
    for sev, (emoji, _, short) in SEVERITIES.items():
        group = [f for f in findings if f["severity"] == sev]
        if not group:
            continue
        opened = " open" if sev in ("blocker", "major") else ""
        out += [f"<details{opened}>", f"<summary><b>{emoji} {short} ({len(group)})</b></summary>", ""]
        for f in group:
            if sev in ("blocker", "major"):
                out.append(f"- **{f['title']}** (`{f['location']}`) — {f['breaks']} → {f['fix']}")
            elif sev == "minor":
                out.append(f"- {f['title']} (`{f['location']}`) — {f['fix']}")
            else:
                out.append(f"- {f['title']}")
        out += ["", "</details>", ""]
    style = review.get("style") or ["rien à signaler"]
    out += ["<details>", "<summary><b>✍️ Style & altitude</b></summary>", ""] + [f"- {s}" for s in style] + ["", "</details>", ""]
    local = str(review.get("local_checks", "")).strip()
    if local:
        out.append(f"Vérifié localement : {local}.")
    else:
        out.append("_Relecture statique : lecture de code + CI (read-only). Ni lint, ni test, ni build lancés — "
                   "un 🟢 veut dire « rien trouvé en lecture », pas « ça compile »._")
    return "\n".join(out) + "\n"


def details(summary, lines, open_=False):
    return [f"<details{' open' if open_ else ''}>", f"<summary><b>{summary}</b></summary>", ""] + lines + ["", "</details>", ""]


def comment_routine(pr, review, rules, findings, icon, label, sha):
    """The layout a routine posts: verdict and reserves unfolded, everything else folded, the marker last.

    One screen unfolded; the whole sheet stays available, folded. The marker
    `<!-- pr-review-auto: SHA -->` is alone on the last line, outside any <details>:
    dedup.py reads it to know a SHA was already reviewed.
    """
    ci = ci_for(pr)
    out = [f"**Review** · {icon} {label}", "", f"> **Réserves** — {reserves(findings, with_location=False)}", "", review["summary"], ""]
    if pr["isDraft"]:
        out += ["PR en draft : verdict indicatif.", ""]
    if ci != "verte":
        out += [f"CI {ci} — hors verdict.", ""]
    top = [f for f in findings if f["severity"] in ("blocker", "major")]
    if top:
        has_blocker = any(f["severity"] == "blocker" for f in top)
        lines = [f"- {'🔴' if f['severity'] == 'blocker' else '🟠'} **{f['title']}** (`{f['location']}`) — {f['breaks']} → {f['fix']}" for f in top]
        out += details(f"🔴 Bloquants · 🟠 À corriger ({len(top)})", lines, open_=has_blocker)
    soft = []
    for f in findings:
        if f["severity"] == "minor":
            soft.append(f"- 🟡 {f['title']} (`{f['location']}`) — {f['fix']}")
        elif f["severity"] == "question":
            soft.append(f"- 💬 {f['title']}")
    soft += [f"- ✍️ {s}" for s in review.get("style") or ["rien à signaler"]]
    out += details(f"🟡 Suggestions · 💬 Remarques · ✍️ Style & altitude ({len(soft)})", soft)
    out += details("Fiche de review", sheet_rows(pr, review, rules, findings, icon, label))
    out.append(f"<!-- pr-review-auto: {sha} -->")
    return "\n".join(out) + "\n"


def main():
    args = sys.argv[1:]
    routine = "--routine" in args
    sha = None
    if "--sha" in args:
        sha = args[args.index("--sha") + 1]
    workdir = Path(args[0])
    pr = json.loads((workdir / "pr.json").read_text())
    review = json.loads((workdir / "review.json").read_text())
    rules_file = workdir / "rules.json"
    rules = json.loads(rules_file.read_text()) if rules_file.exists() else {}
    problems = validate(review, workdir)
    if problems:
        print("review.json invalide :", file=sys.stderr)
        print("\n".join(f"  - {p}" for p in problems), file=sys.stderr)
        sys.exit(1)

    order = list(SEVERITIES)
    findings = sorted(review.get("findings", []), key=lambda f: order.index(f["severity"]))
    if len(findings) > 10:
        print(f"attention : {len(findings)} constats, plafond ~10 — agréger le style dans `style`.", file=sys.stderr)

    icon, label = verdict(findings)
    if routine:
        body = comment_routine(pr, review, rules, findings, icon, label, sha or pr["headRefOid"])
        (workdir / "comment.md").write_text(body)
        print(body, end="")
        return
    body = comment(pr, review, findings, icon, label)
    (workdir / "comment.md").write_text(body)

    fence = fence_for(body)
    print(sheet(pr, review, rules, findings, icon, label))
    print("\n---\n\n## Commentaire à coller sur la PR\n")
    print(f"{fence}markdown\n{body}{fence}")


if __name__ == "__main__":
    main()
