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

## Les scripts font le travail

Rien de ce qui suit ne se tape à la main : c'est `${CLAUDE_SKILL_DIR}/local-gate.sh`.

```bash
local-gate.sh status <WORKDIR>                     # lecture seule
local-gate.sh checkout <PR#> --go -- <commande>    # branche de la PR, état de départ toujours rendu
local-gate.sh worktree <PR#> --go -- <commande>    # worktree isolé, toujours retiré
```

- **`status`** dit si le checkout courant est la branche de la PR (sinon une vérification locale ne dit
  **rien** de la PR : ne pas la lancer, l'écrire dans la fiche), si l'arbre est propre, et liste les
  scripts du `package.json` pour trouver les vérifications ciblées du dépôt.
- **`checkout`** refuse un arbre sale, note la branche de départ, fait `gh pr checkout`, lance la
  commande, et **rend toujours** la branche de départ, y compris sur échec ou interruption.
- **`worktree`** fait de même dans un worktree hors de l'arbre du projet (`PR_REVIEW_WT_DIR`, sinon
  `TMPDIR`) ; un worktree neuf n'a **pas** de `node_modules`, la commande doit installer si elle en a
  besoin (3-10 min, avec go). Il est toujours retiré, branche locale comprise.
- `--go` est obligatoire : il atteste que l'utilisateur a donné un go explicite pour du coûteux. Le
  coût, lui, s'annonce **avant**, par toi.

## Sans changer de branche (à préférer)

- Quand `status` dit que le checkout courant **est** la branche de la PR, lancer directement les scripts
  **ciblés, en lecture seule** du dépôt (diff de types, dépendances circulaires, usage des traductions)
  pour isoler la cause d'un constat précis ou d'un job de CI rouge.
- **Ne pas rejouer ce que la CI couvre sur un pipeline vert.** Lint, format, tests unitaires et build
  tournent déjà dans la CI de la PR : les relancer sur du vert n'apporte aucune information. Ces
  scripts ne servent qu'à **isoler la cause** d'un job rouge, jamais à re-valider du vert.
- La cause d'un job rouge est déjà dans `WORKDIR/ci-<run>.log`, récupérée par `collect.sh`.
- Le diff d'une PR et ses fichiers en version PR sont déjà dans `WORKDIR` (`diff.patch`, `head/`).

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
