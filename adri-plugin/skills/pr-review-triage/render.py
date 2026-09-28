#!/usr/bin/env python3
"""Render the triage reply from the verdicts in triage.json.

    python3 render.py <workdir>

Writes <workdir>/reply.md and prints it. The judgment -- verdicts, treatments,
proofs -- is in triage.json. What is mechanical lives here: the summary table,
one <details> per point open only for 🔴/🟠, the blank line GitHub needs after
</summary>, and the "still open" list derived from the 📌 and ⛔ points.
Re-run it after each change of status: reply.sh posts the same comment again.
"""
import json
import re
import sys
from pathlib import Path

MARKER = "<!-- pr-review-triage -->"
SEVERITY = {"blocker": "🔴", "major": "🟠", "minor": "🟡", "question": "💬"}
STATUS = {
    "in_progress": ("⏳ En cours", None),
    "fixed": ("✅ Corrigé", "le sha du commit"),
    "deferred": ("📌 Reporté", "où la dette est notée"),
    "rejected": ("⛔ Écarté", "la raison, en une ligne"),
    "decide": ("🙋 À trancher", "la question posée"),
}
SHA = re.compile(r"^[0-9a-f]{7,40}$")


def validate(triage):
    problems = [] if str(triage.get("summary", "")).strip() else ["champ manquant : summary"]
    for i, p in enumerate(triage.get("points", []), 1):
        for key in ("title", "verdict", "outcome", "proof"):
            if not str(p.get(key, "")).strip():
                problems.append(f"point {i} : champ manquant : {key}")
        if p.get("severity") not in SEVERITY:
            problems.append(f"point {i} : severity doit être {', '.join(SEVERITY)}")
        status = p.get("status")
        if status not in STATUS:
            problems.append(f"point {i} : status doit être {', '.join(STATUS)}")
            continue
        need = STATUS[status][1]
        note = str(p.get("note", "")).strip()
        if need and not note:
            problems.append(f"point {i} ({status}) : note requise — {need}")
        if status == "fixed" and note and not SHA.match(note):
            problems.append(f"point {i} : note « {note} » n'est pas un sha")
    return problems


def treatment(p):
    label, _ = STATUS[p["status"]]
    note = str(p.get("note", "")).strip()
    if p["status"] == "fixed":
        return f"{label} {note}"
    return f"{label} ({note})" if note else label


def main():
    wd = Path(sys.argv[1])
    triage = json.loads((wd / "triage.json").read_text())
    problems = validate(triage)
    if problems:
        print("triage.json invalide :", file=sys.stderr)
        print("\n".join(f"  - {p}" for p in problems), file=sys.stderr)
        sys.exit(1)

    order = list(SEVERITY)
    points = sorted(triage["points"], key=lambda p: order.index(p["severity"]))
    out = [MARKER, triage["summary"].strip(), "", "| Point | Verdict | Traitement |", "|---|---|---|"]
    for p in points:
        cells = (f"{SEVERITY[p['severity']]} {p['title']}", p["verdict"], treatment(p))
        out.append("| " + " | ".join(c.replace("|", "\\|") for c in cells) + " |")

    out += ["", f"**Vérifications point par point ({len(points)})**", ""]
    for i, p in enumerate(points, 1):
        opened = " open" if p["severity"] in ("blocker", "major") else ""
        out += [
            f"<details{opened}>",
            f"<summary><b>{i}. {SEVERITY[p['severity']]} {p['title']} — {p['outcome']}</b></summary>",
            "",
            p["proof"].strip(),
            "",
            "</details>",
            "",
        ]

    unnoticed = [u for u in triage.get("unnoticed", []) if u.strip()]
    still_open = [p for p in points if p["status"] in ("deferred", "rejected", "decide")]
    if unnoticed or still_open:
        out += ["<details>", "<summary><b>Point non relevé · Ce qui reste ouvert</b></summary>", ""]
        for u in unnoticed:
            out += [f"**Point non relevé par la review** — {u}", ""]
        if still_open:
            out += ["**Ce qui reste ouvert**", ""]
            out += [f"- {SEVERITY[p['severity']]} {p['title']} — {treatment(p)}" for p in still_open]
            out.append("")
        out += ["</details>", ""]

    body = "\n".join(out).rstrip() + "\n"
    (wd / "reply.md").write_text(body)
    print(body)

    pending = [p["title"] for p in points if p["status"] == "decide"]
    if pending:
        print(f"À trancher par l'utilisateur avant d'appliquer : {' · '.join(pending)}", file=sys.stderr)


if __name__ == "__main__":
    main()
