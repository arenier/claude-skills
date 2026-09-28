---
type: regex
target: {source: file, path: docs/mettre-a-jour.md}
match: not_contains
flags: i
weight: 1
---
pourquoi|parce que|\bcar\b|au lieu du script|plutôt que l'ancien
