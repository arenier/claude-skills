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

## 1. Relever l'état réel

En parallèle, avant toute rédaction :

```bash
git status
git branch --show-current
git log main..HEAD --oneline          # commits déjà faits sur la branche
git diff main...HEAD --stat           # périmètre du travail commité
git diff --stat                       # ce qui traîne, non commité
gh issue list --limit 20
```

Puis lire le diff, pas seulement le `--stat`. Ne rédiger aucune section sur la base de la
conversation seule : ce qui compte est ce que le diff contient, pas ce qu'on a eu l'intention de
faire.

## 2. Amener le travail sur une branche

`main` est protégée : push direct refusé. Donc :

- **Sur `main`** → créer la branche avant tout : `git checkout -b <type>/<résumé-kebab-case>`
  (`feat/`, `fix/`, `docs/`, `refactor/`, `chore/`).
- **Modifications non commitées** → les lire, puis commiter. Découper en plusieurs commits si le
  travail contient des parties distinctes ; un seul commit sinon. Message en anglais, avec le
  trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Jamais de `git add -A` à l'aveugle.** Ajouter les fichiers du travail en cours, et rien d'autre.
  Un fichier hors sujet dans le diff se signale à l'utilisateur au lieu d'être embarqué.
- Pousser : `git push -u origin HEAD`.

Avant d'ouvrir : lancer lint et tests s'ils existent (`yarn nx affected -t lint test` une fois le
repo scaffoldé). Tant que le repo n'a pas de `package.json`, il n'y a rien à lancer — le dire dans
la section Tests plutôt que de laisser croire à une vérification.

## 3. Rédiger

### Titre

Anglais, préfixe conventionnel, impératif, minuscule, ~70 caractères max :
`feat: extract author/title pairs from shelf photo`.

Le merge est un squash : **ce titre devient le message de commit dans l'historique de `main`**. Il
doit se tenir seul, sans le contexte de la PR.

### Corps

Français. Ouvrir par une ou deux phrases : ce que la PR change, et pourquoi maintenant. Puis les
sections utiles, dans cet ordre. **Une section sans contenu réel se supprime** — pas de « N/A », pas
de remplissage.

```markdown
<Une ou deux phrases : ce que la PR change, et pourquoi maintenant.>

## Contexte

## Modifications

## Tests

## ADR concernés

## Points d'attention

## Hors scope

Closes #N
```

**Contexte** — ce qui existait avant, et le problème que ça posait. À omettre quand le titre suffit.
Pas une reformulation du besoin en trois paragraphes.

**Modifications** — regrouper par intention, pas par fichier. Au-delà de trois fichiers, un tableau
`fichier ou lib → ce que ça fait` passe mieux qu'une liste. Dire ce que le code établit, pas quelles
lignes ont bougé.

**Tests** — ce qui est couvert, et le résultat **réellement observé** : coller le résumé de la
sortie. Jamais « les tests passent » sans les avoir lancés. S'il n'y a pas de test, dire pourquoi
(documentation seule, adapter testé manuellement contre la vraie techno, …) et donner les étapes de
vérification à la main.

**ADR concernés** — les ADR que le code applique, en lien relatif (`docs/adr/0002-….md`). Deux cas
qui exigent un arrêt avant d'ouvrir la PR, à signaler à l'utilisateur :

- la PR prend une **décision structurante sans ADR** → proposer d'écrire l'ADR dans la même PR ;
  c'est la règle du repo (« avant ou avec le code »).
- la PR **contredit un ADR accepté** → un ADR accepté ne se réécrit pas ; il faut un nouvel ADR qui
  remplace l'ancien.

**Points d'attention** — ce qu'il faut relire en premier, les limites connues, ce qui est fragile ou
reconstitué. C'est la section la plus utile ; ne pas la remplir de généralités pour la remplir.

**Hors scope** — ce qui a été laissé de côté volontairement, et ce qui reste non tranché.

**Closes #N** — seulement si une issue correspond vraiment, vérifiée dans `gh issue list`. Aucun
numéro inventé, aucun numéro deviné.

Terminer le corps par :

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## 4. Créer

Écrire le corps dans un fichier du scratchpad, puis :

```bash
gh pr create --title "<titre>" --body-file <chemin>
```

Le corps contient du markdown multiligne : passer par `--body-file`, jamais par `--body` inline.

## 5. Rendre compte

Donner l'URL de la PR, et énumérer ce qui a été **écarté ou non vérifié** : test non lancé, fichier
laissé de côté, section supprimée faute de matière. Ce qui a échoué se dit, avec la sortie.

Ne pas merger. Rappeler que la suite appartient à l'auteur :
`gh pr merge --squash --delete-branch`.
