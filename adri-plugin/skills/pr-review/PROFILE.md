# Profil de dépôt pour `pr-review`

Le skill ne connaît aucun dépôt. Un dépôt qui veut une relecture adaptée dépose
`.claude/pr-review.json` à sa racine. Le profil est **optionnel** : sans lui, seules les
vérifications générales s'appliquent (tests des fichiers touchés, jumeaux) et les décisions se
découvrent à la lecture.

`collect.sh` lit ce fichier sur la **branche de base** de la PR, jamais sur la branche relue : son
auteur pourrait sinon réécrire le référentiel qui le juge. Une routine cloud fait de même, par
`get_file_contents` au ref de la branche par défaut.

Tous les champs sont optionnels. Les motifs sont des expressions régulières Python, appliquées aux
chemins du dépôt (champs `paths`, `changed`, `companion`, `except`, `stakes`, `import_zones`) ou au
texte des lignes ajoutées (`pattern`, `ignore`).

| Champ | Rôle |
|---|---|
| `index` | Fichiers d'entrée des conventions, lus toujours. Défaut : `CLAUDE.md`, `AGENTS.md`. |
| `decisions` | Dossier des décisions actées (ADR). |
| `rules` | Dossier des rules ; celles dont le frontmatter `paths` cible un fichier du diff s'y appliquent. |
| `routes` | `[{paths, read, refs}]` — pour un chemin qui correspond, `read` dit quoi confronter et `refs` liste les décisions à ouvrir. |
| `stakes` | Chemins à enjeu, qui remplissent le critère d'enjeu du second avis. |
| `import_zones` | Chemins où chaque import ajouté est listé, pour juger les frontières. |
| `locked` | `[{pattern, label, paths?, ignore?}]` — constructions proscrites, cherchées dans les lignes ajoutées. `paths` restreint les fichiers, `ignore` écarte des lignes (imports, commentaires). |
| `required` | `[{paths, contains, label}]` — un fichier qui correspond doit contenir `contains` dans sa version PR. |
| `tests` | `{source, test}` — ce qui est un fichier source et un fichier de test. Défaut : les extensions usuelles et `.spec.`, `.test.`, `_test`, `test_`, `tests/`. |
| `companions` | `[{id, label, changed, companion, except?, warning, judge?, if_confirmed?}]` — des fichiers qui vont de pair (un schéma et sa migration). Alerte si `changed` est touché sans `companion`. |
| `checks` | `[{id, label, judge, if_confirmed?}]` — vérifications à juger, sans script. |
| `notes` | Texte libre pour le relecteur : ce qui ne concerne pas ce dépôt, ce qui y est une forme normale. |

Chaque `id` de `companions` et de `checks` devient une ligne de la fiche : `review.json` y répond
dans `checks.<id>`, et `render.py` refuse s'il en manque une.

Exemple réel : le `.claude/pr-review.json` du dépôt `arenier/pick-a-book`.
