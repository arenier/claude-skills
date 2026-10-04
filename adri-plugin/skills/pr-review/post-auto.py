#!/usr/bin/env python3
"""Post the routine's review comment as the ambient token, after a last dedup check.

    python3 post-auto.py <PR#> <workdir>

Only a routine uses this. It posts as `claude[bot]` (the installation token), never as a
person: the review must be recognisable as automatic at a glance. So it REQUIRES
GITHUB_TOKEN / GH_TOKEN and never falls back to `gh`, whose credentials are a person's.

Before posting it re-runs dedup.py: another run may have commented while the review was
being written. It refuses when:
  - the dedup decision is now SKIP (nothing is posted, exit 10);
  - the comment does not end with `<!-- pr-review-auto: SHA -->` at the SHA that was
    reviewed (pr.json), or the PR head has moved since (the review is stale).

It also refuses a token that is not an installation token (`ghs_…`): a user-to-server
(`ghu_…`) or personal token (`ghp_…`, `github_pat_…`) would sign the review as a person.
Exit code 11; `PR_REVIEW_ALLOW_USER_TOKEN=1` lifts it for a manual test.

It posts one comment and nothing else: no review, no merge, no label.
"""
import os
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from dedup import decide  # noqa: E402
from ghapi import api, token  # noqa: E402

import json  # noqa: E402


def main():
    number, workdir = sys.argv[1], Path(sys.argv[2])
    if not token():
        sys.exit("refus : GITHUB_TOKEN / GH_TOKEN absent. La review doit être postée sous l'identité du token ambiant (claude[bot]), jamais sous celle d'une personne.")
    if not token().startswith("ghs_") and os.environ.get("PR_REVIEW_ALLOW_USER_TOKEN") != "1":
        print("refus : le token ambiant n'est pas un token d'installation (ghs_…) : la review serait signée par une personne. "
              "Rien n'est posté, et aucun autre canal d'écriture n'est à tenter.", file=sys.stderr)
        sys.exit(11)
    body = (workdir / "comment.md").read_text()
    reviewed = json.loads((workdir / "pr.json").read_text())["headRefOid"]
    last = [line for line in body.splitlines() if line.strip()][-1]
    m = re.fullmatch(r"<!-- pr-review-auto: ([0-9a-f]{7,40}) -->", last.strip())
    if not m or m.group(1) != reviewed:
        sys.exit(f"refus : le commentaire doit finir par `<!-- pr-review-auto: {reviewed} -->` (render.py --routine).")

    result = decide(number)
    if result["sha"] != reviewed:
        sys.exit(f"refus : la PR a avancé ({reviewed[:12]} → {result['sha'][:12]}), cette review est périmée. Relancer collect.sh.")
    if result["decision"] == "SKIP":
        print(f"SKIP {result['reason']} : rien n'est posté.")
        sys.exit(10)

    posted = api(f"repos/{{owner}}/{{repo}}/issues/{number}/comments", method="POST", data={"body": body}, transport="token")
    login = posted["user"]["login"]
    print(f"auteur={login}")
    if not login.endswith("[bot]"):
        print(f"⚠️ commentaire posté sous `{login}`, pas sous une identité de bot : à signaler dans le rapport.", file=sys.stderr)
    print(f"url={posted['html_url']}")


if __name__ == "__main__":
    main()
