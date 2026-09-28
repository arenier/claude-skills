---
max_turns: 20
timeout_seconds: 400
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, "Bash(python3:*)"]
runs: 3
---
Voici notre `docs/premiers-pas.md`. Il n'est pas encore dans ce dossier : écris-le tel quel à ce chemin avant d'y toucher.

````markdown
# Premiers pas avec Mesure

Dans ce tutoriel, tu installes Mesure 1.8, tu crées ton premier tableau de bord et tu l'affiches dans ton navigateur.

## 1. Installer Mesure

```bash
pip install mesure==1.8
```

## 2. Créer un tableau de bord

```bash
mesure init mon-tableau
```

Un dossier `mon-tableau/` apparaît, avec un fichier `tableau.yaml`.

## 3. L'afficher

```bash
mesure serve mon-tableau
```

Ouvre http://localhost:8000 : ton tableau de bord s'affiche.

## Recommencer

Pour repartir de zéro, supprime le dossier `mon-tableau/` et relance `mesure init mon-tableau`.
````

Mesure 2 est sortie et la 1.8 n'est plus maintenue. En version 2, on installe avec `pipx install mesure` (pip n'est plus supporté), et `mesure init` devient `mesure new`. Passe le tutoriel en version 2.
