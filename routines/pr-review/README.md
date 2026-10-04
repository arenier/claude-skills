# Routine — revue de code sur PR (ouverture ou label `claude`)

Routine cloud (agent claude.ai **événementiel**) qui relit **une** pull request du dépôt qui la
déclenche, applique le skill `pr-review` (plugin `adri-plugin`, même dépôt que cette routine), et
poste le commentaire de review sous l'identité `claude[bot]`.

Elle est **agnostique du dépôt** : le dépôt cible est celui de la PR (`CCR_TRIGGER_REPO`), et ses
conventions viennent de ce dépôt (`CLAUDE.md`, ADR, rules, et le profil optionnel
`.claude/pr-review.json` décrit dans
[`PROFILE.md`](../../adri-plugin/skills/pr-review/PROFILE.md)). Brancher un nouveau dépôt, c'est
ajouter un déclencheur dans l'UI et, si on veut une relecture adaptée, déposer un profil.

Un **seul** prompt couvre les deux déclenchements possibles — l'**ouverture / mise à jour** d'une PR
et l'**ajout du label `claude`** — parce que la seule chose qui change entre eux (la déduplication)
se **déduit à l'exécution de la présence du label `claude`** sur la PR.

## Comportement unifié

La config des déclencheurs dans l'UI décide **quand** la routine se réveille ; le prompt décide
**comment** se comporter d'après l'état du label sur la PR relue.

| État de la PR au moment de la lecture | Mode | Déduplication |
|---|---|---|
| **Sans** label `claude` | Automatique | **Stricte par SHA** — marqueur au même SHA → on ne poste rien, quel que soit son âge |
| **Avec** label `claude` | À la demande | Fenêtre de **10 min** — un ré-étiquetage volontaire relance une review à SHA inchangé |

Conséquence du montage des déclencheurs (dans l'UI, voir plus bas) :

- déclencheur **ouverture seule** → toute PR ouverte est relue ;
- déclencheur **label seul** → relue à la pose du label ;
- **les deux** → auto-review à l'ouverture **et** review à la demande par label, sans doublon.

## Deux sources de vérité — et leur frontière de sécurité

Le `prompt.md` de la routine et le skill `pr-review` vivent ici, dans `arenier/claude-skills`. Les
conventions de chaque dépôt relu vivent dans ce dépôt.

| Fichier | Rôle |
|---|---|
| `prompt.md` | **Instructions exécutées**. Source unique lue par CHAQUE déploiement, **au ref `main`** de `arenier/claude-skills`. |
| `routine.template.json` | Body de création de l'API, à instancier (placeholders `<<…>>`). |
| `README.md` | Cette fiche. |

Le skill de review : [`adri-plugin/skills/pr-review/SKILL.md`](../../adri-plugin/skills/pr-review/SKILL.md),
lu au ref `main`.

> **Le durcissement.** Le workspace d'un run événementiel est le checkout de **la branche de la PR
> relue** — modifiable par l'auteur de la PR. Aucune instruction n'y est donc lue : tout passe par le
> canal GitHub MCP (`get_file_contents`), **jamais** depuis le workspace.
>
> - Le prompt et le skill sont lus sur la `main` de `arenier/claude-skills`, un **autre dépôt** : une
>   PR du dépôt relu ne peut pas les toucher. Qui peut pousser sur `claude-skills` peut en revanche
>   changer le référentiel de review de tous les dépôts branchés — c'est la frontière à tenir, donc
>   protéger sa `main` (review requise, pas de push direct).
> - Les conventions du dépôt relu (`CLAUDE.md`, ADR, rules, profil) sont lues sur **sa branche par
>   défaut**, protégée elle aussi : un auteur ne peut pas les altérer sans d'abord les faire merger.
>   Un dépôt dont la branche par défaut n'est pas protégée affaiblit sa propre relecture, pas celle
>   des autres.

## Prérequis d'accès

La session cloud lit GitHub via la **GitHub App de Claude**, pas via SSH. Cette App doit avoir accès
au dépôt relu **et** à `arenier/claude-skills`, **et** les deux dépôts doivent figurer dans les
`sources` de la routine (clone + allowlist de `get_file_contents`). Sans l'un ou l'autre, la routine
s'arrête proprement (fail-closed) sans rien poster.

## Déployer

Instancier `routine.template.json` en substituant :

| Placeholder | Où le trouver |
|---|---|
| `<<TARGET_REPO_URL>>` | l'URL du dépôt à relire, ex. `https://github.com/arenier/pick-a-book` |
| `<<ENVIRONMENT_ID>>` | `/schedule` liste les environnements (`env_…`) |
| `<<UUID_V4>>` | n'importe quel UUID v4 minuscule |
| `<<CONNECTOR_UUID_CLAUDE_CODE_REMOTE>>` | copié depuis les `mcp_connections` d'une routine existante |

> **Le binding événementiel n'est PAS dans ce body.** Le ou les déclencheurs (dépôt, événement
> `pull_request` — action `opened`/`synchronize` et/ou `labeled` —, et **tous** les filtres : label
> `claude`, auteur, état de la PR) se configurent depuis <https://claude.ai/code/routines>. C'est le
> seul endroit qui décide quels événements atteignent un run ; le prompt ne redouble aucun de ces
> filtres.
>
> - **Choisis les déclencheurs selon l'usage voulu** (voir le tableau [Comportement
>   unifié](#comportement-unifié)) : ouverture, label, ou les deux.
> - **Sans filtre auteur sur le déclencheur d'ouverture, chaque PR ouverte du dépôt est relue** — à
>   contrôler après déploiement.

## Vérifier

Pour **changer le dépôt d'une routine existante**, ajouter le dépôt à ses `sources` et son déclencheur
dans l'UI : le prompt n'a rien à changer.

Faire un **run manuel** (« Run now ») et contrôler : commentaire posté, **auteur = `claude[bot]`**,
une seule PR traitée. Une autre identité d'auteur = mauvais canal d'écriture (l'écriture doit passer
par `curl`, pas par un outil MCP). Pour couvrir les deux modes, valider une PR **sans** label (dédup
stricte par SHA) puis une PR **labellisée** (ré-étiquetage → nouvelle review).

## Composition

- `pr-review` (skill, plugin `adri-plugin`) — la procédure de review appliquée par cette routine, en mode « aucun humain
  dans la boucle » (les questions deviennent des remarques 💬, le second avis à froid et le fan-out
  ne se déclenchent pas).
- `pr-review-triage` (skill, même plugin) — en aval, à la main : traiter la review une fois postée (vérifier,
  corriger, répondre).
