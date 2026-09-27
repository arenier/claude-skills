#!/usr/bin/env python3
"""List the phrases that often betray a Diataxis compliance problem.

    python3 signals.py <file> <tutorial|how-to|reference|explanation> [--diff]

A signal is not a violation: "car" can be a vehicle, "depuis" a place. Each
hit is a line to re-read against the checklist in diataxis.md, and the
judgment stays with the reader. What this script guarantees is that no such
line goes unread.

--diff restricts the scan to lines added since HEAD (the whole file when it is
untracked), for an edit that must be checked on the modified block only.
"""
import re
import subprocess
import sys
from pathlib import Path

STATE = [
    r"auparavant", r"désormais", r"dorénavant", r"anciennement", r"précédemment",
    r"jusqu'(à présent|ici)", r"n'(est|sont|existe|existent) plus", r"ne \w+ plus",
    r"a été (remplacée?s?|renommée?s?|supprimée?s?)", r"(depuis|à partir de) la version",
    r"nouvelle version", r"obsolète", r"dépréciée?s?", r"changelog",
    r"previously", r"formerly", r"no longer", r"used to", r"(has|have) been (replaced|renamed|removed)",
    r"(since|as of) (version|v\d)", r"deprecated",
]
JUSTIFICATION = [
    r"parce qu", r"\bcar\b", r"puisqu", r"afin (de|qu)", r"pour qu", r"c'est pour(quoi| ça| cela)",
    r"(la|une) raison", r"raison pour laquelle", r"justifi\w*", r"en effet", r"l'intérêt", r"ce qui permet",
    r"because", r"in order to", r"so that", r"the reason", r"rationale", r"(that|this) is why", r"\bwhy\b",
]
BRANCHING = [
    r"si vous préférez", r"si tu préfères", r"vous pouvez (aussi|également)", r"tu peux (aussi|également)",
    r"alternativement", r"au choix", r"optionnel\w*", r"facultati\w+", r"ou bien",
    r"alternatively", r"you can also", r"optionally", r"if you prefer",
]

CHECKS = {
    "Vérité de l'état (trace d'un état passé ?)": (STATE, {"tutorial", "how-to", "reference", "explanation"}),
    "Justification hors Explanation (un « pourquoi » ?)": (JUSTIFICATION, {"tutorial", "how-to", "reference"}),
    "Embranchement dans un tutorial (une option ?)": (BRANCHING, {"tutorial"}),
}


def lines_to_scan(path, diff):
    text = Path(path).read_text().splitlines()
    if not diff:
        return list(enumerate(text, 1))
    tracked = subprocess.run(["git", "ls-files", "--error-unmatch", path], capture_output=True).returncode == 0
    if not tracked:
        return list(enumerate(text, 1))
    patch = subprocess.run(["git", "diff", "-U0", "HEAD", "--", path], capture_output=True, text=True).stdout
    added, line = [], 0
    for raw in patch.splitlines():
        if raw.startswith("@@"):
            line = int(re.search(r"\+(\d+)", raw).group(1))
        elif raw.startswith("+") and not raw.startswith("+++"):
            added.append((line, raw[1:]))
            line += 1
    return added


def main():
    args = [a for a in sys.argv[1:] if a != "--diff"]
    if len(args) != 2 or args[1] not in {"tutorial", "how-to", "reference", "explanation"}:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        sys.exit(2)
    path, fmt = args
    lines = lines_to_scan(path, "--diff" in sys.argv)
    total = 0
    in_code = False
    scanned = []
    for n, text in lines:
        if text.lstrip().startswith("```"):
            in_code = not in_code
            continue
        if not in_code:
            scanned.append((n, text))

    for title, (patterns, formats) in CHECKS.items():
        if fmt not in formats:
            continue
        regex = re.compile("|".join(f"(?:{p})" for p in patterns), re.IGNORECASE)
        hits = [(n, m.group(0), t.strip()) for n, t in scanned for m in [regex.search(t)] if m]
        print(f"## {title}\n")
        for n, term, t in hits:
            print(f"- ligne {n} · « {term} » · {t[:140]}")
        print("rien\n" if not hits else "")
        total += len(hits)

    scope = "lignes ajoutées" if "--diff" in sys.argv else "document entier"
    print(f"{total} signal(aux) sur {len(scanned)} ligne(s) ({scope}, blocs de code exclus) — à juger un par un.")


if __name__ == "__main__":
    main()
