# claude-skills

Mes skills [Claude Code](https://claude.com/claude-code) — des procédures que je
répète assez souvent pour vouloir qu'elles soient exactes à chaque fois plutôt
que reconstruites de mémoire.

Un skill est un dossier contenant un `SKILL.md` : Claude Code le charge quand la
demande correspond à sa description. Il peut embarquer des scripts, que Claude
exécute au lieu de réinventer les commandes.

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

### Plugin `adri-plugin`

Trois skills qui couvrent la vie d'une PR, de l'ouverture à la réponse aux
retours. Écrits pour [pick-a-book](https://github.com/arenier/pick-a-book) :
`pr-review` et `pr-review-triage` confrontent le diff aux ADR et conventions de ce
repo, `create-pr` en applique les conventions de branche et de PR.

| Skill | Rôle |
|---|---|
| `create-pr` | Ouvre une PR décrite — branche, commits, push, puis corps orienté relecture (contexte, modifications, tests, ADR, points d'attention). |
| `pr-review` | Relit une PR en la confrontant aux ADR et conventions ; produit une fiche de review et un commentaire prêt à coller. Consultatif : ne merge ni ne pousse. |
| `pr-review-triage` | Traite une review déjà postée : vérifie chaque point contre le code, attribue un double verdict, applique les correctifs retenus avec test de non-régression, répond en commentaire. |

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

## Licence

MIT
