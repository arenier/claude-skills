---
name: pr-review
description: Relit une pull request de pick-a-book en confrontant chaque changement aux ADR et aux conventions du repo (CLAUDE.md + docs/adr/**), et produit une fiche de review + un commentaire prêt à coller ouvert par un verdict de mergeabilité. À utiliser quand on demande de relire, reviewer, ou donner un avis sur une PR — par numéro, par URL, ou « la PR ouverte ». Relecture statique : lit l'état de la CI en read-only, ne lance ni lint, ni test, ni build. Consultatif : ne merge pas, ne pousse rien, ne poste qu'après go explicite. Pour traiter une review déjà postée, c'est pr-review-triage.
argument-hint: <PR# | rien = la PR ouverte>
---

# Relecture de pull request

Produit un avis de relecture sur une PR de **ce repo** et, sur go explicite, le poste en commentaire
GitHub. La valeur de ce skill n'est pas la checklist générique (lint, tests, types — la CI les couvre
déjà) : c'est la **confrontation du diff aux décisions actées du projet**. Les ADR de `docs/adr/**`
consolident les arbitrages tranchés ; une relecture qui ne les confronte pas au diff laisse repasser
la même erreur.

Les ADR sont **contraignants** : c'est le référentiel contre lequel tu juges, pas ton goût personnel.
Une remarque sans ADR ni conséquence concrète est une opinion — elle descend en `🟡` ou en `✍️`,
jamais en bloquant.

## Quand l'utiliser

- `/pr-review <PR#>` (ex. `/pr-review 12`), ou `/pr-review` sans argument.
- « relis la PR », « reviewe cette PR », « qu'est-ce qui cloche là-dedans », un lien de PR collé.

**Ne pas l'utiliser pour** :

- **traiter** une review déjà postée (vérifier les points, corriger) → `pr-review-triage`.
- **écrire / créer** une PR → `create-pr`.
- une PR **Dependabot** → `collect.sh` la signale ; le dire et s'arrêter sans produire de fiche.

## Déroulé

Les scripts rassemblent les faits et mettent en forme ; toi, tu juges. Rien de ce qu'un script
établit ne se refait à la main, et rien de ce qui demande du jugement ne se délègue à un `grep`.

| # | Étape | Qui |
|---|---|---|
| 1 | Rassembler PR, diff, fichiers en version PR et faits mécaniques | script `collect.sh` |
| 2 | Établir l'intention | jugement |
| 3 | Lire CLAUDE.md et les ADR routés | jugement |
| 4 | Lire le code, chercher la réfutation | jugement |
| 5 | Trancher les vérifications hors-diff | jugement, sur les résultats bruts de l'étape 1 |
| 6 | Filtrer, classer, plafonner les constats | jugement |
| 6b | Second avis à froid, si un critère est rempli | jugement (proposer, attendre le go) |
| 7 | Écrire `review.json` | jugement |
| 8 | Calculer le verdict, rendre fiche et commentaire | script `render.py` |
| 9 | Poster, sur go explicite | script `post.sh` |

## 1. Rassembler

```bash
${CLAUDE_SKILL_DIR}/collect.sh [PR#]
```

Sans numéro : prend la seule PR ouverte ; s'il y en a plusieurs, le script les liste et sort en code
3 — demander laquelle plutôt que d'en choisir une. Refuser le mode « relis toutes les PR » : une PR à
la fois.

Le script vérifie `gh` (installé, authentifié) et écrit dans un répertoire de travail (dernière ligne
`WORKDIR=…`) : `pr.json`, `diff.patch`, **chaque fichier touché dans sa version PR** sous `head/`, et
`facts.md`, qu'il affiche :

- **Arrêts** : PR non ouverte ou Dependabot → s'arrêter. Draft → verdict indicatif. Base ≠ `main` → PR
  empilée, le diff peut inclure la PR parente : le signaler.
- **Taille** : lecture fichier par fichier au-delà de 2000 lignes ; fan-out à proposer au-delà de 40
  fichiers ou 2500 lignes ; critère d'enjeu du second avis.
- **Titre** : forme Conventional Commits. L'impératif et la capacité du titre à se tenir seul (il
  devient le message de commit de `main` au squash) restent à juger.
- **CI** : verte, rouge sur tel job, en attente, non lancée.
- **Routage ADR** : pour chaque fichier, les ADR qui le régissent.
- **Vérifications hors-diff** : résultats bruts des `grep` (imports ajoutés dans `domain` et
  `application`, specs, schéma et migrations, APIs verrouillées, assertions `as`).

## 2. Établir l'intention

Depuis le titre, le body et les messages de commit : **que cherche à faire cette PR ?** Sans intention
claire, une relecture dégénère en chasse au style. Si elle reste indéterminable (body vide, commits
« wip »), ne pas s'arrêter : la noter en 💬 et relire sur la seule base des ADR.

## 3. Lire les décisions

Lis `CLAUDE.md` puis les ADR listés par le routage — **lis les fichiers**, ne te fie pas à un résumé
de mémoire. Le routage dit *quels* ADR ouvrir ; ce qu'ils interdisent précisément, c'est leur texte
qui le dit. Repères pour savoir quoi y chercher :

| Zone | Ce que l'ADR tranche |
|---|---|
| `libs/*/domain/**` | 0002 — dépend de **rien** : ni framework, ni ORM, ni HTTP, ni autre contexte. Pas de primitive nue : value objects validant à la construction. |
| `libs/*/application/**` | 0002 — dépend du `domain` seul, parle aux **ports**, jamais aux adapters. 0003 — pas d'event bus. |
| `libs/*/infrastructure/**` | 0002 — personne n'en dépend hors composition root. 0006 — le SQL, le schéma Postgres et les migrations vivent **ici**. |
| `apps/api/**` | 0003 — seul module à connaître plus d'un contexte ; ne manipule que des **DTO de frontière** ; ne porte aucune règle exprimable dans un contexte. |
| `apps/web/**` | 0002 — feature-slice ; une slice n'importe pas l'intérieur d'une autre. |
| `libs/shared/**` | 0002 — n'importe **aucun** contexte ; une lib par sujet nommé, jamais `common`/`utils`. |
| Adapter VLM | 0005 — derrière `ShelfScannerPort` ; tests sur réponses enregistrées. |
| Outillage JS | 0001 — Yarn 4, pins exacts, `nodeLinker: node-modules`. 0007 — Vite/Vitest, SWC pour `apps/api`. |
| Déploiement | 0004 — Cloud Run + bucket. 0006 — Postgres managé, ni gcsfuse ni SQLite comme base. |

**Multi-tenant : non concerné** — ce repo n'a pas de clé tenant (usage personnel · ADR 0006).

**Fan-out** (seulement si `facts.md` le propose) : annoncer le coût et **attendre un go explicite**
avant de découper en sous-agents par axe (correction · frontières Nx · tests · front). ⚠️ Ne pas
découper une feature qui traverse les couches (un slice web + l'API + une migration, c'est sa forme
normale) : c'est la **cohérence inter-couches** qui donne les meilleurs constats. Après fan-out :
dédupliquer, **re-vérifier chaque 🔴 soi-même**, relire les jonctions entre axes.

## 4. Lire le code

Un hunk ment par omission. Pour chaque fichier non trivialement touché : **ouvrir le fichier entier**
dans `WORKDIR/head/` — jamais depuis le checkout local, qui est presque toujours `main` et montrerait
le code sans les changements de la PR. Les fichiers **non touchés** (adapters voisins, entités, specs
existantes) se lisent bien depuis le checkout : ils sont identiques sur les deux branches.

Pour chaque constat suspecté, va chercher la réfutation avant d'accuser :

- Un import qui semble interdit peut passer par une lib partagée légitime — vérifier la cible.
- Un use case qui semble parler à un adapter peut parler à un **port** injecté — `grep` le module.
- Un changement de comportement sans test visible peut être couvert par une spec existante — `grep`
  la spec du fichier et de ses appelants.
- Un pattern qui choque peut être **l'idiome du repo** — le compter (`grep -rl …`) avant d'en faire
  un constat. Un pattern présent dans des dizaines de fichiers n'est pas un défaut de cette PR.

C'est l'étape qui sépare une relecture utile d'une liste de faux positifs.

## 5. Trancher les vérifications hors-diff

`facts.md` donne les résultats bruts ; chacun reste un **candidat**, à confirmer par la lecture de
l'étape 4. Chaque vérification finit dans la fiche, y compris « rien ».

| # | Vérification | Ce que tu juges | Si confirmé |
|---|---|---|---|
| 1 | **Frontières Nx** | l'import listé franchit-il vraiment une frontière ? croiser avec `@nx/enforce-module-boundaries` dans `eslint.config.mjs` | 🔴 → ADR 0002 |
| 2 | **Jumeaux** — le correctif laisse un chemin frère intact (adapter ↔ adapter, single ↔ bulk, VO ↔ VO sœur, slice dupliquée) | aucun script ne connaît la signature du défaut : la déduire, puis `grep` la **signature** (pas le nom de fichier) dans tout le repo et auditer chaque appelant | 🟠 — corrigé, ou listé comme dette dans la description. Jamais silencieux. |
| 3 | **Comportement verrouillé par un test ?** | la spec listée couvre-t-elle le changement, **cas d'erreur** compris ? | 🟠 si rien ne le verrouille → conventions de test (CLAUDE.md) |
| 4 | **Schéma ↔ migration** | le fichier touché modifie-t-il vraiment le schéma ? | 🔴 sans discussion (ADR 0006) |
| 5 | **APIs verrouillées** | la ligne introduit-elle l'API, ou la mentionne-t-elle (commentaire, chaîne) ? | 🔴 → ADR 0001 / 0003 / 0006 / 0007 |
| 6 | **`as` interdit** | vraie assertion de type, ou faux positif (alias d'import, texte) ? | 🟠 → CLAUDE.md (`assertionStyle: 'never'`) ; proposer `satisfies` ou un type guard |

## 6. Filtrer les constats

Un constat entre dans la fiche seulement s'il passe les quatre tests :

1. **Localisé** — un `path:line` exact (le vrai fichier, pas la ligne du diff).
2. **Étayé** — le fichier entier a été lu, le `grep` de confirmation est fait. Si la vérification est
   impossible, le formuler en 💬 (« je ne trouve pas le port pour X, injecté ailleurs ? »).
3. **Conséquent** — un scénario concret : entrée/état → comportement faux, ou ADR nommément violé.
   Sans conséquence énonçable, c'est au mieux un 🟡.
4. **Réfuté d'abord** — « et si c'était intentionnel ? le code alentour le gère-t-il déjà ? » Un
   constat qui ne survit pas à cette question est supprimé.

Sévérités planchers, quel que soit le reste :

- Entité ou schéma modifié **sans** migration → 🔴 (ADR 0006).
- Logique métier ou correctif de bug **sans** test → au moins 🟠.
- Un jumeau identifié, ni corrigé ni signalé → au moins 🟠.

Puis **s'arrêter à ~10 constats**, du plus grave au moins grave. Une fiche de 40 lignes de style
enterre le seul bloquant qui compte. Ce que le plafond coupe ne disparaît pas : lisibilité, nommage,
découpage partent **agrégés** en 1-3 lignes dans `style`.

## 6b. Second avis à froid — optionnel

Cette relecture est **guidée** par les ADR : c'est sa force et son biais. **Déclencher seulement si un
critère est rempli** — sur une PR ordinaire et propre, ça ne produit que du bruit :

- **Enjeu** : calculé par `collect.sh` (adapter VLM, persistance, schéma, > 300 lignes).
- **Doute** : au moins un constat fini en 💬 faute de vérifiabilité ; un constat écarté sur une
  hypothèse non prouvée du comportement d'un tiers ; verdict 🟢 sans aucun constat sur un diff
  substantiel ; intention indéterminable ; un fichier clé illisible.

**Proposer et attendre le go.** Un sous-agent `general-purpose`, en avant-plan, **aveugle** : le
numéro de PR seul (jamais tes constats), interdiction de lire `.claude/skills/**`, obligation de lire
les fichiers en version PR (il peut lancer `collect.sh` lui-même), **interdiction de toute écriture**.
Sa sortie n'est **pas** autorité : dédupliquer, repasser chaque **nouveau** constat par les quatre
tests de l'étape 6, ne **jamais** le publier séparément.

## 7. Écrire `review.json`

Dans `WORKDIR/review.json`. Tout ce qui est mécanique (périmètre, titre, CI, verdict, réserves,
compteurs) est calculé par `render.py` : ne l'y mets pas.

```json
{
  "intention": "ce que la PR cherche à faire, en 1 phrase",
  "contexts": "apps et libs Nx concernés ; bounded context ou lib partagée",
  "adr": "ADR réellement relus pour cette review, ex. 0002 · 0006",
  "schema": "non concerné | entité modifiée AVEC migration | ⚠️ SANS migration",
  "tests": "N spec(s) ajoutés/modifiés · couvre <quoi> | ⚠️ domaine ou application SANS test",
  "boundaries": "tags posés · imports conformes | 🔴 import interdit : <path>",
  "twins": "aucun | <jumeau : chemin> · corrigé / NON corrigé",
  "second_opinion": "non déclenché | déclenché (<critère>) · N constats · M retenus",
  "summary": "1-2 phrases pour le commentaire : ce que fait la PR + la raison du verdict",
  "findings": [
    {"severity": "blocker", "title": "titre court", "location": "path:line",
     "breaks": "entrée/état → comportement faux, ou ADR violé", "rule": "ADR 000X (intitulé) ou convention CLAUDE.md",
     "fix": "la modification, en 1-3 lignes"},
    {"severity": "major", "…": "mêmes champs que blocker"},
    {"severity": "minor", "title": "…", "location": "path:line", "fix": "recommandation en 1 ligne"},
    {"severity": "question", "title": "ce qui ne se tranche pas sans l'auteur"}
  ],
  "style": ["lisibilité, nommage, découpage — agrégé, 1-3 lignes ; liste vide = rien à signaler"]
}
```

Une ligne sans objet s'écrit `non concerné` plutôt que de s'inventer une préoccupation.

## 8. Rendre

```bash
python3 ${CLAUDE_SKILL_DIR}/render.py <WORKDIR>
```

Valide `review.json` (champs, sévérités, `path:line`) et refuse s'il manque quelque chose. Puis
**calcule le verdict sur le code, jamais sur la CI** — 🔴 dès un bloquant, 🟡 dès un 🟠, 🟢 sinon —
et affiche la fiche, la frontière `---` / `## Commentaire à coller sur la PR`, puis le commentaire,
écrit aussi dans `WORKDIR/comment.md`. Recopier cette sortie telle quelle dans la conversation.

La CI rouge ne colore pas le verdict, mais elle n'est pas neutre : si sa cause est un défaut du diff,
ce défaut entre comme constat et le verdict bouge **par le code**. Une CI verte ne rachète aucun
constat. Le verdict est **consultatif** : il ne pose aucun label et ne bloque rien.

## 9. Poster (sur go explicite seulement)

```bash
${CLAUDE_SKILL_DIR}/post.sh <PR#> [WORKDIR]
```

Crée le commentaire, ou met à jour celui qui porte déjà le marqueur `<!-- pr-review -->` plutôt que
d'en empiler un second.

## Interdits

- **Aucune écriture GitHub sans go explicite.** Défaut : fiche + commentaire dans la conversation,
  rien de posté.
- Après un go : `post.sh`, **et rien d'autre**.
- **Toujours interdits**, même après un go : `gh pr review --approve`, `--request-changes`,
  `gh pr merge`, `gh pr close`, `gh pr edit`, l'auto-merge, tout changement de label/assignee. La
  décision GitHub reste à l'auteur.
- **Ne modifie aucun fichier du repo, ne pousse aucun commit.** Ce skill relit et propose des
  correctifs en extraits ; l'application passe par `pr-review-triage` ou par l'implémentation à la
  main. Les fichiers de `WORKDIR` sont hors du repo.
- **N'installe rien, ne lance ni lint, ni test, ni build.** La CI se **lit** ; elle ne se reproduit
  pas. Conséquence assumée : un 🟢 veut dire « rien trouvé en lecture », pas « ça compile ».
- **Ne signale rien que tu n'as pas vu.** Pas de remarque déduite du titre ou d'un nom de fichier, ni
  d'un résultat de `grep` non confirmé par la lecture. Une remarque fausse coûte plus cher que pas de
  remarque : elle décrédibilise tout le reste.
- **Le sous-agent du second avis n'écrit rien** : ni GitHub, ni fichier.

## Composition

| Skill | Rôle |
|---|---|
| `pr-review` | **produit** la review (ce skill) |
| `pr-review-triage` | **traite** une review déjà postée : vérifie chaque point, corrige, répond |
| `create-pr` | ouvre la PR — en amont de tout |
