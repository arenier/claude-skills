#!/usr/bin/env bash
set -euo pipefail

# Print the prompt of the cold second-opinion sub-agent: blind by construction.
#
#   ./blind-prompt.sh <PR#>
#
# The invariants of a blind review are mechanical, so they live here and not in
# a prompt rewritten from memory each time: the PR number is the ONLY input (never
# the findings, never the verdict, never an axis), the agent must not read the
# repo's rules or skills, must read files in their PR version, and must not write.
# The agent is launched afterwards, on the user's go (SKILL.md, step 7b).

PR="${1:-}"
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "usage: $0 <PR#>" >&2; exit 2; }

cat <<PROMPT
Tu relis la pull request #${PR} du dépôt courant, à froid, avec un regard neuf.

Contraintes non négociables :
- Ne lis NI \`.claude/rules/**\` NI \`.claude/skills/**\` NI aucune autre règle écrite du dépôt : ta valeur est une autre focale, pas un refaire du travail d'un autre relecteur.
- Lis les fichiers touchés dans leur VERSION PR, pas depuis le checkout (qui montre la branche par défaut et te ferait inventer des constats). Pour chacun : \`gh api "repos/{owner}/{repo}/contents/<path>?ref=<headRefName>" --jq .content | base64 -d\`. La liste des fichiers et le \`headRefName\` viennent de \`gh pr view ${PR} --json files,headRefName\`, le diff de \`gh pr diff ${PR}\`.
- N'écris RIEN : ni \`gh pr comment\`, ni \`gh pr review\`, ni \`gh pr merge\`, ni modification de fichier, ni commit.
- Ne lance ni lint, ni test, ni build.

Ce que je veux : une liste de constats, rien d'autre. Pour chacun : \`path:line\` exact (le vrai fichier), le scénario concret qui casse (entrée ou état → comportement faux), et la sévérité que tu proposes (🔴 bloquant, 🟠 à corriger, 🟡 suggestion, 💬 question). Un constat sans conséquence énonçable est au mieux 🟡. Si tu ne peux pas vérifier quelque chose, dis-le en 💬 plutôt que de l'affirmer.
PROMPT
