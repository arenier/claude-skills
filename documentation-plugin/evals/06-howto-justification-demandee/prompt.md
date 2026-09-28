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
2. Changer la version de l'image dans `terraform/main.tf` :

   ```hcl
   image = "service:2.4.0"
   ```

3. Relire le plan, puis appliquer :

   ```bash
   terraform plan
   terraform apply
   ```

4. Vérifier que le service répond :

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' https://service.example.com/health
   ```
````

Ajoute dans ce guide pourquoi on a choisi Terraform plutôt que l'ancien script : le script créait des écarts avec l'état décrit en HCL.
