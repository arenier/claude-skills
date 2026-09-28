---
name: create-pr
description: Ouvre une pull request décrite — contexte, modifications, tests, ADR concernés, points d'attention, issue liée. Gère aussi la branche, les commits et le push quand le travail est encore sur main ou non commité. À utiliser dès qu'il s'agit d'ouvrir ou créer une PR, de « faire la PR », de proposer le travail à la relecture, ou de « create a PR » / « open a pull request ».
---

# Ouvrir une PR décrite

Le corps de PR sert à **relire**, pas à raconter. Le relecteur a déjà le diff : ce qu'il n'a pas,
c'est l'intention, l'arbitrage, et ce qui mérite son attention en premier. Une PR qui paraphrase le
diff ne vaut rien.

Périmètre : de l'état de travail courant jusqu'à la PR ouverte. **Le merge n'en fait pas partie** —
c'est la décision de l'auteur.

## Déroulé

Les scripts relèvent l'état, lancent les vérifications et refusent une PR mal formée. Le jugement
porte sur ce qui entre dans la PR et sur ce qu'on en dit.

| # | Étape | Qui |
|---|---|---|
| 1 | Relever l'état réel et lire le diff | script `state.sh` |
| 2 | Nommer la branche, choisir quoi commiter et comment découper | jugement |
| 3 | Commiter | script `commit.sh` |
| 4 | Lancer lint et tests | script `checks.sh` |
| 5 | Rédiger titre et corps | jugement |
| 6 | Valider, pousser, ouvrir | script `open.sh` |
| 7 | Rendre compte | jugement |

Les scripts du plugin vivent dans `${CLAUDE_SKILL_DIR}` (ceux de ce skill) et
`${CLAUDE_SKILL_DIR}/../../scripts` (partagés avec `pr-review-triage`).

## 1. Relever l'état réel

```bash
${CLAUDE_SKILL_DIR}/state.sh
```

Branche courante, commits de la branche, périmètre commité et non commité, fichiers non suivis, PR
déjà ouverte pour la branche, issues ouvertes, puis le diff complet. **Lire le diff**, pas seulement
les `--stat` : ne rédiger aucune section sur la base de la conversation seule — ce qui compte est ce
que le diff contient, pas ce qu'on a eu l'intention de faire.

Si une PR est déjà ouverte pour la branche, ne pas en ouvrir une seconde : proposer de mettre à jour
sa description (`gh pr edit <N> --body-file <fichier>`).

## 2. Décider ce qui entre dans la PR

- **Sur `main`** (protégée, push direct refusé) → créer la branche avant tout :
  `git checkout -b <type>/<résumé-kebab-case>` (`feat/`, `fix/`, `docs/`, `refactor/`, `chore/`).
- **Quoi commiter** → les fichiers du travail en cours, et rien d'autre. Un fichier hors sujet dans le
  diff (capture, config locale, artefact de dev-server) se signale à l'utilisateur au lieu d'être
  embarqué.
- **Comment découper** → plusieurs commits si le travail contient des parties distinctes, qui se
  comprendraient seules ; un seul sinon.

## 3. Commiter

```bash
${CLAUDE_SKILL_DIR}/../../scripts/commit.sh -m "<type>(<scope>): <sujet>" [-b <corps.txt>] -- <chemins>...
```

Message en anglais. Le script refuse `main`, un sujet hors Conventional Commits et `.` en guise de
chemins ; il ajoute le trailer `Co-Authored-By`.

## 4. Lancer lint et tests

```bash
${CLAUDE_SKILL_DIR}/checks.sh
```

Lance `yarn nx affected -t lint test` et finit par une ligne `CHECKS=` : `passed`, `failed`, ou
`none` tant que le repo n'a pas de `package.json`. Un échec se corrige avant d'ouvrir, ou se dit dans
la section Tests — jamais en silence.

## 5. Rédiger

### Titre

Anglais, préfixe conventionnel, **impératif**, minuscule, ~70 caractères max :
`feat: extract author/title pairs from shelf photo`. La forme est vérifiée par `open.sh` ;
l'impératif et la clarté, par toi.

Le merge est un squash : **ce titre devient le message de commit dans l'historique de `main`**. Il
doit se tenir seul, sans le contexte de la PR.

### Corps

Français. Ouvrir par une ou deux phrases : ce que la PR change, et pourquoi maintenant. Puis les
sections utiles, dans cet ordre. **Une section sans contenu réel se supprime** — `open.sh` refuse les
sections vides et les lignes « N/A ».

```markdown
<Une ou deux phrases : ce que la PR change, et pourquoi maintenant.>

## Contexte

## Modifications

## Tests

## ADR concernés

## Points d'attention

## Hors scope

Closes #N

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

**Contexte** — ce qui existait avant, et le problème que ça posait. À omettre quand le titre suffit.
Pas une reformulation du besoin en trois paragraphes.

**Modifications** — regrouper par intention, pas par fichier. Au-delà de trois fichiers, un tableau
`fichier ou lib → ce que ça fait` passe mieux qu'une liste. Dire ce que le code établit, pas quelles
lignes ont bougé.

**Tests** — ce qui est couvert, et le résultat **réellement observé** par `checks.sh` : coller le
résumé de sa sortie. Si `CHECKS=none` ou s'il n'y a pas de test, dire pourquoi (documentation seule,
adapter testé manuellement contre la vraie techno, …) et donner les étapes de vérification à la main.

**ADR concernés** — les ADR que le code applique, en lien relatif (`docs/adr/0002-….md`). Deux cas
qui exigent un arrêt avant d'ouvrir la PR, à signaler à l'utilisateur :

- la PR prend une **décision structurante sans ADR** → proposer d'écrire l'ADR dans la même PR ;
  c'est la règle du repo (« avant ou avec le code »).
- la PR **contredit un ADR accepté** → un ADR accepté ne se réécrit pas ; il faut un nouvel ADR qui
  remplace l'ancien.

**Points d'attention** — ce qu'il faut relire en premier, les limites connues, ce qui est fragile ou
reconstitué. C'est la section la plus utile ; ne pas la remplir de généralités pour la remplir.

**Hors scope** — ce qui a été laissé de côté volontairement, et ce qui reste non tranché.

**Closes #N** — seulement si une issue listée par `state.sh` correspond vraiment. `open.sh` refuse un
numéro qui n'existe pas ou n'est pas ouvert ; qu'il corresponde au travail, c'est à toi de le juger.

Le corps finit par la ligne `🤖 Generated with …` ci-dessus.

## 6. Valider, pousser, ouvrir

Écrire le corps dans un fichier du scratchpad, puis :

```bash
${CLAUDE_SKILL_DIR}/open.sh "<titre>" <chemin-du-corps>
```

Le script vérifie tout avant de toucher au remote et liste chaque problème d'un coup : pas sur
`main`, pas de PR déjà ouverte, titre conforme, aucune section vide ni ligne de remplissage, chaque
`Closes #N` existant et ouvert, pied de page présent. Il prévient si des changements non commités
restent hors de la PR. Seulement ensuite : `git push -u origin HEAD` puis `gh pr create --body-file`.

## 7. Rendre compte

Donner l'URL de la PR, et énumérer ce qui a été **écarté ou non vérifié** : test non lancé, fichier
laissé de côté, section supprimée faute de matière. Ce qui a échoué se dit, avec la sortie.

Ne pas merger. Rappeler que la suite appartient à l'auteur :
`gh pr merge --squash --delete-branch`.
