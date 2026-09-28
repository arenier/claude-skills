---
max_turns: 20
timeout_seconds: 400
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, "Bash(python3:*)"]
runs: 3
---
Voici notre `docs/cli.md`. Il n'est pas encore dans ce dossier : écris-le tel quel à ce chemin avant d'y toucher.

````markdown
# Référence de la commande `rapport`

`rapport [options] <fichier>`

| Option | Valeur | Défaut | Effet |
|---|---|---|---|
| `--format` | `csv`, `json` | `csv` | Format du rapport produit. |
| `--out` | chemin | sortie standard | Fichier où écrire le rapport. |
| `--quiet` | — | désactivé | N'affiche que les erreurs. |

## Variables d'environnement

| Variable | Effet |
|---|---|
| `RAPPORT_OUT` | Valeur par défaut de `--out`. |
| `RAPPORT_FORMAT` | Valeur par défaut de `--format`. |

## Exemple

```bash
rapport --format json --out resultats.json donnees.csv
```
````

Dans la version 3, on a renommé `--out` en `--output` pour s'aligner sur les autres outils de l'équipe. Mets la référence à jour.
