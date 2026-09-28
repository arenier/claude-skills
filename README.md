# claude-skills

Mes skills [Claude Code](https://claude.com/claude-code) — des procédures que je
répète assez souvent pour vouloir qu'elles soient exactes à chaque fois plutôt
que reconstruites de mémoire.

Un skill est un dossier contenant un `SKILL.md` : Claude Code le charge quand la
demande correspond à sa description. Il peut embarquer des scripts, que Claude
exécute au lieu de réinventer les commandes.

## Principe : script ou jugement

Chaque skill est découpé en étapes, et chaque étape est rangée d'un côté ou de
l'autre (d'après [Skill Design: The Script vs. LLM Split](https://claude-world.com/articles/skill-design-script-vs-llm/)) :

* **Script** — ce qui donne le même résultat à chaque fois : appels `gh`,
  collecte d'état, `grep`, validation de format, calcul d'un verdict à partir de
  règles, mise en forme d'un commentaire. Ça s'écrit en vrai code, que
  Claude se contente de lancer. Pas de prose qui décrit une commande à
  reconstituer.
* **Jugement** — ce qui dépend du contexte : choisir un nom, décider si un
  constat tient, trier une review, rédiger. Le `SKILL.md` n'y donne pas de
  procédure, mais un cadre : des critères, des contraintes, des exemples.

Le rythme est toujours le même : un script rapporte des faits, Claude en tire
une décision, le script suivant l'exécute. Chaque `SKILL.md` s'ouvre sur une
table **Déroulé** qui dit, étape par étape, qui fait quoi. Entre deux étapes, le
contrat est un format explicite — un `review.json` que `render.py` valide avant
de le mettre en forme, par exemple — plutôt qu'une consigne de présentation que
le modèle suivrait plus ou moins bien.

Les scripts sont référencés par `${CLAUDE_SKILL_DIR}`, que Claude Code remplace
par le dossier du skill. Ils demandent `bash`, `python3` (3.9 et plus), et `gh`
selon le skill.

Les skills sont distribués comme **marketplace de plugins** Claude Code (voir
[Marketplace `adri-skills`](#marketplace-adri-skills)).

## Marketplace `adri-skills`

Le repo est une [marketplace de plugins Claude Code](https://code.claude.com/docs/en/plugin-marketplaces),
déclarée dans [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).
Elle publie deux plugins, **`adri-plugin`** et **`documentation-plugin`**.

Ajouter la marketplace et installer le plugin, en interactif :

```
/plugin marketplace add arenier/claude-skills
/plugin install adri-plugin@adri-skills
```

Ou le référencer dans le `.claude/settings.json` d'un projet, pour que le plugin
soit disponible à tout le monde sans installation manuelle :

```json
{
  "extraKnownMarketplaces": {
    "adri-skills": {
      "source": { "source": "github", "repo": "arenier/claude-skills" }
    }
  },
  "enabledPlugins": {
    "adri-plugin@adri-skills": true
  }
}
```

Ce repo s'active lui-même `adri-plugin` de cette façon, dans son propre
[`.claude/settings.json`](.claude/settings.json). La source `github` sert la
version de `main` : une modification du plugin sur une branche ne s'applique
qu'une fois mergée.

### Plugin `adri-plugin`

Trois skills qui couvrent la vie d'une PR, de l'ouverture à la réponse aux
retours. Écrits pour [pick-a-book](https://github.com/arenier/pick-a-book) :
`pr-review` et `pr-review-triage` confrontent le diff aux ADR et conventions de ce
repo, `create-pr` en applique les conventions de branche et de PR.

| Skill | Rôle |
|---|---|
| `create-pr` | Ouvre une PR décrite — branche, commits, push, puis corps orienté relecture (contexte, modifications, tests, ADR, points d'attention). Scripts : relevé d'état, lint et tests, validation du titre et du corps avant ouverture. |
| `pr-review` | Relit une PR en la confrontant aux ADR et conventions ; produit une fiche de review et un commentaire prêt à coller. Consultatif : ne merge ni ne pousse. Scripts : collecte des fichiers en version PR, routage vers les ADR, `grep` hors-diff, calcul du verdict et mise en forme. |
| `pr-review-triage` | Traite une review déjà postée : vérifie chaque point contre le code, attribue un double verdict, applique les correctifs retenus avec test de non-régression, répond en commentaire. Scripts : collecte des retours avec leur péremption, mise en forme et mise à jour de la réponse, réécriture de message de commit. |

Les scripts communs (validation Conventional Commits, commit sur chemins
explicites, commentaire mis à jour par marqueur) sont dans
[`adri-plugin/scripts/`](adri-plugin/scripts/).

### Plugin `documentation-plugin`

Trois skills qui couvrent l'écriture de documentation selon la méthodologie
[Diataxis](https://diataxis.fr/) : un document ne doit tenir que dans un seul de ses quatre formats
(tutorial, how-to guide, reference, explanation). Les critères de chaque format et la checklist de
conformité commune sont dans [`documentation-plugin/diataxis.md`](documentation-plugin/diataxis.md).
`create` et `restructure` s'appuient sur `grilling` — une interview par rounds de questions, dont le
plugin embarque sa propre copie — pour déterminer le format visé quand il n'est pas donné
explicitement, et pour `create`, pour rassembler les sources du contenu.

| Skill | Rôle |
|---|---|
| `create` | Rédige une documentation neuve dans l'un des quatre formats. |
| `restructure` | Réécrit une documentation existante pour la faire tenir dans l'un des quatre formats. |
| `edit` | Ajoute ou modifie un élément d'une documentation existante, sans changer son format ni y introduire de justification hors du format `explanation`. |

Les trois skills relèvent d'abord, par
[`scripts/signals.py`](documentation-plugin/scripts/signals.py), les tournures qui
trahissent souvent un écart (état passé, justification, embranchement), puis les
tranchent une à une pendant la relecture de conformité.

## Licence

MIT
