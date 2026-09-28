---
max_turns: 20
timeout_seconds: 400
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, "Bash(python3:*)"]
runs: 3
---
Voici notre `docs/mettre-a-jour.md`. Il n'est pas encore dans ce dossier : écris-le tel quel à ce chemin avant d'y toucher.

````markdown
# Mettre à jour le service

1. Choisir la version à déployer dans les notes de version.
2. Lancer le script de déploiement avec cette version :

   ```bash
   VERSION=2.4.0 ./deploy.sh mon-projet
   ```

3. Vérifier que le service répond :

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' https://service.example.com/health
   ```

## Revenir à la version précédente

Relancer le script avec la version d'avant :

```bash
VERSION=2.3.1 ./deploy.sh mon-projet
```
````

On a abandonné `deploy.sh` : il créait des écarts avec l'état décrit dans Terraform. Maintenant, la version se change dans `terraform/main.tf` (`image = "service:<version>"`), puis `terraform plan` et `terraform apply`. Corrige le guide.
