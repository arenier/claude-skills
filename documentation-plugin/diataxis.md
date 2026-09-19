# Diataxis

Référence partagée par les trois skills du plugin (`create`, `restructure`, `edit`) : les critères
qui définissent chaque quadrant, et la checklist de conformité à appliquer avant de rendre la main.

Diataxis classe la documentation selon deux axes : ce qu'elle sert (apprendre / agir) et ce qu'elle
engage (action / cognition). Un même sujet peut avoir un document dans chacun des quatre quadrants ;
un seul document ne doit tenir que dans un seul.

## Les quatre formats

**Tutorial** — orienté apprentissage. Prend un débutant par la main sur un parcours concret, du
début à une réussite garantie. L'auteur décide du chemin, pas le lecteur : pas d'embranchement, pas
d'option. Explique le minimum nécessaire pour avancer — l'explication approfondie n'a pas sa place
ici, elle appartient à l'*explanation*.

**How-to guide** — orienté action. Résout un problème réel et précis pour quelqu'un qui sait déjà se
servir de l'outil. Suppose la compétence, va droit au but, s'adapte au contexte du lecteur plutôt que
de dérouler un seul chemin. Pas de pédagogie de démarrage, pas de justification des choix — seulement
les étapes vers le résultat.

**Reference** — orienté information. Décrit la mécanique avec exactitude et exhaustivité : une API,
une configuration, une commande. Structure calquée sur la structure du produit, pas sur l'usage —
faite pour être consultée, pas lue en continu. Austère : pas de récit, pas d'exemple pédagogique
développé, pas de rationale.

**Explanation** — orienté compréhension. Le seul quadrant où la justification, le contexte, les
alternatives écartées et le « pourquoi » ont leur place. Discute, met en perspective, relie à
d'autres concepts. N'explique pas comment faire — ça, c'est le how-to.

## Checklist de conformité

À appliquer en fin de skill, sur le résultat produit — jamais sur l'intention.

**Pureté du format**
- Le document ne tient que dans un seul quadrant ; aucun paragraphe n'emprunte aux critères d'un
  autre (pas d'explication dans un how-to, pas de tutoriel dans une reference, etc.).
- Le contenu satisfait les critères du quadrant annoncé (ci-dessus), pas seulement son titre ou son
  emplacement dans l'arborescence.

**Vérité de l'état**
- Chaque phrase est vraie dans l'état actuel du sujet documenté. Aucune trace de ce qui n'est plus
  vrai : pas de changelog, pas d'historique, pas de « auparavant X, désormais Y » dans le corps.
- Aucune ligne obsolète n'a été laissée à côté d'une ligne nouvelle qui la contredit.

**Sobriété**
- Un bloc modifié a été réécrit en entier plutôt que complété par des ajouts marginaux qui laissent
  la structure d'origine deviner le sens.
- Rien n'a été ajouté qui ne change pas la compréhension du lecteur.

**Justification (hors Explanation)**
- Dans `tutorial`, `how-to guide` et `reference` : aucune justification, aucun rationale, aucun
  « parce que » introduit par la modification. Un besoin de justifier une décision est un signal que
  le contenu appartient à un document `explanation` séparé, pas une raison de l'insérer ici.
- Dans `explanation` : cette règle ne s'applique pas — la justification est le contenu du quadrant.
