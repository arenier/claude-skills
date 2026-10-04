#!/usr/bin/env bash
set -euo pipefail

# Print the prompt of the cold second-opinion sub-agent: blind by construction.
#
#   ./blind-prompt.sh <PR#> [workdir]
#
# The invariants of a blind review are mechanical, so they live here and not in a
# prompt rewritten from memory each time: the PR is the ONLY input (never the
# findings, never the verdict, never an axis), the agent must not read the repo's
# rules or skills, must read files in their PR version, and must not write.
#
# With a workdir (from collect.sh), the PR's own material is copied to
# <workdir>/blind/ (diff, files in PR version, title and description) and the prompt
# points there: the agent needs no GitHub access, and cannot stumble on facts.md,
# review.json or the rules, which stay one level up. Without one, it is told how to
# read the PR with `gh`.
# The agent is launched afterwards, on the user's go (SKILL.md, step 7b).

PR="${1:-}"
WORKDIR="${2:-}"
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "usage: $0 <PR#> [workdir]" >&2; exit 2; }

if [[ -n "$WORKDIR" ]]; then
  BLIND="$WORKDIR/blind"
  rm -rf "$BLIND"
  mkdir -p "$BLIND"
  cp "$WORKDIR/diff.patch" "$BLIND/diff.patch"
  cp -r "$WORKDIR/head" "$BLIND/head"
  python3 - "$WORKDIR/pr.json" > "$BLIND/description.md" <<'PY'
import json, sys
pr = json.load(open(sys.argv[1]))
print(f"# {pr['title']}\n\n{pr.get('body') or '(pas de description)'}")
PY
  SOURCE="Tout ce qui concerne la PR est dans \`${BLIND}\` : \`description.md\` (titre et description de l'auteur), \`diff.patch\` (le diff), et \`head/\` (chaque fichier touché dans sa VERSION PR, à son chemin du dépôt). Lis ces fichiers, rien d'autre. Pour les fichiers que la PR ne touche pas, le dépôt courant est identique à la PR."
else
  SOURCE="Lis les fichiers touchés dans leur VERSION PR, pas depuis le checkout (qui montre la branche par défaut et te ferait inventer des constats). Pour chacun : \`gh api \"repos/{owner}/{repo}/contents/<path>?ref=<headRefName>\" --jq .content | base64 -d\`. La liste des fichiers et le \`headRefName\` viennent de \`gh pr view ${PR} --json files,headRefName\`, le diff de \`gh pr diff ${PR}\`."
fi

cat <<PROMPT
Tu relis la pull request #${PR} du dépôt courant, à froid, avec un regard neuf.

Contraintes non négociables :
- Ne lis NI \`.claude/rules/**\` NI \`.claude/skills/**\` NI aucune autre règle écrite du dépôt, NI aucun fichier d'un autre relecteur (\`facts.md\`, \`review.json\`, \`comment.md\`, \`rules/\`) : ta valeur est une autre focale, pas un refaire du travail d'un autre relecteur.
- ${SOURCE}
- N'écris RIEN : ni \`gh pr comment\`, ni \`gh pr review\`, ni \`gh pr merge\`, ni modification de fichier, ni commit.
- Ne lance ni lint, ni test, ni build.

Ce que je veux : une liste de constats, rien d'autre. Pour chacun : \`path:line\` exact (le vrai fichier), le scénario concret qui casse (entrée ou état → comportement faux), et la sévérité que tu proposes (🔴 bloquant, 🟠 à corriger, 🟡 suggestion, 💬 question). Un constat sans conséquence énonçable est au mieux 🟡. Si tu ne peux pas vérifier quelque chose, dis-le en 💬 plutôt que de l'affirmer.
PROMPT
