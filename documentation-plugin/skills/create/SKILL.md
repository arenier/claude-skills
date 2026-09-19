---
name: create
description: Rédige une documentation neuve dans l'un des quatre formats Diataxis (tutorial, how-to guide, reference, explanation). Détermine le format par une interview si l'utilisateur ne l'a pas donné explicitement, puis rassemble les sources avant d'écrire. À utiliser quand l'utilisateur demande explicitement d'écrire, de créer ou de rédiger une documentation, un tutoriel, un guide, une référence ou une explication — jamais en réaction à une simple modification de code qui touche incidemment un fichier de doc.
---

# Créer une documentation

Rédiger un document qui tient dans un seul des quatre quadrants Diataxis, alimenté par des sources
identifiées plutôt que reconstruit de mémoire. Lire d'abord [`../../diataxis.md`](../../diataxis.md) :
les critères de chaque format et la checklist de conformité de l'étape 4 y sont définis une fois pour
les trois skills du plugin.

## 1. Déterminer le format

Si l'utilisateur a nommé le format (« un how-to pour... », « une reference de... ») ou qu'il se
déduit sans ambiguïté de la demande, passer à l'étape 2.

Sinon, appeler le skill `grilling` pour lever l'ambiguïté. La question racine du design tree est le
choix du quadrant parmi les quatre définis dans `diataxis.md` ; les questions qui en dépendent
(portée exacte, angle) suivent dans les rounds suivants. Ne pas deviner le format à la place de
l'utilisateur : c'est une décision, pas un fait.

## 2. Rassembler les sources

Continuer (ou ouvrir, si l'étape 1 n'a pas grillé) une session `grilling` pour identifier ce qui
alimentera le contenu : fichiers, code, specs, conversations, liens, texte à coller. C'est le
frontier de cette étape.

Une des questions de ce round porte explicitement sur l'exploration du repo courant (code, tests,
CLAUDE.md, docs existantes) comme source : **c'est à l'utilisateur de dire si elle est utile**, pas
une exploration automatique. Si l'utilisateur y répond oui, dispatcher l'exploration en sous-agent
plutôt que de bloquer dessus, et ne mettre en attente que les questions qui en dépendent réellement.

La session est terminée quand le frontier est vide : chaque source pertinente a été identifiée ou
écartée explicitement.

## 3. Rédiger

Un seul quadrant, tenu de bout en bout — voir les critères par format dans `diataxis.md`. N'écrire
que ce qui est vrai dans l'état actuel des sources rassemblées ; aucune trace de ce qui a changé ou
n'est plus d'actualité. Hors `explanation`, ne pas justifier les choix : les motiver appartiendrait à
un document `explanation` séparé, pas à celui-ci.

## 4. Relecture de conformité

Avant de rendre la main, relire le document produit contre la checklist de `diataxis.md` (pureté du
format, vérité de l'état, sobriété, justification hors Explanation). Corriger ce qui y manque avant
de le présenter comme terminé — la relecture porte sur le résultat, pas sur l'intention de départ.
