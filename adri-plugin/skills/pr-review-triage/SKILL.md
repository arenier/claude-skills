---
name: pr-review-triage
description: Traite une review déjà postée sur une PR de pick-a-book — qu'elle vienne de pr-review, d'une routine cloud, ou d'un humain. Repasse la PR en draft, vérifie chaque point contre le code (repro jetable pour les affirmations de comportement), attribue un double verdict (le point est-il fondé ? qu'en fait-on ?), poste une réponse en commentaire avec un tableau récapitulatif, applique les correctifs retenus avec un test de non-régression, met à jour ce même commentaire, puis demande l'accord avant de repasser la PR en ready. À utiliser quand on dit « traite la review », « réponds aux retours », « corrige ce qui est valable », « la routine a relu ma PR », ou `/pr-review-triage <PR#>`. Ne merge jamais, n'approuve jamais, ne repasse jamais en ready sans accord explicite.
argument-hint: <PR#>
---

# Traiter une review de PR

Compagnon aval de `pr-review` : ce skill-là **produit** une review, celui-ci la **reçoit, la trie,
agit dessus, et y répond**.

La valeur de ce skill n'est pas d'appliquer les correctifs demandés — c'est de **séparer ce qui est
vrai de ce qui est seulement plausible**, puis de laisser une trace lisible de cet arbitrage. Une
review automatique se trompe : sur le fond, ou plus souvent sur le mécanisme. L'appliquer telle
quelle produit de mauvais correctifs ; l'ignorer laisse passer de vrais défauts. Les deux erreurs
coûtent cher, et la seconde se paie en production.

## Langue

Tout est en **français**, comme le reste de la doc du projet. Les livrables suivent la convention de
CLAUDE.md : **français dans la doc et les commentaires de PR, anglais dans le code et les commits**.

## Seuil d'application

Ce skill vise une review qui porte **au moins un point 🔴/🟠, ou plus de trois points**. En dessous
— deux remarques de style, une seule question — réponds directement dans la conversation : le passage
en draft, le commentaire versionné et le tableau coûtent plus qu'ils n'apportent.

Le même dosage vaut dans le process. Le repro par exécution est réservé aux affirmations de
**comportement** en 🔴/🟠 ; un 🟡 ou un 💬 se tranche en lisant. N'instrumente pas un point que trois
lignes de lecture règlent.

## Déroulé

| # | Étape | Qui |
|---|---|---|
| 1 | Rassembler les retours, l'état de la PR et du checkout | script `collect.sh` |
| 2 | Décider si le seuil est atteint | jugement |
| 3 | Repasser la PR en draft | commande `gh pr ready --undo` |
| 4 | Vérifier chaque point dans le code | jugement (repros, lecture) |
| 5 | Trier : verdict × traitement, escalader ce qui doit l'être | jugement |
| 6 | Écrire `triage.json`, rendre et poster la réponse | jugement, puis scripts `render.py` et `reply.sh` |
| 7 | Appliquer les correctifs retenus, avec leurs tests | jugement, puis script `commit.sh` |
| 8 | Mettre à jour le même commentaire | scripts `render.py` et `reply.sh` |
| 9 | Demander l'accord pour repasser en ready | jugement |

## Garde-fous

- **Ne merge jamais, n'approuve jamais, ne ferme jamais** la PR.
- **Ne repasse jamais la PR en ready sans accord explicite** — c'est le seul geste qui la rouvre aux
  relecteurs.
- **Commits par `commit.sh` uniquement**, avec les chemins explicites : l'arbre de travail contient
  souvent des fichiers étrangers à la PR (captures, config locale, artefacts de dev-server). Les
  lister quand ils sont laissés de côté.
- **Push sous le bon compte.** `collect.sh` affiche le compte `gh` actif et son droit de push ; s'il
  ne peut pas pousser : `gh auth switch --user arenier`. L'identité git de commit reste celle
  configurée dans le repo.
- **Réécriture d'historique** : sur demande explicite seulement, par `reword.sh`, jamais par
  `git reset --hard` ni un rebase interactif.
- **Zéro secret** dans les commentaires, commits et fiches. Un numéro d'issue GitHub est admis.
- Ne résous pas silencieusement le fil de review de quelqu'un d'autre : réponds, laisse l'auteur le
  fermer.

## 1. Rassembler

```bash
${CLAUDE_SKILL_DIR}/collect.sh [PR#]
```

Sans numéro : la PR de la branche courante. Le script affiche `sources.md` (et `WORKDIR=…`) :

- l'état de la PR, le compte `gh` et son droit de push, si le checkout local **est** la branche de la
  PR (sinon `gh pr checkout <PR#>` avant toute correction), le nombre de fichiers modifiés localement ;
- la sortie de `gh pr checks` ;
- l'éventuel commentaire de triage déjà posté ;
- les retours aux quatre endroits où une review peut vivre — commentaires de conversation, reviews
  formelles, commentaires inline — chacun avec son origine (routine cloud, `pr-review`, humain) et le
  **nombre de commits poussés depuis**. Un point relu sur un commit antérieur peut être périmé : le
  dire plutôt que de « corriger » du code qui a changé.

## 2. Décider du seuil

Compter les points et leur sévérité (voir « Seuil d'application »). En dessous, répondre dans la
conversation et s'arrêter là.

## 3. Repasser en draft

```bash
gh pr ready --undo <PR#>
```

**Tôt**, et le dire à l'utilisateur. Pendant le triage la PR est dans un état intermédiaire, points
reconnus mais pas encore corrigés : le draft empêche un merge ou une approbation d'atterrir à
mi-chemin, et signale que la balle est dans le camp de l'auteur. Déjà en draft : ne rien faire.

## 4. Vérifier chaque point

C'est l'étape qui porte la valeur. **Aucun point n'est retenu ni écarté sans vérification.** Les
prendre un par un, du plus grave au moins grave.

Lire d'abord le code cité. Les numéros de ligne d'une review peuvent pointer un commit antérieur
(`sources.md` le signale) : **trouve le code par son contenu**, pas par sa ligne.

Une affirmation de **comportement** se vérifie par un repro jetable qui imprime la preuve observable :
ne retiens pas ce que tu n'as pas vu se produire, n'écarte pas ce que tu n'as pas tenté de
reproduire. Une **question** (💬) se répond ou s'escalade — ce n'est pas un défaut à corriger par
réflexe.

**Commence par la CI, c'est le recours le moins cher.** Toute affirmation _sur la CI_ (« la règle X va
casser le build », « ce test ne passe plus ») se tranche par le `gh pr checks` déjà dans
`sources.md`. Une CI verte tue immédiatement un « la CI va échouer ».

Mais **une CI verte ne prouve rien sur le comportement** : elle prouve seulement que rien de ce
qu'elle vérifie n'est cassé. Elle est structurellement muette quand la règle invoquée n'est pas
activée, quand le chemin est exclu du lint, quand le job est _skipped_, ou quand rien n'exerce le
régime en question. Dans ces cas — et seulement ceux-là — **déclenche vraiment la cause invoquée** :
active la règle et relance le lint du repo, écris le fichier pour voir le système le refuser, appelle
le vrai appelant.

```bash
yarn nx test <projet>          # une spec / un projet ciblé (Vitest · ADR 0007)
yarn nx lint <projet>          # le lint d'un projet (dont @nx/enforce-module-boundaries)
yarn nx typecheck <projet>     # tsc
```

Annonce l'**ordre de grandeur du coût avant** de lancer, jamais après. Préfère le projet ciblé à un
`nx run-many` sur tout le graphe. Un repro se pose de préférence en spec Vitest dans le scratchpad, ou
un petit script `node`.

Trois pièges qui reviennent :

- **Le mécanisme, pas seulement la conclusion.** Une review peut avoir raison sur la règle et tort sur
  ses effets. Corriger sur un mécanisme faux mène au mauvais correctif.
- **Le régime de test.** Un point non reproductible dans le cas nominal peut être bien réel à une
  autre échelle ou avec une autre structure de données. Demande **quel régime** l'affirmation exige,
  et teste _ce_ régime.
- **Le vrai seuil.** Quand un point est fondé, mesure son ampleur au lieu de reprendre l'estimation
  de la review : elle est souvent approximative.

**Un `grep` de vérification est aussi faillible que le code qu'il contrôle** : écrit trop strict, il
crie au défaut sur du code sain. Le confirmer par exécution avant de le rapporter — un faux échec
ruine la confiance dans tout le triage.

Enfin, cherche **ce que la review n'a pas vu**. Une review regarde le diff ; elle regarde rarement si
la **description de la PR** dit encore la vérité. Si un correctif invalide une affirmation de la
description, c'est un point à part entière.

## 5. Trier : deux axes, pas un

Chaque point reçoit **un verdict** (est-il fondé ?) et **un traitement** (qu'en fait-on ?). Les
confondre perd de l'information : un point peut être parfaitement fondé et volontairement reporté.

**Verdicts** — libres mais explicites : `Fondé` · `Fondé, sous-estimé` · `Fondé, mécanisme faux` ·
`Fondé, hors scope` · `Constat` · `Infondé`.

**Traitements** (`status` dans `triage.json`) :

| `status` | Affiché | Sens | `note` |
|---|---|---|---|
| `in_progress` | ⏳ En cours | retenu, correctif pas encore poussé | — |
| `fixed` | ✅ Corrigé | traité dans cette PR | le sha du commit |
| `deferred` | 📌 Reporté | fondé, mais hors scope de cette PR | où la dette est notée (description, issue) |
| `rejected` | ⛔ Écarté | non retenu | la raison, en une ligne |
| `decide` | 🙋 À trancher | exige une décision humaine | la question posée |

**Escalade à l'humain** (via `AskUserQuestion`, recommandation en tête, une ligne de compromis par
option) quand le correctif : change un comportement produit ou un arbitrage déjà acté (un ADR !) ;
exige de réécrire de l'historique déjà poussé ; élargit le scope de la PR ; oppose deux options
défendables de coûts différents ; touche une décision déjà prise plus tôt. **Un correctif qui
contredirait un ADR accepté s'escalade toujours** : un ADR ne se réécrit pas par un correctif de
review, il faut un nouvel ADR. N'escalade pas ce qui a une réponse par défaut évidente : décide,
dis-le, avance.

## 6. Poster la réponse

**Avant** d'appliquer les correctifs : le triage devient visible, et l'utilisateur peut objecter
avant qu'une ligne ne soit écrite — pas après.

Écrire `WORKDIR/triage.json` :

```json
{
  "summary": "1-2 lignes : ce qui a été vérifié, et le résultat d'ensemble",
  "points": [
    {"severity": "blocker|major|minor|question", "title": "le point, court",
     "verdict": "Fondé, mécanisme faux", "status": "in_progress", "note": "",
     "outcome": "reproduit | infirmé | constaté | …",
     "proof": "markdown : sortie du repro, extrait de config, citation de code — ce qui est observé, pas supposé"}
  ],
  "unnoticed": ["point non relevé par la review, s'il y en a"]
}
```

Puis :

```bash
python3 ${CLAUDE_SKILL_DIR}/render.py <WORKDIR>    # valide, écrit reply.md, l'affiche
${CLAUDE_SKILL_DIR}/reply.sh <PR#> [WORKDIR]        # crée ou met à jour le commentaire
```

`render.py` refuse un `triage.json` incomplet (un `fixed` sans sha, un `rejected` sans raison…) et
se charge de la forme : tableau récapitulatif visible, un `<details>` par point ouvert seulement en
🔴/🟠, la liste « ce qui reste ouvert » tirée des 📌, ⛔ et 🙋. Il rappelle les points `decide` à faire
trancher avant d'appliquer quoi que ce soit.

## 7. Appliquer les correctifs retenus

Par ordre de gravité. Selon la taille du changement :

- **Correctif contenu** (un guard, un ordre d'opérations, une validation d'entrée) : le faire
  directement.
- **Changement de taille feature** : le décrire et proposer de le sortir en travail à part ; ne pas
  gonfler la PR sous couvert de triage.

Deux exigences sur les tests, parce que c'est là que naissent les défauts trouvés par une review — et
que la convention du repo (CLAUDE.md) l'impose :

1. **Chaque point de comportement retenu reçoit un test de non-régression** — et le repro de l'étape 4
   en est le brouillon naturel : il échoue avant le correctif, passe après. `domain` et `application`
   se testent sans infra ; un adapter se teste contre la vraie techno (jamais contre un mock de
   lui-même · ADR 0005/0006).
2. **Le test doit exercer le régime où l'invariant casse**, pas seulement celui où il tient. Demande
   explicitement : _quel axe ce test ne couvre-t-il pas ?_

**Épingle aussi les points écartés — mais pas tous.** Un ⛔ dont l'affirmation était
**comportementale** mérite un test qui passe **avant et après** : cette signature vert/vert prouve
que le point n'a jamais été un bug et empêche un futur contributeur de « corriger » le même
non-défaut. Passe-le quand le point est stylistique. Un test par point écarté, pas plus.

Puis les conventions du repo :

- **Jumeaux (fix-twins)** : pour tout correctif sur un adapter, un chemin frère (single ↔ bulk), un
  value object ou une slice web dupliquée, demande « où est le jumeau ? » — `grep` la signature du
  défaut dans tout le repo, corrige les jumeaux ou liste-les comme dette explicite.
- **Frontières Nx** : ne « corrige » jamais un import interdit en le déplaçant hors des tags — c'est
  l'ADR 0002 qu'il faut respecter, pas le garde-fou qu'il faut contourner.
- **Description de la PR** : si le code la contredit désormais, la réécrire selon `create-pr` et la
  pousser par `gh pr edit <PR#> --body-file <fichier>`.

Commiter et pousser :

```bash
${CLAUDE_SKILL_DIR}/../../scripts/commit.sh -m "fix(<scope>): <sujet impératif en anglais>" -- <chemins précis>
git push
```

`commit.sh` refuse un sujet hors Conventional Commits, `main`, et `.` en guise de chemins ; il ajoute
le trailer `Co-Authored-By`.

## 8. Mettre à jour le MÊME commentaire

Faire avancer les statuts dans `triage.json` (`in_progress` → `fixed` + sha), ajouter les points non
relevés découverts en route, **garder la preuve avant/après** (le « avant » est la justification du
correctif), puis relancer `render.py` et `reply.sh` : le script retrouve le commentaire par son
marqueur et le met à jour au lieu d'en créer un nouveau. Un relecteur qui revient lit un seul
endroit.

## 9. Demander l'accord pour repasser en ready

Présenter d'abord l'état réel : CI, ce qui a été corrigé, ce qui reste ouvert. Puis demander. Sur
accord :

```bash
gh pr ready <PR#>
```

Sans accord, la PR reste en draft — état parfaitement valide pour finir un tour.

## Réécrire un message de commit

Sur demande explicite seulement. `git rebase -i` est indisponible dans cet environnement, et
`git reset --hard` **détruirait les changements locaux non commités**. Écrire le nouveau message dans
un fichier, puis :

```bash
${CLAUDE_SKILL_DIR}/reword.sh <commit> <fichier-message>
```

Le script reconstruit le commit et tous ceux qui le suivent par la plomberie Git (arbres, auteurs et
dates identiques), déplace la branche seulement si elle n'a pas bougé entre-temps, puis vérifie que le
contenu est identique et que l'arbre de travail n'a pas changé. Il ne pousse pas : il affiche la
commande `git push --force-with-lease=…`, à lancer seulement sur accord.

## Composition

| Skill | Rôle |
|---|---|
| `pr-review` | **produit** la review — l'amont de ce skill |
| `create-pr` | ouvre la PR, et donne la forme de sa description si le triage l'a invalidée |

Ne pas utiliser ce skill pour **produire** une review (c'est `pr-review`).
