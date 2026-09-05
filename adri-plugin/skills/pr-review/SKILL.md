---
name: pr-review
description: Relit une pull request de pick-a-book en confrontant chaque changement aux ADR et aux conventions du repo (CLAUDE.md + docs/adr/**), et produit une fiche de review + un commentaire prêt à coller ouvert par un verdict de mergeabilité. À utiliser quand on demande de relire, reviewer, ou donner un avis sur une PR — par numéro, par URL, ou « la PR ouverte ». Relecture statique : lit l'état de la CI en read-only, ne lance ni lint, ni test, ni build. Consultatif : ne merge pas, ne pousse rien, ne poste qu'après go explicite. Pour traiter une review déjà postée, c'est pr-review-triage.
argument-hint: <PR# | rien = la PR ouverte>
---

# Relecture de pull request

Produit un avis de relecture sur une PR de **ce repo** et, sur go explicite, le poste en
commentaire GitHub. La valeur de ce skill n'est pas la checklist générique (lint, tests, types — la
CI les couvre déjà) : c'est la **confrontation du diff aux décisions actées du projet**. Les ADR de
`docs/adr/**` consolident les arbitrages tranchés ; une relecture qui ne les confronte pas au diff
laisse repasser la même erreur.

Les ADR sont **contraignants** : c'est le référentiel contre lequel tu juges, pas ton goût
personnel. Une remarque sans ADR ni conséquence concrète est une opinion — elle descend en `🟡` ou
en `✍️`, jamais en bloquant.

## Quand l'utiliser

- `/pr-review <PR#>` (ex. `/pr-review 12`), ou `/pr-review` sans argument.
- « relis la PR », « reviewe cette PR », « qu'est-ce qui cloche là-dedans », un lien de PR collé.

**Ne pas l'utiliser pour** :

- **traiter** une review déjà postée (vérifier les points, corriger) → `pr-review-triage`.
- **écrire / créer** une PR → `create-pr`.
- une PR **Dependabot** → la relecture d'un bump de dépendance ne relève pas de ce skill ; le dire
  et s'arrêter sans produire de fiche.

## Entrée

Le numéro de PR. S'il n'est pas fourni, prends la seule PR ouverte
(`gh pr list --state open --json number,title`). S'il y en a plusieurs, demande laquelle plutôt que
d'en choisir une. Refuse le mode « relis toutes les PR » : une PR à la fois.

## Prérequis

1. `gh --version` répond → sinon : `` `gh` (GitHub CLI) requis. Installation : `brew install gh`. ``
   et arrête-toi.
2. `gh auth status` rapporte une session → sinon : `` `gh` installé mais non authentifié. Lance
   `gh auth login` puis relance. `` et arrête-toi.

Aucun mode n'exige un arbre de travail propre : toute la relecture est en lecture seule.

## Livrable attendu

**Deux blocs streamés dans la conversation. Aucun fichier créé. Aucun appel `gh` qui écrit, sauf go
explicite (voir Interdits).**

### Bloc 1 — Fiche de review

```
## Review — PR #<N> · <titre>

| Champ | Valeur |
|---|---|
| **Verdict** | 🟢 Mergeable · 🟡 Mergeable avec réserves · 🔴 À ne pas merger |
| **Réserves** | <titres des constats 🔴 et 🟠, 3 au plus, séparés par ` · `, chacun avec son `path:line` · `+N autres` au-delà> — ou `aucune` |
| **Intention** | <ce que la PR cherche à faire, en 1 phrase, tirée du titre/body/commits> |
| **Périmètre** | <X fichiers · +A/-S lignes · zones touchées : api / web / libs / docker / docs …> |
| **Contextes / libs touchés** | <apps et libs Nx concernés ; bounded context `recognition` ou lib partagée> |
| **Titre Conventional Commits** | <conforme (`type(scope): sujet`, impératif, minuscule) / ⚠️ non conforme : <détail>> |
| **CI** | <verte / rouge sur `<job>` (<cause>) / en attente / non lancée> — read-only, ne colore pas le verdict |
| **ADR confrontés** | <numéros des ADR réellement relus pour cette review, ex. 0002 · 0006> |
| **Schéma / migration** | <non concerné / entité ou schéma Postgres modifié dans `infrastructure` AVEC migration / ⚠️ SANS migration> |
| **Tests** | <N spec(s) ajoutés/modifiés · couvre <quoi> / ⚠️ domaine ou application ajouté SANS test> |
| **Frontières Nx** | <tags posés sur les nouveaux projets · imports conformes à `@nx/enforce-module-boundaries` / 🔴 <import interdit : path>> |
| **Jumeaux** | <aucun / <jumeau identifié : chemin> · <corrigé / NON corrigé>> |
| **Vérifications lancées** | lecture de code + lecture CI (read-only). **Ni lint, ni test, ni build lancés localement.** |
| **Second avis à froid** | <non déclenché / déclenché (<critère>) · N constats · M retenus> |

### Constats

#### 🔴 Bloquants
1. **<titre court>** — `path:line`
   - **Ce qui casse** : <scénario concret : entrée/état → comportement faux, ou ADR violé>
   - **Règle** : <ADR 000X (intitulé), ou la convention de CLAUDE.md qui la porte>
   - **Correctif** : <la modification à faire, en 1-3 lignes ou un extrait de code>

#### 🟠 À corriger avant merge
<même format>

#### 🟡 Suggestions (non bloquant)
<titre — path:line — recommandation en 1 ligne>

#### 💬 Questions à l'auteur
<ce qui ne se tranche pas sans lui : intention, arbitrage, contexte hors diff>

#### ✍️ Style & altitude
<1-3 lignes agrégées : lisibilité, nommage, longueur des commentaires, découpage — ce qui n'a pas de conséquence fonctionnelle. « Rien à signaler » est une réponse valide.>
```

**Verdict et Réserves ouvrent la fiche** : ce qui bloque doit être lisible sans dérouler le tableau
ni les constats. **Réserves** = les constats 🔴 et 🟠 uniquement ; les 🟡 et 💬 n'y figurent pas. Un
verdict 🔴 a des réserves lui aussi (ses bloquants) : la ligne est renseignée dans tous les cas.

Une ligne du tableau sans objet se remplit `non concerné` (ex. **Schéma / migration** quand la PR ne
touche pas `infrastructure`) plutôt que de s'inventer une préoccupation. **Multi-tenant : non
concerné** — ce repo n'a pas de clé tenant (usage personnel, un seul utilisateur · ADR 0006).

Omettre les sous-sections de constats vides plutôt que d'écrire « aucun » — **sauf `✍️ Style &
altitude`**, toujours renseignée : c'est le seul endroit qui survit au plafond de constats (étape 6),
et la première chose qu'un relecteur humain voit. L'y agréger en 1-3 lignes, jamais en constats
numérotés.

Si **zéro constat**, remplacer `### Constats` par : `Aucun constat : le diff est conforme aux ADR et
conventions confrontés ci-dessus.` — et garder `✍️ Style & altitude`.

### Bloc 2 — Commentaire prêt à coller

Précédé de la frontière, non négociable :

```
---

## Commentaire à coller sur la PR
```

Puis, dans une fence ` ```markdown ` :

```markdown
<!-- pr-review -->
**Review** · <🟢 Mergeable / 🟡 Mergeable avec réserves / 🔴 À ne pas merger>

> **Réserves** — <titres des constats 🔴 et 🟠, 3 au plus, séparés par ` · ` · `+N autres` au-delà> (ou : `aucune`)

<1-2 phrases : ce que fait la PR + la raison du verdict>

<Si la CI n'est pas verte : « CI <rouge sur `<job>` / en attente> — hors verdict. »>

### 🔴 Bloquants

- **<titre>** (`path:line`) — <ce qui casse> → <correctif>

### 🟠 À corriger

- **<titre>** (`path:line`) — <ce qui casse> → <correctif>

### 🟡 Suggestions

- <titre> (`path:line`) — <recommandation>

### 💬 Questions

- <question>

### ✍️ Style & altitude

- <remarques de lisibilité agrégées, ou « rien à signaler »>

_Relecture statique : lecture de code + CI (read-only). Ni lint, ni test, ni build lancés — un 🟢 veut dire « rien trouvé en lecture », pas « ça compile »._
```

Le marqueur `<!-- pr-review -->` en tête rend l'opération rejouable (étape 7). Les sections de
constats vides s'omettent, sauf `✍️ Style & altitude`.

## Process

### 1. Rassembler le diff et le contexte

```bash
gh pr view <N> --json number,title,body,author,state,isDraft,baseRefName,headRefName,additions,deletions,files,commits,statusCheckRollup,labels
gh pr diff <N>
```

- `state` ≠ `OPEN` → le signaler et s'arrêter (rien à relire).
- Auteur Dependabot (ou label `dependencies`/`Dependabot`) → le dire et s'arrêter, sans fiche.
- `isDraft: true` → continuer, mais le mentionner dans le verdict (un draft se relit, ne se bloque
  pas).
- `baseRefName` ≠ `main` → le signaler (PR empilée : le diff peut inclure la PR parente).

Un diff > ~2000 lignes ne se lit pas d'un bloc : le lire **fichier par fichier**, priorisé par le
routage de l'étape 3.

### 2. Établir l'intention

Depuis le titre, le body et les messages de commit : **que cherche à faire cette PR ?** Sans
intention claire, une relecture dégénère en chasse au style.

- Vérifier le **titre Conventional Commits** : forme `type(scope): sujet`, impératif, minuscule,
  ~70 caractères. Le repo n'a **pas** de commitlint — se limiter à la forme de base. Le merge étant
  un squash (workflow Git de CLAUDE.md), ce titre devient le message de commit de `main` : il doit
  se tenir seul.
- Si l'intention reste indéterminable (body vide, commits « wip ») : ne pas s'arrêter — la noter en
  💬 et relire sur la seule base des ADR.

### 3. Confronter aux ADR et router le diff

Lis `CLAUDE.md` puis les ADR **utiles au diff** dans `docs/adr/**` — **lis les fichiers**, ne te fie
pas à un résumé de mémoire. Route chaque chemin touché vers les décisions qui le régissent :

| Chemin touché | ADR / convention à confronter |
|---|---|
| `libs/*/domain/**` | 0002 — dépend de **rien** : ni framework, ni ORM, ni HTTP, ni autre contexte. Pas de primitive nue : value objects validant à la construction. |
| `libs/*/application/**` | 0002 — dépend du `domain` seul, parle aux **ports**, jamais aux adapters. 0003 — pas d'event bus. |
| `libs/*/infrastructure/**` | 0002 — personne n'en dépend hors composition root. 0006 — le SQL, le schéma Postgres et les migrations vivent **ici**. |
| `apps/api/**` (orchestration) | 0003 — seul module à connaître plus d'un contexte ; ne manipule que des **DTO de frontière**, jamais un objet de domaine ; ne porte aucune règle exprimable dans un contexte. |
| `apps/web/**` | 0002 — feature-slice ; une slice n'importe pas l'intérieur d'une autre (passer par une lib partagée). |
| `libs/shared/**` | 0002 — importable par tous, n'importe **aucun** contexte ; une lib par sujet nommé, jamais `common`/`utils`. |
| Reconnaissance (adapter VLM) | 0005 — derrière `ShelfScannerPort` ; tests sur réponses enregistrées, non-régression photos réelles en test manuel séparé. |
| `package.json`, `.yarnrc.yml`, lockfile, Volta | 0001 — Yarn 4 (jamais Classic), pins exacts (jamais de plage), `nodeLinker: node-modules` (pas de PnP). |
| `vite.config.*`, `vitest.config.*`, générateurs Nx | 0007 — Vite/Vitest partout, ni webpack ni Jest ; `apps/api` passe par SWC (`unplugin-swc`) pour les métadonnées de décorateurs. |
| `docker-compose.yml`, scripts de déploiement | 0006 — base = Postgres managé (Neon) hors du bucket ; pas de montage gcsfuse ni SQLite comme base applicative. 0004 — Cloud Run + bucket. |
| Nouveau projet (app ou lib) | tags `type:` / `context:` / `scope:` posés dans `nx.tags` de son `package.json` — sinon il échappe aux frontières. |

**Fan-out.** Défaut : **relecture inline**, contexte partagé, sortie déterministe. Le déclencheur
est le **volume**, pas le nombre de zones touchées : au-delà de ~40 fichiers ou ~2500 lignes,
proposer un découpage en sous-agents par axe (correction · frontières Nx · tests · front), annoncer
le coût, et **attendre un go explicite**. ⚠️ Ne pas découper une feature qui traverse les couches
(un slice web + l'API + une migration, c'est sa forme normale) : c'est justement la **cohérence
inter-couches** qui donne les meilleurs constats. Après fan-out : dédupliquer, **re-vérifier chaque
🔴 soi-même**, et relire les jonctions entre axes (l'angle mort de tout découpage).

### 4. Lire le code — dans la version de la PR

Un hunk ment par omission. Pour chaque fichier non trivialement touché : **ouvrir le fichier
entier** autour du hunk.

> ⚠️ **Le checkout local n'est presque jamais la branche de la PR.** Un `Read` sur un chemin touché
> renvoie alors la version de **`main`**, sans les changements — de quoi fabriquer des constats
> entièrement faux (« le port n'est pas propagé » alors que la PR le propage). **Vérifie d'abord** :
> `git rev-parse --abbrev-ref HEAD` contre le `headRefName` de l'étape 1. S'ils diffèrent, récupère
> chaque fichier touché **dans sa version PR, sans checkout** :
>
> ```bash
> gh api "repos/{owner}/{repo}/contents/<path>?ref=<headRefName>" --jq .content | base64 -d > <scratchpad>/<basename>
> ```
>
> `{owner}/{repo}` est substitué par `gh` depuis le remote courant — ne jamais coder le repo en dur.
> Les fichiers **non touchés** par la PR (adapters voisins, entités, specs existantes) se lisent
> bien depuis le checkout local : ils sont identiques sur les deux branches.

Puis, pour chaque constat suspecté, va chercher la réfutation avant d'accuser :

- Un import qui semble interdit peut passer par une lib partagée légitime — vérifier la cible.
- Un use case qui semble parler à un adapter peut parler à un **port** injecté — `grep` le module.
- Un changement de comportement sans test visible peut être couvert par une spec existante — `grep`
  la spec du fichier et de ses appelants.
- Un pattern qui choque peut être **l'idiome du repo** — le compter (`grep -rl …`) avant d'en faire
  un constat. Un pattern présent dans des dizaines de fichiers n'est pas un défaut de cette PR.

C'est l'étape qui sépare une relecture utile d'une liste de faux positifs.

### 5. Les vérifications hors-diff (la vraie valeur)

Une lecture attentive trouve seule les bugs de logique locale. Ce qu'elle ne fait **jamais**
spontanément, c'est sortir du diff. Chaque vérification ci-dessous demande une action (un `grep`,
une lecture hors diff) et **son résultat s'inscrit dans la fiche, y compris « rien »**.

| # | Vérification | Action | Si positif |
|---|---|---|---|
| 1 | **Frontières Nx** — un import franchit une frontière d'architecture | `grep` les imports ajoutés dans `libs/*/domain` et `libs/*/application` ; croiser avec les règles `@nx/enforce-module-boundaries` de `eslint.config.mjs` | 🔴 → ADR 0002 |
| 2 | **Jumeaux** — le correctif laisse un chemin frère intact (adapter ↔ adapter, use case single ↔ bulk, VO ↔ VO sœur, slice web dupliquée) | `grep` la **signature du défaut** (pas le nom de fichier) dans tout le repo ; auditer chaque appelant de la méthode corrigée | 🟠 — corrigé, ou listé comme dette dans la description. Jamais silencieux. |
| 3 | **Comportement verrouillé par un test ?** | `grep` la spec du fichier **et** de ses appelants ; vérifier la présence des **cas d'erreur** | 🟠 si rien ne le verrouille → conventions de test (CLAUDE.md) |
| 4 | **Schéma / entité ↔ migration** — entité ou schéma Postgres modifié dans `infrastructure` sans migration | croiser `git diff --name-only` avec le répertoire de migrations d'`infrastructure` | 🔴 sans discussion (schéma non auto-synchronisé · ADR 0006) |
| 5 | **APIs verrouillées introduites** — Yarn Classic, plage de versions, PnP, webpack, Jest, event bus (`@nestjs/cqrs`, EventEmitter applicatif), montage gcsfuse du bucket ou SQLite comme base applicative | `grep` le diff pour ces signatures | 🔴 → ADR 0001 / 0003 / 0006 / 0007 |
| 6 | **`as` interdit** — une assertion de type introduite | `grep` le diff pour ` as ` (hors `as const`) | 🟠 → convention CLAUDE.md (`assertionStyle: 'never'`) ; proposer `satisfies` ou un type guard |

### 6. Filtrer les constats avant de les écrire

Un constat entre dans la fiche seulement s'il passe les quatre tests :

1. **Localisé** — un `path:line` exact (le vrai fichier, pas la ligne du diff).
2. **Étayé** — le fichier entier a été lu (étape 4), le `grep` de confirmation est fait. Si la
   vérification est impossible, le formuler en 💬 (« je ne trouve pas le port pour X, injecté
   ailleurs ? »), pas en constat.
3. **Conséquent** — un scénario concret : entrée/état → comportement faux, ou ADR nommément violé.
   Sans conséquence énonçable, c'est au mieux un 🟡.
4. **Réfuté d'abord** — « et si c'était intentionnel ? le code alentour le gère-t-il déjà ? » Un
   constat qui ne survit pas à cette question est supprimé.

Puis trier du plus grave au moins grave et **s'arrêter à ~10 constats**. Une fiche de 40 lignes de
style enterre le seul bloquant qui compte. Ce que le plafond coupe ne disparaît pas : tout ce qui
touche lisibilité, nommage, découpage part **agrégé** dans `✍️ Style & altitude`.

### 6b. Second avis à froid (sous-agent aveugle) — optionnel

Cette relecture est **guidée** par les ADR : c'est sa force et son biais. Elle voit ce que les ADR
décrivent et peut rater ce qu'un lecteur neuf verrait tout de suite. **Déclencher seulement si un
critère d'enjeu OU de doute est rempli** — sur une PR ordinaire et propre, ça ne produit que du
bruit :

- **Enjeu** : le diff touche l'adapter VLM (`ShelfScannerPort`), la persistance Postgres, un schéma,
  ou fait > ~300 lignes.
- **Doute** : au moins un constat fini en 💬 faute de vérifiabilité ; un constat écarté sur une
  hypothèse non prouvée du comportement d'un tiers ; verdict 🟢 sans aucun constat sur un diff
  substantiel ; intention indéterminable ; un fichier clé illisible.

**Proposer et attendre le go.** Un sous-agent `general-purpose`, en avant-plan, avec un prompt qui
garantit l'**aveuglement** : lui donner le numéro de PR seul (jamais mes constats), lui interdire de
lire `.claude/skills/**`, lui rappeler de récupérer les fichiers en **version PR**
(`gh api …?ref=<headRefName>`), lui **interdire toute écriture**. Sa sortie n'est **pas** autorité :
dédupliquer contre mes constats, repasser chaque **nouveau** constat par les quatre tests de
l'étape 6 (vérifié par moi), ne **jamais** le publier séparément. Renseigner le champ **Second avis
à froid** dans tous les cas.

### 7. Verdict, puis poster (sur go)

Le verdict se lit **sur le code**, jamais sur la CI :

| Verdict | Condition |
|---|---|
| 🔴 **À ne pas merger** | ≥ 1 constat 🔴 |
| 🟡 **Mergeable avec réserves** | pas de 🔴, ≥ 1 constat 🟠 |
| 🟢 **Mergeable** | ni 🔴 ni 🟠 |

**La CI ne colore pas le verdict.** Une CI rouge/en attente est reportée dans le champ **CI** et au
pied du commentaire, pas dans le verdict. Mais elle n'est pas neutre : si sa cause est un défaut du
diff, ce défaut entre comme constat 🔴/🟠 et le verdict bouge **par le code**. Une CI verte ne
rachète aucun constat.

**Forçages** :

- Entité/schéma modifié **sans** migration dans `infrastructure` → 🔴 (ADR 0006).
- Logique métier ou correctif de bug **sans** test → minimum 🟠 (donc jamais 🟢).
- Un jumeau identifié, ni corrigé ni signalé → minimum 🟠.
- Draft → verdict indicatif, l'écrire (« PR en draft : verdict indicatif »).

Le verdict est **consultatif** : il ne pose aucun label, ne repasse pas la PR en draft, ne bloque
rien — la décision de merger reste humaine.

**Poster (sur go explicite seulement).** Le marqueur `<!-- pr-review -->` rend l'opération
rejouable :

```bash
# Un commentaire de review existe-t-il déjà ?
gh pr view <N> --json comments \
  --jq '.comments[] | select(.body | startswith("<!-- pr-review -->")) | {id, url}'
```

- **Aucun** → `gh pr comment <N> --body-file <fichier>`
- **Il en existe un** → le mettre à jour plutôt que d'en empiler un second :
  `gh api -X PATCH /repos/{owner}/{repo}/issues/comments/{id} -F body=@<fichier>`

Le corps contient du markdown multiligne : passer par `--body-file` / `-F body=@…`, jamais par
`--body` inline.

## Interdits

- **Aucune écriture GitHub sans go explicite.** Défaut : fiche + commentaire dans la conversation,
  rien de posté.
- Après un go : `gh pr comment` / le PATCH du commentaire existant, **et rien d'autre**.
- **Toujours interdits**, même après un go : `gh pr review --approve`, `--request-changes`,
  `gh pr merge`, `gh pr close`, `gh pr edit`, l'auto-merge, tout changement de label/assignee. La
  décision GitHub reste à l'auteur.
- **Ne modifie aucun fichier, ne pousse aucun commit.** Ce skill relit et propose des correctifs en
  extraits ; l'application passe par `pr-review-triage` ou par l'implémentation à la main.
- **N'installe rien, ne lance ni lint, ni test, ni build.** La CI se **lit** (read-only) ; elle ne
  se reproduit pas. Conséquence assumée sur l'honnêteté : un 🟢 veut dire « rien trouvé en lecture »,
  pas « ça compile ».
- **Ne signale rien que tu n'as pas vu.** Pas de remarque déduite du titre ou d'un nom de fichier.
  Une remarque fausse coûte plus cher que pas de remarque : elle décrédibilise tout le reste.
- **Le sous-agent du second avis (étape 6b) n'écrit rien** : ni GitHub, ni fichier.
- Toujours produire la **fiche avant** le commentaire, séparés par `---` + `## Commentaire à coller
  sur la PR`.

## Composition

| Skill | Rôle |
|---|---|
| `pr-review` | **produit** la review (ce skill) |
| `pr-review-triage` | **traite** une review déjà postée : vérifie chaque point, corrige, répond |
| `create-pr` | ouvre la PR — en amont de tout |
