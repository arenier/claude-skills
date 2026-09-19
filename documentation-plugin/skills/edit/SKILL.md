---
name: edit
description: Ajoute ou modifie un ou plusieurs éléments d'une documentation existante, sans en changer le format Diataxis ni y introduire de justification. À utiliser quand l'utilisateur demande explicitement d'ajouter, corriger, mettre à jour ou modifier un point précis d'une documentation déjà en place — pas pour une réorganisation d'ensemble (`restructure`) ni une création (`create`).
---

# Modifier une documentation

Faire porter le changement demandé sur le document tel qu'il est, sans dériver son format ni y
glisser de justification qu'il n'admet pas. Lire d'abord [`../../diataxis.md`](../../diataxis.md)
pour les critères de chaque format et la checklist de conformité de l'étape 4.

## 1. Identifier le format du document visé

Avant de toucher au contenu, déterminer dans lequel des quatre quadrants Diataxis le document se
range déjà (voir les critères dans `diataxis.md`). C'est ce format qui fixe la règle de justification
de l'étape 2 — un document `explanation` l'admet, les trois autres non. Un document qui ne tient déjà
dans aucun quadrant proprement n'est pas du ressort de ce skill : c'est le cas pour `restructure`, à
signaler à l'utilisateur plutôt que de modifier un format bancal.

## 2. Modifier

Appliquer le changement demandé :

- **N'écrire que ce qui est vrai dans l'état actuel.** Rien de ce qui n'est plus vrai ne reste dans
  le texte, même reformulé ou atténué — pas de changelog, pas de « auparavant / désormais » dans le
  corps.
- **Réécrire le bloc concerné plutôt que d'y ajouter des lignes.** Une modification qui se contente
  d'ajouter en périphérie laisse une structure qui ne reflète plus l'intention d'ensemble du bloc ;
  la réécrire entièrement le fait.
- **Hors format `explanation` : aucune justification.** Si le changement ne peut s'exprimer sans un
  « parce que », un rationale ou une mise en contexte du choix, c'est que la modification déborde du
  quadrant du document — s'arrêter et le signaler à l'utilisateur plutôt que d'introduire la
  justification dans un `tutorial`, un `how-to guide` ou une `reference`. En `explanation`, cette
  règle ne s'applique pas.

## 3. Relecture de conformité

Avant de rendre la main, relire le changement contre la checklist de `diataxis.md` (pureté du
format, vérité de l'état, sobriété, justification hors Explanation) — appliquée au bloc modifié, pas
au document entier. Corriger ce qui y manque avant de le présenter comme terminé.
