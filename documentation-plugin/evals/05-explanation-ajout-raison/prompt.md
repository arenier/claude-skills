---
max_turns: 20
timeout_seconds: 400
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, "Bash(python3:*)"]
runs: 3
---
Voici notre `docs/pourquoi-sqlite.md`. Il n'est pas encore dans ce dossier : écris-le tel quel à ce chemin avant d'y toucher.

````markdown
# Pourquoi SQLite

Le service stocke ses données dans un fichier SQLite plutôt que dans une base PostgreSQL managée.

## Le coût

Une base managée facture une instance allumée en permanence, même sans trafic. Le service reçoit quelques requêtes par jour : un fichier SQLite posé dans un bucket ne coûte que son stockage.

## La simplicité

Pas de réseau privé à configurer, pas d'identifiants de base à faire tourner : la sauvegarde est une copie de fichier.

## Les contreparties

La base ne se partage pas : aucun autre service ne peut l'interroger directement.
````

Ajoute la raison pour laquelle le service est limité à une seule instance : SQLite sur un bucket monté en gcsfuse ne supporte pas deux écrivains concurrents, et deux instances corrompraient la base.
