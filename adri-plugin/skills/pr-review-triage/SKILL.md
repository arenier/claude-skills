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

Le corps du skill est en anglais dans les autres repos ; ici tout est en **français**, comme le
reste de la doc du projet. Les livrables — le commentaire de réponse, le message de commit — suivent
la convention de CLAUDE.md : **français dans la doc, anglais dans le code et les commits**.

## Seuil d'application

Ce skill vise une review qui porte **au moins un point 🔴/🟠, ou plus de trois points**. En dessous
— deux remarques de style, une seule question — réponds directement dans la conversation : le passage
en draft, le commentaire versionné et le tableau coûtent plus qu'ils n'apportent.

Le même dosage vaut dans le process. Le repro par exécution est réservé aux affirmations de
**comportement** en 🔴/🟠 ; un 🟡 ou un 💬 se tranche en lisant. N'instrumente pas un point que trois
lignes de lecture règlent.

## Garde-fous

- **Ne merge jamais, n'approuve jamais, ne ferme jamais** la PR.
- **Ne repasse jamais la PR en ready sans accord explicite** — c'est le seul geste qui la rouvre aux
  relecteurs.
- **Stage les fichiers explicitement** (`git add <chemins>`), jamais `git add -A` : l'arbre de
  travail contient souvent des fichiers étrangers à la PR (captures, config locale, artefacts de
  dev-server). Les lister quand ils sont laissés de côté.
- **Push sous le bon compte.** Le remote est `arenier/pick-a-book` (perso). Vérifier que le compte
  `gh` actif peut y pousser (`gh auth status`) ; au besoin `gh auth switch --user arenier`.
  L'identité git de commit reste celle configurée dans le repo.
- **Réécriture d'historique** (`--amend`, force-push) : sur demande explicite seulement, avec
  `--force-with-lease`. Si l'arbre est sale, **ne pas passer par `git reset --hard`** ni un rebase
  interactif — voir « Réécrire un message de commit » plus bas.
- **Zéro secret** dans les commentaires, commits et fiches. Un numéro d'issue GitHub est admis.
- Ne résous pas silencieusement le fil de review de quelqu'un d'autre : réponds, laisse l'auteur le
  fermer.

## Process

### 1. Préflight et collecte des points

En parallèle : `gh auth status`, puis la PR et ses retours. Une review peut vivre à quatre endroits
— les rater fait répondre à côté :

```bash
gh pr view <PR#> --json number,state,isDraft,reviewDecision,statusCheckRollup,commits,headRefName
gh pr view <PR#> --json comments --jq '.comments[] | "===== " + .author.login + " =====\n" + .body'   # commentaires (pr-review, routine cloud)
gh pr view <PR#> --json reviews  --jq '.reviews[]  | {author: .author.login, state, body}'            # reviews formelles
gh api /repos/{owner}/{repo}/pulls/<PR#>/comments --jq '.[] | {path, line, body}'                     # commentaires inline
```

Une review de la routine cloud signe son commentaire par un marqueur `<!-- pr-review-auto: <sha> -->`
(ou `<!-- pr-review -->` pour le skill local). Quand un tel marqueur est présent, **compare son sha
au HEAD de la branche** : si la branche a bougé depuis, certains points peuvent déjà être périmés —
le dire plutôt que de « corriger » du code qui a changé.

Note l'**id du commentaire** à mettre à jour plus tard
(`gh pr view --json comments --jq '.comments[] | {id, url}'`).

Sans numéro de PR : cibler la PR de la branche courante (`gh pr view --json number …`).

### 2. Repasser la PR en draft

```bash
gh pr ready --undo <PR#>
```

**Tôt**, et le dire à l'utilisateur. Ce n'est pas cosmétique : pendant le triage la PR est dans un
état intermédiaire, points reconnus mais pas encore corrigés. Le draft empêche un merge/approbation
d'atterrir à mi-chemin et signale que la balle est dans le camp de l'auteur. Si la PR est déjà en
draft, ne rien faire.

### 3. Vérifier chaque point dans le code

C'est l'étape qui porte la valeur. **Aucun point n'est retenu ni écarté sans vérification.** Prendre
les points un par un, du plus grave au moins grave.

Lire d'abord le code cité. Les numéros de ligne d'une review peuvent pointer un commit antérieur :
**trouve le code par son contenu**, pas par sa ligne.

Une affirmation de **comportement** se vérifie par un repro jetable qui imprime la preuve
observable : ne retiens pas ce que tu n'as pas vu se produire, n'écarte pas ce que tu n'as pas tenté
de reproduire. Une **question** (💬) se répond ou s'escalade — ce n'est pas un défaut à corriger par
réflexe.

**Commence par la CI, c'est le recours le moins cher.** Toute affirmation _sur la CI_ (« la règle X
va casser le build », « ce test ne passe plus ») se tranche par le run qui existe déjà :
`gh pr checks <PR#>`. Une CI verte tue immédiatement un « la CI va échouer ».

Mais **une CI verte ne prouve rien sur le comportement** : elle prouve seulement que rien de ce
qu'elle vérifie n'est cassé. Elle est structurellement muette quand la règle invoquée n'est pas
activée, quand le chemin est exclu du lint, quand le job est _skipped_, ou quand rien n'exerce le
régime en question. Dans ces cas — et seulement ceux-là — **déclenche vraiment la cause invoquée** :
active la règle et relance le lint du repo, écris le fichier pour voir le système le refuser, appelle
le vrai appelant. Les commandes du repo :

```bash
yarn nx test <projet>          # une spec / un projet ciblé (Vitest · ADR 0007)
yarn nx lint <projet>          # le lint d'un projet (dont @nx/enforce-module-boundaries)
yarn nx typecheck <projet>     # tsc
```

Annonce l'**ordre de grandeur du coût avant** de lancer, jamais après. Un `nx run-many` sur tout le
graphe est long : préfère le projet ciblé (`nx test <projet>`). Un repro se pose de préférence en
spec Vitest dans le scratchpad, ou un petit script `node`.

Trois pièges qui reviennent :

- **Le mécanisme, pas seulement la conclusion.** Une review peut avoir raison sur la règle et tort
  sur ses effets. Corriger sur un mécanisme faux mène au mauvais correctif.
- **Le régime de test.** Un point non reproductible dans le cas nominal peut être bien réel à une
  autre échelle ou avec une autre structure de données. Demande **quel régime** l'affirmation exige,
  et teste _ce_ régime.
- **Le vrai seuil.** Quand un point est fondé, mesure son ampleur au lieu de reprendre l'estimation
  de la review : elle est souvent approximative.

**Un `grep` de vérification est aussi faillible que le code qu'il contrôle** : écrit trop strict, il
crie au défaut sur du code sain (une regex extraite en constante, un appel renommé). Le confirmer par
exécution avant de le rapporter — le coût de l'erreur est asymétrique : un faux échec ruine la
confiance dans tout le triage.

Enfin, cherche **ce que la review n'a pas vu**. Une review regarde le diff ; elle regarde rarement
si la **description de la PR** dit encore la vérité. Si un correctif invalide une affirmation de la
description, c'est un point à part entière.

### 4. Triage : deux axes, pas un

Chaque point reçoit **un verdict** (est-il fondé ?) et **un traitement** (qu'en fait-on ?). Les
confondre perd de l'information : un point peut être parfaitement fondé et volontairement reporté.

**Verdicts** — libres mais explicites : `Fondé` · `Fondé, sous-estimé` · `Fondé, mécanisme faux` ·
`Fondé, hors scope` · `Constat` · `Infondé`.

**Traitements** :

| Statut | Sens | Accompagné de |
|---|---|---|
| ✅ **Corrigé** | Traité dans cette PR | le sha du commit |
| 📌 **Reporté** | Fondé, mais hors scope de cette PR | où la dette est notée (description, issue) |
| ⛔ **Écarté** | Non retenu | la raison, en une ligne |
| 🙋 **À trancher** | Exige une décision humaine | la question posée |

**Escalade à l'humain** (via `AskUserQuestion`, recommandation en tête, une ligne de compromis par
option) quand le correctif : change un comportement produit ou un arbitrage déjà acté (un ADR !) ;
exige de réécrire de l'historique déjà poussé ; élargit le scope de la PR ; oppose deux options
défendables de coûts différents ; touche une décision déjà prise plus tôt. **Un correctif qui
contredirait un ADR accepté s'escalade toujours** : un ADR ne se réécrit pas par un correctif de
review, il faut un nouvel ADR. N'escalade pas ce qui a une réponse par défaut évidente : décide,
dis-le, avance.

### 5. Poster la réponse

**Avant** d'appliquer les correctifs. Le triage devient visible, et l'utilisateur peut objecter
avant qu'une ligne ne soit écrite — pas après.

Structure du commentaire — le tableau récapitulatif reste **visible** (verdicts d'un coup d'œil) ; le
détail point par point est **replié** dans `<details>`. Marqueur `<!-- pr-review-triage -->` en tête
pour la rejouabilité :

```markdown
<!-- pr-review-triage -->
[1-2 lignes : ce qui a été vérifié, et le résultat d'ensemble]

| Point | Verdict | Traitement |
|---|---|---|
| 🟠 <point, court> | Fondé | ⏳ En cours |
| 🟡 <point, court> | Fondé | 📌 Reporté |
| 💬 <question> | Constat | ⛔ Écarté (raison) |

<details open>
<summary><b>Vérifications point par point (N)</b></summary>

### 1. <Point> — <reproduit | infirmé>

[La preuve : sortie du repro, extrait de config, citation de code. Ce qui est observé, pas supposé.]

</details>

<details>
<summary><b>Point non relevé · Ce qui reste ouvert</b></summary>

**Point non relevé par la review** — [s'il y en a un].

**Ce qui reste ouvert** — les 📌 et les ⛔, nommés, pour qu'un lecteur sache ce qui n'a pas été traité.

</details>
```

Deux règles pour que les `<details>` rendent sur GitHub :

- **Une ligne vide après `</summary>` est obligatoire** — sans elle, le markdown intérieur (tableau,
  titres, liste) n'est pas rendu.
- Garder l'attribut **`open`** sur « Vérifications point par point » **seulement quand il porte un 🔴
  ou 🟠**. Le retirer (`<details>`) quand tout est 🟡/💬. Omettre un `<details>` dont le contenu
  serait vide.

Poster via un fichier du scratchpad, et **garder l'id du commentaire** :

```bash
gh pr comment <PR#> --body-file <scratchpad>/review-reply.md
```

### 6. Appliquer les correctifs retenus

Par ordre de gravité. Selon la taille du changement :

- **Correctif contenu** (un guard, un ordre d'opérations, une validation d'entrée) : le faire
  directement.
- **Changement de taille feature** : le décrire et proposer de le sortir en travail à part ; ne pas
  gonfler la PR sous couvert de triage.

Deux exigences sur les tests, parce que c'est là que naissent les défauts trouvés par une review —
et que la convention du repo (CLAUDE.md) l'impose :

1. **Chaque point de comportement retenu reçoit un test de non-régression** — et le repro de
   l'étape 3 en est le brouillon naturel : il échoue avant le correctif, passe après. `domain` et
   `application` se testent sans infra ; un adapter se teste contre la vraie techno (jamais contre un
   mock de lui-même · ADR 0005/0006).
2. **Le test doit exercer le régime où l'invariant casse**, pas seulement celui où il tient. Demande
   explicitement : _quel axe ce test ne couvre-t-il pas ?_

**Épingle aussi les points écartés — mais pas tous.** Un ⛔ dont l'affirmation était **comportementale**
mérite un test qui passe **avant et après** : cette signature vert/vert prouve que le point n'a jamais
été un bug et empêche un futur contributeur de « corriger » le même non-défaut. Passe-le quand le
point est stylistique. Un test par point écarté, pas plus.

Puis applique les conventions du repo :

- **Jumeaux (fix-twins)** : pour tout correctif sur un adapter, un chemin frère (single ↔ bulk), un
  value object ou une slice web dupliquée, demande « où est le jumeau ? » — `grep` la signature du
  défaut dans tout le repo, corrige les jumeaux ou liste-les comme dette explicite.
- **Frontières Nx** : ne « corrige » jamais un import interdit en le déplaçant hors des tags — c'est
  l'ADR 0002 qu'il faut respecter, pas le garde-fou qu'il faut contourner.
- **Mettre à jour la description de la PR** si le code la contredit désormais : déléguer la réécriture
  à `create-pr` (`gh pr edit <PR#> --body-file <fichier>`).

Avant de commiter, valider la forme du message. Le repo **n'a pas** de commitlint : se limiter à la
forme Conventional Commits (`type(scope): sujet`, impératif, minuscule, anglais). Message en anglais
avec le trailer `Co-Authored-By: Claude <noreply@anthropic.com>` (convention de `create-pr`).

```bash
git add <chemins précis>          # jamais -A
git commit -m "fix(recognition): <sujet impératif en anglais>" -m "" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
git push
```

### 7. Mettre à jour le MÊME commentaire

**Le même**, pas un nouveau :

```bash
gh api -X PATCH /repos/{owner}/{repo}/issues/comments/<id> -F body=@<scratchpad>/review-reply.md
```

Un relecteur qui revient lit un seul endroit, et le tableau reste l'index de l'échange. Faire avancer
les statuts (`⏳ En cours` → `✅ Corrigé <sha>`) et **garder la preuve avant/après** : le « avant »
est la justification du correctif. Si le tableau a gagné des lignes (points non relevés par la
review), les y ajouter aussi.

### 8. Demander l'accord pour repasser en ready

Présenter d'abord l'état réel : CI, ce qui a été corrigé, ce qui reste ouvert. Puis demander. Sur
accord :

```bash
gh pr ready <PR#>
```

Sans accord, la PR reste en draft — état parfaitement valide pour finir un tour.

## Réécrire un message de commit sans casser l'arbre de travail

Sur demande explicite seulement. Un `git rebase -i` est indisponible dans cet environnement, et un
`git reset --hard` **détruirait les changements locaux non commités**. La plomberie Git reconstruit
les commits sans jamais toucher l'arbre de travail :

```bash
BASE=$(git rev-parse "$C1^")
git log -1 --format=%B "$C1" > msg1.txt   # puis édite msg1.txt

rebuild() {  # $1 = commit source, $2 = parent, $3 = fichier message
  GIT_AUTHOR_NAME=$(git log -1 --format=%an "$1") \
  GIT_AUTHOR_EMAIL=$(git log -1 --format=%ae "$1") \
  GIT_AUTHOR_DATE=$(git log -1 --format=%aI "$1") \
  GIT_COMMITTER_DATE=$(git log -1 --format=%cI "$1") \
  git commit-tree "$(git rev-parse "$1^{tree}")" -p "$2" -F "$3"
}

N1=$(rebuild "$C1" "$BASE" msg1.txt)
git update-ref refs/heads/<branche> "$N1" "$C1"   # le 3e arg refuse si la ref a bougé
git push --force-with-lease
```

Puis vérifier que **le contenu est identique** (`git diff <ancien-HEAD> HEAD` vide) et que l'arbre de
travail n'a pas bougé (`git status --short`).

## Composition

| Skill | Rôle |
|---|---|
| `pr-review` | **produit** la review — l'amont de ce skill |
| `create-pr` | ouvre la PR et réécrit sa description si le triage l'a invalidée |

Ne pas utiliser ce skill pour **produire** une review (c'est `pr-review`).
