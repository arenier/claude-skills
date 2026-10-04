#!/usr/bin/env python3
"""Render the review sheet and the PR comment from the reviewer's findings.

    python3 render.py <workdir>

Reads <workdir>/pr.json and <workdir>/profile.json (from collect.sh) and
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
from analyze import ci_state, title_check, zone  # noqa: E402

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
FIELDS = ("intention", "scope", "decisions", "tests", "twins", "second_opinion", "summary")
LOCATION = re.compile(r"^\S+:\d+(-\d+)?$")
MARKER = "<!-- pr-review -->"


def profile_checks(profile):
    """The repo's extra rows of the sheet, in profile order: (id, label)."""
    return [(c["id"], c["label"]) for c in profile.get("companions", []) + profile.get("checks", []) if c.get("id")]


def validate(review, profile):
    problems = [f"champ manquant : {f}" for f in FIELDS if not str(review.get(f, "")).strip()]
    results = review.get("checks") or {}
    problems += [f"checks.{i} manquant ({label})" for i, label in profile_checks(profile) if not str(results.get(i, "")).strip()]
    for i, f in enumerate(review.get("findings", []), 1):
        sev = f.get("severity")
        if sev not in SEVERITIES:
            problems.append(f"constat {i} : severity doit être {', '.join(SEVERITIES)}")
            continue
        problems += [f"constat {i} ({sev}) : champ manquant : {k}" for k in REQUIRED[sev] if not str(f.get(k, "")).strip()]
        if "location" in REQUIRED[sev] and f.get("location") and not LOCATION.match(f["location"]):
            problems.append(f"constat {i} : location « {f['location']} » n'est pas un path:line")
    return problems


def verdict(findings):
    sevs = {f["severity"] for f in findings}
    if "blocker" in sevs:
        return "🔴", "À ne pas merger"
    if "major" in sevs:
        return "🟡", "Mergeable avec réserves"
    return "🟢", "Mergeable"


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


def sheet(pr, review, profile, findings, icon, label):
    draft = " (PR en draft : verdict indicatif)" if pr["isDraft"] else ""
    paths = [f["path"] for f in pr.get("files") or []]
    zones = ", ".join(sorted({zone(p) for p in paths}))
    rows = [
        ("Verdict", f"{icon} {label}{draft}"),
        ("Réserves", reserves(findings, with_location=True)),
        ("Intention", review["intention"]),
        ("Périmètre", f"{len(paths)} fichiers · +{pr['additions']}/-{pr['deletions']} lignes · zones : {zones}"),
        ("Zones touchées", review["scope"]),
        ("Titre Conventional Commits", title_check(pr["title"])),
        ("CI", f"{ci_state(pr.get('statusCheckRollup'))} — read-only, ne colore pas le verdict"),
        ("Décisions confrontées", review["decisions"]),
        ("Tests", review["tests"]),
        *[(label_, review["checks"][id_]) for id_, label_ in profile_checks(profile)],
        ("Jumeaux", review["twins"]),
        ("Vérifications lancées", "lecture de code + lecture CI (read-only). **Ni lint, ni test, ni build lancés localement.**"),
        ("Second avis à froid", review["second_opinion"]),
    ]
    out = [f"## Review — PR #{pr['number']} · {pr['title']}", "", "| Champ | Valeur |", "|---|---|"]
    out += ["| **%s** | %s |" % (k, str(v).replace("|", "\\|")) for k, v in rows]
    out += ["", "### Constats", ""]

    if not findings:
        out = out[:-2] + ["Aucun constat : le diff est conforme aux décisions et conventions confrontées ci-dessus.", ""]
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
    ci = ci_state(pr.get("statusCheckRollup"))
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
    out.append("_Relecture statique : lecture de code + CI (read-only). Ni lint, ni test, ni build lancés — "
               "un 🟢 veut dire « rien trouvé en lecture », pas « ça compile »._")
    return "\n".join(out) + "\n"


def main():
    workdir = Path(sys.argv[1])
    pr = json.loads((workdir / "pr.json").read_text())
    review = json.loads((workdir / "review.json").read_text())
    profile_file = workdir / "profile.json"
    profile = json.loads(profile_file.read_text()) if profile_file.exists() else {}
    problems = validate(review, profile)
    if problems:
        print("review.json invalide :", file=sys.stderr)
        print("\n".join(f"  - {p}" for p in problems), file=sys.stderr)
        sys.exit(1)

    order = list(SEVERITIES)
    findings = sorted(review.get("findings", []), key=lambda f: order.index(f["severity"]))
    if len(findings) > 10:
        print(f"attention : {len(findings)} constats, plafond ~10 — agréger le style dans `style`.", file=sys.stderr)

    icon, label = verdict(findings)
    body = comment(pr, review, findings, icon, label)
    (workdir / "comment.md").write_text(body)

    fence = fence_for(body)
    print(sheet(pr, review, profile, findings, icon, label))
    print("\n---\n\n## Commentaire à coller sur la PR\n")
    print(f"{fence}markdown\n{body}{fence}")


if __name__ == "__main__":
    main()
