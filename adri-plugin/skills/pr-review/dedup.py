#!/usr/bin/env python3
"""Decide whether a routine must review a PR now, or abstain.

    python3 dedup.py <PR#> [--now 2026-10-04T10:00:00Z]

Prints `REVIEW <mode>` or `SKIP <reason>` and exits 0 (review) or 10 (skip).

The review marker is a comment carrying `<!-- pr-review-auto: SHA -->`.

  - the PR is not open                                  → SKIP
  - no marker, or a marker at another SHA               → REVIEW
  - a marker at the current SHA:
      - PR carries the `claude` label AND the marker is older than 10 minutes
        (a deliberate re-labelling asks for a new review)  → REVIEW
      - otherwise                                        → SKIP
        (no label: "déjà relue au SHA courant"; label, < 10 min: "doublon d'événement écarté")

Without the label the SHA IS the identity of the review: one review per SHA, whatever
its age (a pushed PR changes SHA and is reviewed again by itself). With the label,
which is an explicit request, a new review is produced even at an unchanged SHA; the
marker then only discards concurrent deliveries of the same event (10-minute window).
"""
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from ghapi import api, paginate  # noqa: E402

MARKER = re.compile(r"<!-- pr-review-auto: ([0-9a-f]{7,40}) -->")
WINDOW = timedelta(minutes=10)


def parse(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def decide(number, now=None):
    now = now or datetime.now(timezone.utc)
    pr = api(f"repos/{{owner}}/{{repo}}/pulls/{number}")
    sha = pr["head"]["sha"]
    labelled = any(label["name"].lower() == "claude" for label in pr.get("labels") or [])
    if pr["state"] != "open":
        return {"decision": "SKIP", "reason": f"PR à l'état {pr['state']}", "sha": sha, "labelled": labelled}
    comments = paginate(f"repos/{{owner}}/{{repo}}/issues/{number}/comments")
    at_sha = [parse(c["created_at"]) for c in comments for m in MARKER.finditer(c.get("body") or "") if sha.startswith(m.group(1)) or m.group(1).startswith(sha)]
    base = {"sha": sha, "labelled": labelled}
    if not at_sha:
        return {**base, "decision": "REVIEW", "mode": "label `claude`, première review" if labelled else "ouverture / mise à jour"}
    age = now - max(at_sha)
    if labelled and age > WINDOW:
        return {**base, "decision": "REVIEW", "mode": "label `claude`, ré-étiquetage"}
    if labelled:
        return {**base, "decision": "SKIP", "reason": "doublon d'événement écarté (marqueur de moins de 10 minutes)"}
    return {**base, "decision": "SKIP", "reason": "déjà relue au SHA courant"}


def main():
    args = sys.argv[1:]
    now = parse(args[args.index("--now") + 1]) if "--now" in args else None
    result = decide(args[0], now)
    print(f"{result['decision']} {result.get('mode') or result.get('reason')}")
    print(f"sha={result['sha']} label_claude={str(result['labelled']).lower()}")
    sys.exit(0 if result["decision"] == "REVIEW" else 10)


if __name__ == "__main__":
    main()
