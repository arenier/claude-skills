---
type: llm
focus: {source: file, path: docs/mettre-a-jour.md}
weight: 1
---
- Le document reste un how-to : une suite d'étapes numérotées vers le résultat, sans explication de pourquoi Terraform.
- L'étape de déploiement est récrite : modifier `image` dans `terraform/main.tf`, puis `terraform plan`, puis `terraform apply`, dans cet ordre.
- Aucune trace de l'ancienne méthode : pas de script, pas de « au lieu de », pas de deux méthodes côte à côte.
- L'étape de vérification (`curl` sur `/health`) est toujours là.
