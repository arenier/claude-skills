---
name: create
description: Rédige une documentation neuve dans l'un des quatre formats Diataxis (tutorial, how-to guide, reference, explanation). Détermine le format par une interview si l'utilisateur ne l'a pas donné explicitement, puis rassemble les sources avant d'écrire. À utiliser quand l'utilisateur demande explicitement d'écrire, de créer ou de rédiger une documentation, un tutoriel, un guide, une référence ou une explication — jamais en réaction à une simple modification de code qui touche incidemment un fichier de doc.
---

# Créer une documentation

Rédiger un document qui tient dans un seul des quatre quadrants Diataxis, alimenté par des sources
identifiées plutôt que reconstruit de mémoire. Lire d'abord [`../../diataxis.md`](../../diataxis.md) :
les critères de chaque format et la checklist de conformité de l'étape 3 y sont définis une fois pour
les trois skills du plugin.

## 1. Déterminer le format et les sources

Si l'utilisateur a nommé le format (« un how-to pour... », « une reference de... ») ou qu'il se
déduit sans ambiguïté de la demande, **et** que les sources sont déjà données ou évidentes, passer à
l'étape 2 sans interview.

Sinon, une interview `grilling` est nécessaire (pour le format, pour les sources, ou les deux) —
mais **demander d'abord à l'utilisateur s'il veut s'y prêter**, en une question simple, hors
formalisme design tree : « Pour cadrer ça, je peux t'interviewer par rounds de questions (`grilling`)
— tu préfères ça, ou que je te pose directement les deux ou trois questions qui manquent ? »

- **Oui** → appeler le skill `grilling`. La question racine du design tree est le choix du quadrant
  parmi les quatre définis dans `diataxis.md` ; en dépendent les questions de portée et d'angle, puis
  les sources : fichiers, code, specs, conversations, liens, texte à coller. Une des questions porte
  explicitement sur l'exploration du repo courant (code, tests, CLAUDE.md, docs existantes) comme
  source — **c'est à l'utilisateur de dire si elle est utile**, pas une exploration automatique ; si
  oui, dispatcher l'exploration en sous-agent plutôt que de bloquer dessus. La session est terminée
  quand le frontier est vide.
- **Non** → poser directement, en une fois et sans le formalisme `❓/➡️`, les questions minimales
  encore ouvertes sur le format et les sources. Ne pas deviner à la place de l'utilisateur : le
  format et les sources restent des décisions, pas des faits — seule la manière de les recueillir
  change.

## 2. Rédiger

Un seul quadrant, tenu de bout en bout — voir les critères par format dans `diataxis.md`. N'écrire
que ce qui est vrai dans l'état actuel des sources rassemblées ; aucune trace de ce qui a changé ou
n'est plus d'actualité. Hors `explanation`, ne pas justifier les choix : les motiver appartiendrait à
un document `explanation` séparé, pas à celui-ci.

## 3. Relecture de conformité

Avant de rendre la main, relire le document produit contre la checklist de `diataxis.md` (pureté du
format, vérité de l'état, sobriété, justification hors Explanation). Corriger ce qui y manque avant
de le présenter comme terminé — la relecture porte sur le résultat, pas sur l'intention de départ.
