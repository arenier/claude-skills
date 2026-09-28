#!/usr/bin/env python3
"""Format the review feedback gathered by collect.sh into sources.md.

    python3 sources.py <workdir>
"""
import json
import re
import sys
from pathlib import Path

TRIAGE_MARKER = "<!-- pr-review-triage -->"
AUTO_MARKER = re.compile(r"<!-- pr-review-auto: ([0-9a-f]{7,40}) -->")


def jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def main():
    wd = Path(sys.argv[1])
    pr = json.loads((wd / "pr.json").read_text())
    local = dict(line.split("=", 1) for line in (wd / "local.env").read_text().splitlines() if "=" in line)
    commits = pr.get("commits") or []
    oids = [c["oid"] for c in commits]
    head = pr["headRefOid"]

    def after_sha(sha):
        """Commits pushed after `sha`, or None when sha is not in the PR."""
        for i, oid in enumerate(oids):
            if oid.startswith(sha) or sha.startswith(oid):
                return len(oids) - 1 - i
        return None

    def after_date(date):
        return sum(1 for c in commits if c["committedDate"] > date)

    def staleness(n):
        if n is None:
            return "commit inconnu de la PR (historique réécrit ?)"
        return "à jour (HEAD)" if n == 0 else f"⚠️ {n} commit(s) poussé(s) depuis — vérifier que le point vaut encore"

    out = []
    w = out.append
    w(f"# Retours sur la PR #{pr['number']} · {pr['title']}\n")

    w("## État\n")
    w(f"- PR : {pr['state']} · {'draft' if pr['isDraft'] else 'ready'} · décision : {pr.get('reviewDecision') or '—'}")
    w(f"- HEAD : `{head[:12]}` sur `{pr['headRefName']}`")
    w(f"- Compte gh : {local.get('login')} · droit de push : {local.get('can_push')}")
    if local.get("can_push") != "true":
        w("  - ⚠️ ce compte ne peut pas pousser ici : `gh auth switch --user <compte>`")
    branch_ok = local.get("local_branch") == pr["headRefName"]
    w(f"- Checkout local : `{local.get('local_branch')}` {'= branche de la PR' if branch_ok else '≠ branche de la PR — faire `gh pr checkout` avant de corriger'}")
    w(f"- Fichiers modifiés localement : {local.get('dirty')} (à laisser hors des commits du triage)")

    w("\n## CI (`gh pr checks`)\n")
    w("```\n" + ((wd / "checks.txt").read_text().strip() or "aucun check") + "\n```")

    comments = jsonl(wd / "comments.jsonl")
    triage = [c for c in comments if c["body"].startswith(TRIAGE_MARKER)]
    w("\n## Commentaire de triage existant\n")
    if triage:
        c = triage[-1]
        w(f"- id {c['id']} · {c['html_url']} — reply.sh le mettra à jour")
    else:
        w("- aucun — reply.sh le créera")

    w("\n## Commentaires de conversation\n")
    shown = [c for c in comments if not c["body"].startswith(TRIAGE_MARKER)]
    for c in shown:
        m = AUTO_MARKER.search(c["body"])
        if m:
            origin, n = f"routine cloud, relu sur `{m.group(1)[:12]}`", after_sha(m.group(1))
        elif c["body"].startswith("<!-- pr-review -->"):
            origin, n = "skill pr-review", after_date(c["created_at"])
        else:
            origin, n = "humain ou autre", after_date(c["created_at"])
        w(f"### {c['user']['login']} · {c['created_at']} · id {c['id']} · {origin}\n")
        w(f"_{staleness(n)}_\n")
        w(c["body"].strip() + "\n")
    if not shown:
        w("aucun\n")

    w("## Reviews formelles\n")
    reviews = [r for r in jsonl(wd / "reviews.jsonl") if r.get("body", "").strip() or r["state"] != "COMMENTED"]
    for r in reviews:
        w(f"### {r['user']['login']} · {r['state']} · {r.get('submitted_at', '')}\n")
        w(f"_{staleness(after_sha(r.get('commit_id') or ''))}_\n")
        w((r.get("body") or "").strip() + "\n")
    if not reviews:
        w("aucune\n")

    w("## Commentaires inline\n")
    inline = jsonl(wd / "inline.jsonl")
    for c in inline:
        line = c.get("line")
        where = f"{c['path']}:{line}" if line else f"{c['path']} (ligne {c.get('original_line')} d'une version antérieure — retrouver le code par son contenu)"
        reply = f" · réponse à {c['in_reply_to_id']}" if c.get("in_reply_to_id") else ""
        w(f"### `{where}` · {c['user']['login']} · id {c['id']}{reply}\n")
        w(f"_{staleness(after_sha(c.get('commit_id') or ''))}_\n")
        w(c["body"].strip() + "\n")
    if not inline:
        w("aucun\n")

    print("\n".join(out))


if __name__ == "__main__":
    main()
