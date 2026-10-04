---
name: pr-review
description: >-
  Relit une pull request du dépôt courant, ou la branche courante contre la branche par défaut,
  en confrontant chaque changement aux règles que ce dépôt a lui-même écrites (.claude/rules,
  .github/instructions, et les docs que son CLAUDE.md désigne). Agnostique du dépôt, il découvre
  ces règles et y route le diff, sans jamais supposer une stack. Produit une fiche de review
  classée par sévérité (🔴 bloquant, 🟠 à corriger, 🟡 suggestion, 💬 question) et un commentaire
  prêt à coller, ouvert par le verdict et ses réserves. Le verdict porte sur le CODE, jamais sur
  l'état de la CI. Les vérifications locales restent ciblées et sur demande. À utiliser quand on
  dit « relis la PR 42 », « review cette PR », « check ma branche avant de la pousser »,
  « qu'est-ce qui cloche dans cette PR », qu'on colle un lien de PR en demandant un avis, ou
  `/pr-review <PR#>`. Ne merge jamais, n'approuve jamais, ne poste qu'après go explicite.
argument-hint: <PR# | rien = branche courante contre la branche par défaut>
---

# Relecture de pull request

Relecture pilotée par **les règles écrites du dépôt relu**. La valeur de ce skill n'est pas la
checklist générique (lint, tests, types : la CI les couvre déjà) mais la **confrontation du diff aux
règles que le dépôt a écrites** et aux bugs qu'il a déjà payés, consolidés dans ses `.claude/rules/**`
(et `.github/instructions/**`, et les docs que son `CLAUDE.md` désigne).

Le skill est **agnostique du dépôt** : il résout le dépôt cible dynamiquement et **découvre** ses
règles à la relecture. Il ne suppose jamais une stack, un nom de règle, une clé de tenant ou une
convention de migration : tout cela vient du dépôt relu. Il ne porte aucun critère propre. Un dépôt
sans règle écrite n'obtient qu'une relecture sur l'intention, le titre et les catégories génériques.

> **Une convention que le dépôt veut voir appliquée en review doit être écrite dans ses règles.** Le
> skill ne cache aucune liste de conventions maison (décorateurs, logger, DI, style de commentaire…) :
> il confronte ce que les règles énoncent, rien de plus. Une remarque sans règle citée ni conséquence
> concrète est une opinion : elle descend en `🟡` ou en `✍️`, jamais en bloquant.

## Quand l'utiliser

- `/pr-review <PR#>` (ex. `/pr-review 42`), ou `/pr-review` sans argument : la **branche courante**
  contre la branche par défaut, avant de la pousser.
- « relis la PR », « reviewe cette PR », « regarde ma branche avant que je la pousse », « qu'est-ce
  qui cloche là-dedans », un lien de PR du dépôt courant collé avec une demande d'avis.

**Ne pas l'utiliser pour** :

- une PR **Dependabot** (auteur `app/dependabot`, ou label `Dependabot` / `dependencies`) : le dire
  et s'arrêter, sans fiche ; la montée de dépendance se triage avec l'outil du dépôt prévu pour ça.
- **traiter** une review déjà postée → `pr-review-triage`.
- **écrire** la description d'une PR ou **l'ouvrir** → `create-pr`.
- **corriger** ce que la review remonte : ce skill relit, il ne modifie pas le code.

## Langue des livrables

La fiche et le commentaire sont écrits dans la **langue du dépôt** (français par défaut ici). Les gabarits
ci-dessous sont donnés en français ; ne les traduire que si la convention du dépôt est une autre langue.

## Déroulé

**Tout ce qui peut s'écrire en script est un script.** Les scripts rassemblent les faits, font les
`grep`, appliquent les planchers et mettent en forme ; toi, tu juges. Rien de ce qu'un script établit ne
se refait à la main, et rien de ce qui demande du jugement ne se délègue à un `grep`. Si tu te surprends
à refaire à la main un calcul, un `grep` ou une mise en forme que le dépôt de skills pourrait écrire une
fois pour toutes, c'est le script qui manque : ne pas l'improviser, le signaler.

| # | Étape | Qui |
|---|---|---|
| 0 | Résoudre le dépôt, lire ses règles sur la branche de base | script `collect.sh` (via `rules.py`) |
| 1 | Rassembler PR ou branche, diff, fichiers en version PR, faits mécaniques | script `collect.sh` (via `analyze.py`) |
| 2 | Établir l'intention | jugement |
| 3 | Lire les règles routées vers le diff | jugement |
| 4 | Lire le code, chercher la réfutation | jugement |
| 5 | Trancher les vérifications hors-diff | jugement, sur les résultats bruts de l'étape 1 |
| 6 | Garde-fous : CI lue et cause d'un job rouge récupérée ; vérifications locales ciblées, sur go | scripts `collect.sh` et `local-gate.sh` ; décider de lancer ou non : jugement |
| 7 | Filtrer, classer, plafonner les constats | jugement |
| 7b | Second avis à froid, si un critère est rempli | jugement (proposer, attendre le go) ; prompt aveugle par script `blind-prompt.sh` |
| 8 | Écrire `review.json` | jugement |
| 9 | Valider, appliquer les planchers, calculer le verdict, rendre fiche et commentaire | script `render.py` |
| 10 | Poster, sur go explicite | script `post.sh` |

## 0 et 1. Résoudre, découvrir, rassembler

```bash
${CLAUDE_SKILL_DIR}/collect.sh [PR#]
```

- **Mode PR** (un numéro) : relit cette PR. **Mode local** (rien) : relit la branche courante contre la
  branche par défaut, résolue par `gh` (jamais supposée `main` ou `master`) ; refusé sur la branche par
  défaut elle-même. Aucun mode n'exige un arbre propre : tout est en lecture.
- Le dépôt cible est résolu par `gh` depuis le remote courant, jamais écrit en dur.
- Les **règles** sont lues sur la **branche de base** de la PR, jamais sur la branche relue : son auteur
  pourrait sinon réécrire ce qui le juge. Le script copie sous `WORKDIR/rules/` les `.claude/rules/**`,
  les `.github/instructions/**`, `CLAUDE.md` / `AGENTS.md`, les docs que ces fichiers désignent (ADR,
  guides, politiques), et une éventuelle config commitlint.

Il écrit dans un répertoire de travail (dernière ligne `WORKDIR=…`) : `pr.json`, `diff.patch`,
**chaque fichier touché dans sa version PR** sous `head/`, `rules/`, `rules.json` et `facts.md`, qu'il
affiche :

- **Arrêts** : PR non ouverte ou Dependabot → s'arrêter. Draft → verdict indicatif. Base ≠ branche par
  défaut → PR empilée, le diff peut inclure la PR parente : le signaler.
- **Taille** : lecture fichier par fichier au-delà de 2000 lignes ; fan-out à proposer au-delà de 40
  fichiers ou 2500 lignes ; critères d'enjeu candidats du second avis.
- **Titre** : la forme `type(scope): sujet`, et la config commitlint du dépôt si elle existe (c'est
  **son** enum de types et de scopes qui fait foi, jamais une liste ici). L'impératif et la capacité du
  titre à se tenir seul (il devient le message de commit au squash) restent à juger.
- **CI** : verte, rouge sur tel job, en attente, non lancée.
- **Règles** : lesquelles s'appliquent à quel fichier touché, d'après les globs `paths` / `applyTo` de
  leur frontmatter ; celles sans glob valent partout.
- **Vérifications hors-diff** : les `grep` sont faits (voir l'étape 5) et quelles règles du dépôt les
  rendent pertinentes.
- **Cause d'un job rouge** : `collect.sh` récupère la fin du log des runs en échec (`WORKDIR/ci-<run>.log`).

Sans règle écrite sur la base, `facts.md` le dit : le dire aussi dans la fiche, et relire sur la seule
base de l'intention, du titre et des catégories génériques qui restent valables (couverture de test,
jumeaux par bon sens).

## 2. Établir l'intention

Depuis le titre, le body et les messages de commit : **que cherche à faire cette PR ?** Sans intention
claire, une relecture dégénère en chasse au style.

- Si le dépôt a une convention de **document de conception** (un dossier de conceptions, des specs),
  confronter le diff à ce qui était prévu : un écart de périmètre est une question 💬, pas un constat.
- Si l'intention reste indéterminable (body vide, commits « wip »), ne pas s'arrêter : la noter en 💬 et
  relire sur la seule base des règles.
- **Aucun numéro de ticket n'est attendu dans le code** : la traçabilité vit dans la branche, le commit
  et la PR. Si les règles du dépôt le disent, un `// TICKET-1234` introduit par le diff est un 🟠, mais
  seulement contre une règle que le dépôt a réellement écrite.

## 3. Lire les règles routées vers le diff

**Lis les fichiers** de `WORKDIR/rules/` que le routage de `facts.md` désigne, ne te fie à aucun
résumé de mémoire. Le routage dit *quoi* ouvrir ; ce qui est interdit ou exigé, c'est leur texte qui le
dit. Pour chaque fichier touché, lis les règles qui s'y appliquent, puis les docs qu'elles désignent
(l'ADR derrière une règle, le guide d'architecture, la politique de types) quand le constat en dépend.

Les règles sont **l'index** des familles de constats du dépôt (correction SQL/ORM, accès et
permissions, performance, tests creux, pièges front, typage, doublons de traduction) : ne porte pas
d'index figé en tête, lis-les.

**Fan-out.** Par défaut, **relecture inline**, contexte partagé, sortie déterministe. Le déclencheur est
le **volume**, pas le nombre de zones touchées : au-delà de ~40 fichiers ou ~2500 lignes de diff,
proposer un découpage en sous-agents par axe (correction · performance · front · tests · accès et
multi-tenant, selon ce que les règles du dépôt couvrent), annoncer le coût et **attendre un go explicite**.

> ⚠️ **Ne pas découper une feature qui traverse les couches.** Une feature normale touche plusieurs
> zones à la fois (une lib front, l'API, une migration, des traductions) : c'est sa forme habituelle,
> pas un signal de complexité. Et c'est précisément la **cohérence entre ces zones** qui donne les
> constats les plus utiles : un correctif appliqué à 2 écrans sur 3, une garde présente sur le chemin
> bulk et absente du chemin unitaire, un invariant front que l'API ne tient pas. Un sous-agent par zone
> est aveugle à tout cela. Découper se justifie quand la PR contient des **travaux indépendants**
> (plusieurs features, ou un gros refactor et une feature), jamais pour un sujet unique étalé sur
> plusieurs couches.

Après fan-out : dédupliquer, **re-vérifier chaque 🔴 soi-même** avant de le publier (un constat de
sous-agent non re-vérifié n'entre pas dans la fiche), et relire soi-même les jonctions entre axes.

## 4. Lire le code, pas seulement le diff, en version PR

Un hunk ment par omission. Pour chaque fichier non trivialement touché : **ouvrir le fichier entier**
dans `WORKDIR/head/`.

> ⚠️ **Le checkout local n'est presque jamais la branche de la PR.** Lire un chemin touché depuis le
> disque renvoie la version de la branche par défaut, sans les changements : de quoi fabriquer des
> constats entièrement faux (« le manager n'est pas propagé » alors que la PR le propage). Les fichiers
> **non touchés** (services voisins, entités, specs existantes) se lisent bien depuis le checkout : ils
> sont identiques sur les deux branches. En mode local, la branche courante est la branche relue.

Pour chaque constat suspecté, va chercher la réfutation avant d'accuser :

- Un `WHERE` qui semble sans clé de portée peut en hériter d'un scope de base : vérifier.
- Un champ de resolver qui semble sans batch loader peut en avoir un injecté plus haut : `grep` le module.
- Un changement de comportement sans test visible peut être couvert par une spec existante : `grep`
  la spec du fichier et de ses appelants.
- Un cast ou un motif qui choque peut être **l'idiome du repo** : le compter (`grep -rl …`) avant d'en
  faire un constat. Un motif présent dans des dizaines de fichiers n'est pas un défaut de cette PR.
- Un import qui semble interdit peut passer par une lib partagée légitime : vérifier la cible.

C'est l'étape qui sépare une relecture utile d'une liste de faux positifs.

## 5. Trancher les vérifications hors-diff

Une lecture attentive du diff trouve seule les bugs de logique locaux. Ce qu'elle ne fait **jamais**
spontanément, c'est sortir du diff. Ces vérifications exigent une action hors diff, et c'est là la
valeur propre du skill. **Chacune ne s'applique que si les règles du dépôt la rendent pertinente** ; la
fiche dit ce qu'elle a donné, y compris « rien ».

**`analyze.py` a déjà fait les `grep`** et les a mis dans `facts.md`, sous les numéros ci-dessous. Chaque
résultat reste un **candidat** : il reste à le confirmer par la lecture de l'étape 4, et à trancher s'il
est un constat. Seule la vérification 1 n'est pas scriptée : la signature d'un défaut, aucun script ne
la connaît.

| # | Vérification | S'applique si | Action | Si confirmé |
|---|---|---|---|---|
| 1 | **Jumeaux** : le correctif laisse un chemin frère intact (legacy ↔ V2, PDF ↔ XLSX ↔ CSV, `getX` ↔ `getXWithAccess`, bulk ↔ unitaire, numérateur ↔ dénominateur…) | le dépôt a une règle **fix-twins** | **Jugement** : déduire la **signature** du défaut, puis la `grep` (pas le nom de fichier) dans tout le repo ; auditer chaque appelant de la méthode corrigée | 🟠 : corrigé dans la PR, ou **listé comme dette** dans la description. Jamais silencieux. |
| 2 | **Comportement verrouillé par un test ?** | toujours (générique) | **Scripté** : tests touchés et specs existantes qui mentionnent chaque fichier source. À juger : le test couvre-t-il le changement, **cas d'erreur** compris ? | 🟠 si rien ne le verrouille, contre la règle de test du dépôt |
| 3 | **Schéma / entité ↔ migration** : une entité ou une colonne touchée sans migration | **seulement si le dépôt écrit ses propres migrations** (un schéma vendoré n'en a pas : le dire) | **Scripté** : schéma et entités candidats croisés avec les migrations touchées. À juger : le fichier modifie-t-il vraiment le schéma ? | 🔴 sans discussion (le schéma n'est pas auto-synchronisé) |
| 4 | **Clé de tenant dans chaque branche** après tout refactor de `WHERE` / `OR` / parenthèses | **seulement si les règles définissent une clé de tenant** | **Scripté** : clés candidates lues dans les règles, clauses `WHERE` ajoutées dont la ligne n'a pas la clé. À juger : lire la méthode entière, pas le hunk, et les **lectures** voisines du même service (la clé peut venir d'un scope de base) | 🔴 sur une branche du diff · 🟡 sur un trou préexistant hors diff |
| 5 | **API verrouillée ou interdite introduite** | **seulement si les règles verrouillent une stack** | **Scripté** : les mots entre backticks des lignes d'interdit des règles sont cherchés dans les lignes ajoutées. À juger : la ligne introduit-elle l'API ou la mentionne-t-elle ? Lire aussi la règle pour les interdits qu'aucun mot ne désigne | 🔴 → la règle de verrou du dépôt |
| 6 | **Performance / chargement de données** : N+1, écritures non groupées, `Promise.all` non borné, sur-chargement | **seulement si les règles couvrent la performance** | **Scripté** : motifs de boucle asynchrone et de `Promise.all` ajoutés. À juger : `grep` le batch / loader existant avant d'en exiger un nouveau ; lire la règle pour les motifs propres au dépôt | selon le plancher de la règle (souvent 🟠) |
| 7 | **Réutiliser plutôt que dupliquer** : une clé de traduction ou de message ajoutée duplique un **terme** (la valeur, pas seulement la clé) déjà présent sous une autre clé | le diff touche des catalogues de traduction ou de messages | **Scripté** : pour chaque clé ajoutée, sa **valeur** (sans casse ni ponctuation finale) cherchée dans tous les catalogues, et les clés définies deux fois dans un objet JSON. À juger : le même usage justifie-t-il de réutiliser la clé ? | 🟠 si la même clé est définie deux fois dans un catalogue (la dernière gagne en silence) · 🟡 si une nouvelle clé duplique un terme existant : proposer de réutiliser l'existante. Même réflexe pour une constante, une valeur d'enum ou un utilitaire qui en répète un autre. |

## 6. Garde-fous : la CI d'abord

La CI du dépôt fait déjà tourner les contrôles génériques (lint, tests, build, code mort…) sur les
projets affectés. **Ne pas la reproduire en local.** `facts.md` donne son état (lu depuis
`statusCheckRollup`) :

- tout `SUCCESS` → `verte` ; premier `FAILURE` / `ERROR` → `rouge sur <job>` ; au moins un
  `PENDING` / `QUEUED` → `en attente`.
- sur un job rouge, la fin de son log est déjà dans `WORKDIR/ci-<run>.log` (voir `facts.md`). Cette
  cause décide s'il existe un constat (étape 8) ; elle ne colore pas le verdict.

Ne jamais relancer des checks, ni `gh pr checks --watch`.

**Vérifications locales ciblées.** Elles se découvrent dans les scripts du `package.json` et dans le
`CLAUDE.md` du dépôt, sans supposer de noms. Avant d'en lancer une, **annoncer son ordre de grandeur de
coût**, jamais après. Tout ce qui dure **≥ ~10 min**, ou exige un **checkout de la branche**, demande un
**go explicite** : voir [`references/local-gates.md`](references/local-gates.md). C'est `local-gate.sh`
qui les lance : `status` dit d'abord si le checkout courant mesure bien la PR et liste les scripts du
`package.json` ; `checkout` et `worktree` exigent `--go`, refusent un arbre sale et **rendent toujours**
l'état de départ.

> ⚠️ Ces commandes mesurent le **checkout courant**. Si `local-gate.sh status` dit qu'il n'est pas la
> branche de la PR, leur résultat ne dit rien de la PR : ne pas les lancer, et l'écrire dans la fiche
> plutôt que laisser croire qu'une vérification a eu lieu.

Le champ **Vérifications lancées** se remplit honnêtement : « lecture de code seule » est une réponse
valide ; affirmer une vérification qui n'a pas eu lieu ne l'est pas.

## 7. Filtrer les constats

Un constat entre dans la fiche seulement s'il passe les quatre tests :

1. **Localisé** : un `path:line` exact (le vrai fichier, pas la ligne du diff).
2. **Étayé** : le fichier entier a été lu, le `grep` de confirmation est fait. Si la vérification est
   impossible, le formuler en 💬 (« je ne trouve pas de loader pour X, injecté ailleurs ? »).
3. **Conséquent** : un scénario concret, entrée ou état → comportement faux. Sans conséquence énonçable,
   c'est au mieux un 🟡.
4. **Réfuté d'abord** : « et si c'était intentionnel ? le code alentour le gère-t-il déjà ? » Un constat
   qui ne survit pas à cette question est supprimé.

Puis trier du plus au moins grave et **s'arrêter à ~10 constats**. Une fiche de 40 lignes de style enterre
le seul bloquant qui compte. Ce que le plafond coupe ne disparaît pas : lisibilité, nommage, ordre des
opérations et découpage partent **agrégés** dans `✍️ Style & altitude`, en 1-3 lignes. C'est le premier
réflexe d'un relecteur humain et le premier angle mort d'une relecture à checklist : la section est
**toujours** renseignée, même à « rien à signaler ».

## 7b. Second avis à froid, optionnel

Cette relecture est **guidée** : le routage et les vérifications orientent le regard, c'est sa force et
son biais. Elle voit ce que les règles décrivent et peut rater ce qu'un lecteur neuf verrait tout de
suite. Le contrepoids est un sous-agent qui relit la même PR **sans** les règles et **sans** connaître
les constats déjà faits.

**Déclencher si _un seul_ critère d'enjeu OU _un seul_ critère de doute est rempli.** Pas par réflexe :
sur une PR ordinaire et propre, ça ne produit que du bruit.

**Critères d'enjeu** (mécaniques, évaluables dès l'étape 3, pilotés par les règles du dépôt) :

- le diff touche l'**accès ou les permissions** : gardes, décorateurs public/authentifié, bouclier
  d'autorisation, SSO, clé d'API publique, selon ce que les règles couvrent comme contrôle d'accès ;
- le diff modifie du code **multi-tenant** : un `WHERE` où figure (ou devrait figurer) la clé de tenant
  du dépôt (critère ignoré sans clé de tenant) ;
- **migration destructive ou irréversible** : `DROP` / `ALTER TYPE` / durcissement `NOT NULL`, ou un
  `down()` volontairement vide, seulement sur un dépôt qui écrit ses migrations ;
- **écriture ou suppression de masse** : script de rattrapage, `deleteAll`, mise à jour en bloc,
  migration de données ;
- **volume** : au-delà de ~40 fichiers ou ~2500 lignes (même seuil que le fan-out, les deux se cumulent ;
  le second avis ne remplace pas le découpage) ;
- le diff touche un **fichier déjà brûlé** : `facts.md` (vérification 0) dit quels fichiers touchés sont
  cités dans les règles ou les docs du dépôt, dont ses catalogues de bugs ou de performance.

**Critères de doute** (observables, évaluables après l'étape 7) :

- au moins un constat fini en 💬 **faute de vérifiabilité** ;
- un constat **écarté sur une hypothèse non prouvée** du comportement d'un tiers (montage paresseux d'un
  volet d'UI, un refetch, ce que rend un `save()` d'ORM, un mode de résolution) : un verdict qui repose
  sur « je pense que la lib fait ça » est un doute, pas une conclusion ;
- verdict **🟢 sans aucun constat sur un diff substantiel** (> ~300 lignes) : possible, mais c'est le
  profil typique d'une relecture qui n'a rien vu ;
- **l'intention n'a pas pu être établie** : la relecture a tourné à l'aveugle sur les seules règles ;
- un fichier clé n'a **pas pu être lu** (droits, binaire, généré) ;
- deux lectures **contradictoires** du même code semblent aussi plausibles l'une que l'autre.

**Lancer : proposer et attendre le go**, comme le fan-out. Annoncer le ou les critères déclenchés, puis
lancer sur accord. Un sous-agent `general-purpose`, en avant-plan (son résultat est nécessaire avant le
verdict). **Son prompt vient de `${CLAUDE_SKILL_DIR}/blind-prompt.sh <PR#>`**, ne pas le réécrire : le script
garantit l'**aveuglement** par construction, et il fixe :

- lui donner **le numéro de PR seul** : jamais tes constats, jamais ton verdict, jamais un axe à
  explorer. Un sous-agent à qui on souffle la réponse la confirme ;
- lui interdire explicitement de lire `.claude/rules/**` et `.claude/skills/**` : sa valeur est une
  autre focale, pas un refaire du travail. C'est le seul cas où une relecture non guidée, sans règle,
  est voulue ;
- lui rappeler de lire les fichiers en **version PR** (`gh api "repos/{owner}/{repo}/contents/<path>?ref=<headRefName>"`),
  sinon il relit la branche par défaut et invente des constats ;
- lui **interdire toute écriture** : ni `gh pr comment` / `review` / `merge`, ni édition de fichier. Il
  rend une liste de constats `path:line` + conséquence + sévérité proposée, rien d'autre.

**Sa sortie n'est pas autorité** : c'est un avis non instruit, qui ignore les verrous de stack et les bugs
payés du dépôt. (1) **Dédupliquer** avec les constats déjà faits : ce qu'il retrouve est une
convergence, pas une confirmation. (2) Chaque **nouveau** constat repasse par les quatre tests de
l'étape 7, **vérifié par toi** : un constat non re-vérifié n'entre jamais dans la fiche. (3) Ce qu'il
rate n'est pas un signal : il n'a pas les règles. (4) **Ne jamais le publier séparément** : deux
commentaires de review sur une PR, c'est du bruit pour les relecteurs ; une fiche, une synthèse.

Renseigner le champ **Second avis à froid** dans tous les cas : `non déclenché`, ou `déclenché
(<critère>) · N constats · M retenus après vérification`.

## 8. Écrire `review.json`

Dans `WORKDIR/review.json`. Tout ce qui est mécanique (périmètre, titre, CI, verdict, réserves,
compteurs) est calculé par `render.py` : ne l'y mets pas.

**Les lignes suivent le dépôt.** Garder la ligne quand le dépôt a ce souci, sinon la remplir par
`non concerné` ou la formule exacte ci-dessous. Ne jamais fabriquer un souci que les règles du dépôt ne
déclarent pas.

```json
{
  "intention": "ce que la PR cherche à faire, en 1 phrase",
  "contexts": "contextes bornés, libs, apps concernés",
  "migrations": "non concerné | ce repo n'écrit pas ses migrations (schéma vendoré) | N migration(s) : <nom> · réversible / ⚠️ non réversible | ⚠️ entité modifiée SANS migration",
  "tests": "N test(s) ajoutés/modifiés · couvre <quoi> | ⚠️ aucun test sur <ce qui n'est pas couvert>",
  "locks": "respectés | 🔴 <API verrouillée par les règles> détectée | non concerné",
  "tenant": "<clé du dépôt> présente dans toutes les branches vérifiées | 🔴 fichier:ligne | non concerné (pas de clé de tenant dans les règles)",
  "twins": "aucun | <jumeau : chemin> · corrigé / NON corrigé | pas de règle fix-twins dans ce repo",
  "rules": "fichiers de règles (et instructions, docs) réellement lus pour cette review",
  "second_opinion": "non déclenché | déclenché (<critère>) · N constats · M retenus",
  "summary": "1-2 phrases pour le commentaire : ce que fait la PR + la raison du verdict",
  "local_checks": "optionnel : `<commande>` → <résultat>, si une vérification locale a été lancée",
  "findings": [
    {"severity": "blocker", "title": "titre court", "location": "path:line",
     "breaks": "entrée/état → comportement faux", "rule": "règle citée (`.claude/rules/... § N`, ou la source du dépôt qui la porte)",
     "fix": "la modification, en 1-3 lignes"},
    {"severity": "major", "…": "mêmes champs que blocker"},
    {"severity": "minor", "title": "…", "location": "path:line", "fix": "recommandation en 1 ligne"},
    {"severity": "question", "title": "ce qui ne se tranche pas sans l'auteur"}
  ],
  "style": ["lisibilité, nommage, longueur des commentaires, ordre des opérations, découpage — agrégé, 1-3 lignes ; liste vide = rien à signaler"]
}
```

## 9. Rendre

```bash
python3 ${CLAUDE_SKILL_DIR}/render.py <WORKDIR>
```

Valide `review.json` et refuse s'il manque quelque chose : champs, sévérités, **`path:line` qui doit
exister** (fichier touché lu en version PR, ligne dans ses bornes), et **planchers de sévérité**
(ci-dessous). Puis
**calcule le verdict sur le code, jamais sur la CI**, et affiche la fiche, la frontière `---` /
`## Commentaire à coller sur la PR`, puis le commentaire, écrit aussi dans `WORKDIR/comment.md`.
Recopier cette sortie telle quelle dans la conversation. **Aucun fichier n'est créé dans le dépôt** :
`WORKDIR` est hors de lui.

**Verdict et Réserves ouvrent la fiche** : ce qui bloque doit se lire sans dérouler le tableau ni les
constats. Les **Réserves** sont les constats 🔴 et 🟠 uniquement ; les 🟡 et les 💬 n'y figurent pas.
Un verdict 🔴 a lui aussi des réserves (ses bloquants) : la ligne est renseignée dans tous les cas.

| Verdict | Condition |
|---|---|
| 🔴 **Changements demandés** | au moins un constat 🔴 |
| 🟡 **Approuvable avec réserves** | aucun 🔴, au moins un 🟠 |
| 🟢 **Approuvable** | ni 🔴 ni 🟠 |

**La CI ne colore pas le drapeau.** Un job rouge ou en attente est dit dans le champ **CI** et au pied
du commentaire, pas dans le verdict. Elle n'est pas neutre pour autant : en trouver la cause (étape 6).
Si c'est un défaut de code du diff, il entre comme constat 🔴/🟠 et le verdict bouge **par le code**. Si
c'est un flaky, de l'infra ou un rouge déjà présent sur la branche par défaut, l'écrire et laisser le
verdict. Symétriquement, une CI verte ne rachète aucun constat : un 🔴 reste 🔴.

**Planchers**, appliqués par `render.py` à partir des champs de `review.json` : il refuse un verdict qui
les contredit, il ne les corrige pas. Un champ qui rapporte un problème commence par son marqueur
(`🔴` ou `⚠️`) ou dit `SANS migration` / `NON corrigé` :

- entité ou schéma modifié **sans** migration (`migrations`) → au moins un 🔴, sans discussion,
  **seulement** sur un dépôt qui écrit ses migrations ; un `🔴` dans `locks` ou `tenant` aussi ;
- logique métier ou correctif de bug **sans** test (`tests` commence par `⚠️`) → au moins un 🟠 (donc
  jamais 🟢) ;
- un jumeau identifié, ni corrigé ni signalé (`twins` dit `NON corrigé`) → au moins un 🟠 ;
- draft → le verdict reste indicatif, l'écrire (« PR en draft : verdict indicatif ») : `render.py` le fait.

Le verdict mesure l'état du diff, **pas** la valeur du travail : le formuler factuellement. Il est
**consultatif** : il ne pose aucun label et ne bloque rien.

## 10. Poster (sur go explicite seulement)

```bash
${CLAUDE_SKILL_DIR}/post.sh <PR#> [WORKDIR]
```

Crée le commentaire, ou met à jour celui qui porte déjà le marqueur `<!-- pr-review -->` plutôt que
d'en empiler un second. Pas de PR en mode local : rien à poster, la fiche reste dans la conversation.

## Interdits

- **Aucune écriture GitHub sans go explicite.** Défaut : fiche + commentaire dans la conversation, rien
  de posté.
- Après un go : `post.sh`, **et rien d'autre**.
- **Toujours interdits**, même après un go : `gh pr review --approve`, `--request-changes`,
  `gh pr merge`, `gh pr close`, `gh pr edit`, l'auto-merge, tout changement de label ou d'assignee.
  Approuver engage une responsabilité humaine ; demander des changements par l'API bloque le flux de
  quelqu'un d'autre. La décision GitHub reste à l'auteur.
- **Ne modifie aucun fichier du dépôt, ne pousse aucun commit.** Ce skill relit et propose des
  correctifs en extraits ; l'application passe par `pr-review-triage` ou par l'implémentation à la main.
- **Ne relance pas la CI**, pas de `--watch`.
- **Ne laisse le dépôt dans aucun autre état** qu'au départ : branche d'origine, arbre propre, worktrees
  retirés. `local-gate.sh` le garantit ; ne pas faire `gh pr checkout` ou `git worktree add` à la main.
- **Ne signale rien que tu n'as pas vu.** Pas de remarque déduite du titre ou d'un nom de fichier, ni d'un
  résultat de `grep` non confirmé par la lecture. Une remarque fausse coûte plus cher que pas de
  remarque : elle décrédibilise tout le reste.
- **Mode batch refusé** : une PR à la fois. « Relis toutes les PR ouvertes » → demander un numéro.
- **Le sous-agent du second avis n'écrit rien** : ni GitHub, ni fichier. Sa sortie ne quitte la
  conversation que repliée dans la fiche, après vérification.
- Toujours produire la **fiche avant** le commentaire, avec la frontière `---` + `## Commentaire à
  coller sur la PR`.

## Style

- Sortie dans la langue du dépôt, factuelle, concise. Pas de remplissage, pas de félicitations.
- Émojis limités à `🔴 🟠 🟡 🟢 ⚠️ 💬`, et `✍️` pour la section de style.
- Citer le code en `path:line`. Citer **la règle** sur laquelle repose le constat (`.claude/rules/… § N`,
  ou la source du dépôt qui la porte) : un constat sans règle ni conséquence est une opinion.
- Proposer le correctif, pas seulement le problème.
- Distinguer sans ambiguïté un **bloquant** d'une **préférence** : une préférence présentée en bloquant
  détruit la confiance dans la review suivante.

## Pourquoi ce périmètre

1. **La CI fait déjà la partie générique.** Lint, tests, build et code mort tournent à chaque PR sur les
   projets affectés. Les refaire en local coûte des dizaines de minutes pour zéro information. La valeur
   est ailleurs : multi-tenant, chargement de données, pièges d'ORM, verrous de stack, jumeaux — ce que
   la CI ne voit pas et que **les règles du dépôt** encodent.
2. **Les règles sont le capital du dépôt.** Elles consolident des bugs déjà payés en production. Une
   review qui ne les confronte pas au diff laisse repasser le même bug. Le rôle du skill est d'être
   cette confrontation, et de se taire sur tout ce que les règles n'énoncent pas.
3. **La décision reste humaine.** Le skill peut se tromper (intention mal lue, contexte hors diff, dette
   supposée). Poster une fiche argumentée fait avancer l'équipe ; approuver ou bloquer à sa place
   transfère une responsabilité qui n'est pas la sienne.

## Composition

| Skill | Rôle |
|---|---|
| `pr-review` | **produit** la review (ce skill) |
| `pr-review-triage` | **traite** une review déjà postée : vérifie chaque point, corrige, répond |
| `create-pr` | ouvre la PR, en amont de tout |
