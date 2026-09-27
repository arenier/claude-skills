---
name: restructure
description: Restructure une documentation existante pour la faire tenir dans l'un des quatre formats Diataxis (tutorial, how-to guide, reference, explanation), en repartant du contenu déjà là plutôt qu'en le réécrivant depuis rien. À utiliser quand l'utilisateur demande explicitement de restructurer, réorganiser ou reformater une documentation existante vers un des quatre formats Diataxis — pas pour une simple correction ou un ajout ponctuel, c'est le rôle du skill `edit`.
---

# Restructurer une documentation

Faire tenir un document existant dans un seul quadrant Diataxis. Le contenu source contraint le
résultat : rien n'est réinventé, tout est réorganisé, coupé ou réécrit à partir de ce qui est déjà
là. Lire d'abord [`../../diataxis.md`](../../diataxis.md) pour les critères de chaque format et la
checklist de conformité de l'étape 5.

## Déroulé

| # | Étape | Qui |
|---|---|---|
| 1 | Lire le document source | jugement |
| 2 | Déterminer le format cible | jugement (interview `grilling` si besoin) |
| 3 | Restructurer | jugement |
| 4 | Relever les signaux de non-conformité | script `signals.py` |
| 5 | Relecture de conformité | jugement, sur la checklist et les signaux |

## 1. Lire le document source

Lire le document dans son intégralité avant toute décision. Identifier ce qu'il contient déjà par
nature de contenu (étapes guidées, procédure ciblée, description exhaustive, justification /
contexte) — cette matière brute, indépendamment de sa forme actuelle, est ce qui migrera vers le
document restructuré.

## 2. Déterminer le format cible

Si l'utilisateur a nommé le format cible sans ambiguïté, passer à l'étape 3.

Sinon, une interview `grilling` est nécessaire — mais **demander d'abord à l'utilisateur s'il veut
s'y prêter**, en une question simple, hors formalisme design tree : « Pour choisir le format cible,
je peux t'interviewer par rounds de questions (`grilling`) — tu préfères ça, ou que je te demande
directement lequel des quatre formats viser ? »

- **Oui** → appeler le skill `grilling`. Le design tree part du choix du quadrant cible ; en
  dépendent les questions sur ce qui, dans le contenu lu à l'étape 1, ne correspond à aucun des
  critères du format choisi et doit donc être coupé, déplacé vers un document séparé, ou signalé
  comme manquant.
- **Non** → demander directement, sans le formalisme `❓/➡️`, quel format viser parmi les quatre
  définis dans `diataxis.md`, puis signaler sans détour ce qui, dans le contenu lu à l'étape 1, n'y
  entre pas. Ne pas choisir le format à la place de l'utilisateur dans les deux cas.

## 3. Restructurer

Réécrire le document en entier dans le format cible plutôt que de retoucher la structure existante
par petites touches — une structure Diataxis mal formée ne se corrige pas en y ajoutant des sections,
elle se réécrit. Ce qui, dans la matière de l'étape 1, n'entre dans aucun critère du quadrant cible
sort du document (à signaler à l'utilisateur, jamais supprimé en silence si la matière semble encore
utile ailleurs). N'écrire que ce qui est vrai dans l'état actuel du sujet ; aucune trace de ce qui a
changé. Hors `explanation`, ne pas introduire de justification qui n'était pas déjà dans le contenu
source sous cette forme.

## 4. Relever les signaux

```bash
python3 ${CLAUDE_SKILL_DIR}/../../scripts/signals.py <fichier> <format-cible>
```

Liste les tournures qui trahissent souvent un écart au format cible (trace d'un état passé,
justification hors `explanation`, embranchement dans un `tutorial`). Un signal n'est pas une
violation, mais aucune de ces lignes ne doit échapper à l'étape suivante — en particulier celles
héritées du document source, que la restructuration a pu déplacer sans les requalifier.

## 5. Relecture de conformité

Avant de rendre la main, relire le document restructuré contre la checklist de `diataxis.md` (pureté
du format, vérité de l'état, sobriété, justification hors Explanation), en tranchant chaque signal de
l'étape 4. Corriger ce qui y manque avant de le présenter comme terminé.
