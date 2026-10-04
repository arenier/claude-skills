# pr-review — vérifications locales (référence)

À lire **seulement** quand un constat ne se tranche pas à la lecture du code et que l'utilisateur a
donné son go. La règle par défaut tient : la CI de la PR couvre déjà les contrôles génériques (lint,
tests, build, code mort…) sur les projets affectés. **On ne la reproduit pas.**

Ce fichier est agnostique du dépôt. Les noms de scripts, les cibles et la pile e2e **propres au dépôt
relu** se découvrent dans les scripts de son `package.json` et dans son `CLAUDE.md`, jamais supposés ici.
Ce que ce fichier fixe, c'est le **principe** et la **discipline de coût**, pas une liste de commandes.

## Discipline de coût

Une seule règle : **annoncer l'ordre de grandeur du coût d'une vérification _avant_ de la lancer, jamais
après**, et conditionner les coûteuses à un go explicite.

| Classe de vérification | Ordre de grandeur typique | Go explicite |
|---|---|---|
| Un script de diff en lecture seule du dépôt (nouveaux `any`, dépendances circulaires) | < 1 min | non, **si le checkout courant est la branche de la PR** |
| Le test unitaire ou le lint d'un seul projet | 1-5 min | non, même condition |
| Les tests ou le lint « affectés » sur tout le graphe | ~10-30 min | **oui** |
| Le build de production « affecté » | ~15-60 min | **oui** |
| La pile e2e complète (Docker + e2e) | 30 min - 1 h+ | **oui** |
| Une installation de dépendances neuve dans un worktree neuf | 3-10 min | **oui** |

**Exiger un go explicite pour tout ce qui dure ≥ ~10 min, ou qui exige un checkout de la branche.**

## Sans changer de branche (à préférer)

⚠️ **Ces commandes mesurent le checkout courant.** S'il n'est pas la branche de la PR, leur résultat ne
dit rien de la PR : ne pas les lancer, et l'écrire dans la fiche.

- Lancer les scripts **ciblés, en lecture seule** du dépôt (diff de types, dépendances circulaires,
  usage des traductions) quand ils aident à isoler la cause d'un constat précis ou d'un job de CI rouge.
- **Ne pas rejouer ce que la CI couvre sur un pipeline vert.** Lint, format, tests unitaires et build
  tournent déjà dans la CI de la PR : les relancer sur du vert n'apporte aucune information. Ces
  scripts ne servent qu'à **isoler la cause** d'un job rouge, jamais à re-valider du vert.

Pour lire le diff d'une PR sans la checkouter : `gh pr diff <PR#>` et `gh pr view <PR#> --json files`.

Pour lire un fichier **en version PR** sans checkout (`{owner}/{repo}` est substitué par `gh` depuis le
remote courant, ne jamais écrire le dépôt en dur) :

```bash
gh api "repos/{owner}/{repo}/contents/<path>?ref=<headRefName>" --jq .content | base64 -d
```

## Avec un checkout de la PR

Prérequis non négociables :

1. `git status --porcelain` **vide**. Sinon : afficher `Arbre de travail non propre. Commit/stash tes
   changements avant que je checkoute la PR.` et s'arrêter.
2. Noter la branche de départ : `git rev-parse --abbrev-ref HEAD`.
3. **Rendre l'état de départ avant de rendre la main**, y compris en cas d'échec.

```bash
gh pr checkout <PR#>
# … vérification ciblée …
git checkout <branche-de-départ>
```

## Avec un worktree isolé (quand on ne veut pas toucher au checkout)

Convention : le worktree vit dans le scratchpad de la session, jamais dans l'arbre du projet.

```bash
WT=<scratchpad>/pr-review-<PR#>
git fetch origin pull/<PR#>/head:pr-<PR#>
git worktree add "$WT" pr-<PR#>
# un worktree neuf n'a PAS de node_modules : une installation est nécessaire (3-10 min) —
# ne la faire que si la vérification en a vraiment besoin.
git worktree remove "$WT" --force
```

Un worktree oublié pollue `git worktree list` et le disque : le retirer systématiquement, même après un
échec.

## Pile e2e / intégration

Les vérifications les plus lourdes (pile applicative complète + e2e) ne tournent d'ordinaire dans la CI du
dépôt que derrière un drapeau. Découvrir le point d'entrée e2e du dépôt dans son `package.json` ou son
`CLAUDE.md`.

**Ne jamais les lancer de sa propre initiative.** Si un constat ne se prouve que par un e2e, le formuler
en question 💬, ou en 🟠 avec la mention « à prouver par un e2e ».

## Ce qu'on ne vérifie pas en local

- **Le build de production des apps** : la CI le fait sur les projets affectés ; le refaire n'apporte rien.
- **Les fichiers générés que le dépôt ignore** (artefacts de codegen GraphQL, JSON de traduction tirés
  d'un TMS, par exemple). Si les règles du dépôt disent qu'ils sont ignorés par git, ne jamais les exiger
  dans le diff : une étape de codegen oubliée se voit dans le job de build de la CI, pas dans le diff.
  Lire les règles du dépôt pour savoir quels fichiers sont générés ; ne pas le supposer.
