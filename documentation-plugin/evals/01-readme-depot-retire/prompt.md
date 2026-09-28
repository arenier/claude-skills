---
max_turns: 20
timeout_seconds: 400
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, "Bash(python3:*)"]
runs: 3
---
Voici notre `docs/README.md`. Il n'est pas encore dans ce dossier : écris-le tel quel à ce chemin avant d'y toucher.

````markdown
# infra

Ce que j'héberge, et comment c'est tenu.

## Dépôts liés

| Dépôt | Visibilité | |
|---|---|---|
| [boite-a-outils](https://github.com/exemple/boite-a-outils) | public | skills `deploy-app-gcp` et `backup-app-gcp`, qui déploient et sauvegardent l'application ; marketplace `outils`, avec les plugins `pr-plugin` et `doc-plugin` |
| [app-run](https://github.com/exemple/app-run) | public | déploiement de l'application |
````

Les skills `deploy-app-gcp` et `backup-app-gcp` ont été retirés de boite-a-outils : le parc est maintenant déployé par Terraform. Mets à jour la ligne de ce dépôt dans le README.
