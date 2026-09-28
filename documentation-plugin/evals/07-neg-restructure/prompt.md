---
max_turns: 20
timeout_seconds: 400
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, "Bash(python3:*)"]
runs: 3
---
Voici notre `docs/mettre-a-jour.md`. Il n'est pas encore dans ce dossier : écris-le tel quel à ce chemin avant d'y toucher.

````markdown
# Mettre à jour le service

On est passé à Terraform parce que le script créait des écarts avec l'état décrit en HCL : le plan suivant proposait d'annuler la mise à jour.

1. Changer la version de l'image dans `terraform/main.tf` (`image = "service:<version>"`).
2. Lancer `terraform plan`, relire, puis `terraform apply`.
3. Vérifier avec `curl -s -o /dev/null -w '%{http_code}\n' https://service.example.com/health`.

Tu peux aussi passer par la console GCP si tu préfères, mais c'est déconseillé.
````

Réorganise entièrement ce guide pour en faire un tutoriel, destiné à quelqu'un qui n'a jamais déployé le service.
