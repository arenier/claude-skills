---
max_turns: 20
timeout_seconds: 400
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, "Bash(python3:*)"]
runs: 3
---
Voici notre `docs/premiers-pas.md`. Il n'est pas encore dans ce dossier : écris-le tel quel à ce chemin avant d'y toucher.

````markdown
# Premiers pas avec Mesure

Dans ce tutoriel, tu installes Mesure, tu crées ton premier tableau de bord et tu l'affiches dans ton navigateur.

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
````

Passe le tutoriel à Mesure 2. En version 2, l'installation se fait avec `pipx install mesure`, et `mesure init` s'appelle `mesure new`. Le reste ne change pas.
