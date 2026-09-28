---
type: llm
focus: {source: file, path: docs/mettre-a-jour.md}
weight: 1
---
- La procédure de mise à jour change `image` dans `terraform/main.tf`, puis lance `terraform plan`, puis `terraform apply`.
- La section « Revenir à la version précédente » passe elle aussi par Terraform (remettre l'ancienne version dans `image`, puis plan et apply), et ne lance aucun script.
- Le document ne dit nulle part pourquoi on utilise Terraform.
- L'étape de vérification (`curl` sur `/health`) est toujours là.
