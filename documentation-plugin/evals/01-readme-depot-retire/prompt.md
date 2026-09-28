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

## Installer les outils

Les skills de déploiement s'installent par lien symbolique depuis boite-a-outils :

```bash
git clone https://github.com/exemple/boite-a-outils.git
ln -s "$PWD/boite-a-outils/deploy-app-gcp" ~/.claude/skills/deploy-app-gcp
ln -s "$PWD/boite-a-outils/backup-app-gcp" ~/.claude/skills/backup-app-gcp
```

## Dépôts liés

| Dépôt | Visibilité | |
|---|---|---|
| [boite-a-outils](https://github.com/exemple/boite-a-outils) | public | skills `deploy-app-gcp` et `backup-app-gcp`, qui déploient et sauvegardent l'application ; marketplace `outils`, avec les plugins `pr-plugin` et `doc-plugin` |
| [app-run](https://github.com/exemple/app-run) | public | déploiement de l'application |
````

On a retiré les skills `deploy-app-gcp` et `backup-app-gcp` de boite-a-outils : ils créaient des écarts avec l'état Terraform, et c'est Terraform qui déploie le parc maintenant. Mets à jour le README en conséquence.
