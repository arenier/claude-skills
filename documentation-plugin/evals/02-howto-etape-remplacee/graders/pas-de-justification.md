---
type: regex
target: {source: file, path: docs/mettre-a-jour.md}
match: not_contains
flags: i
weight: 0.5
---
(parce qu|\bcar\b|puisqu|afin (de|qu)|pour qu|la raison|ce qui permet|pour éviter)
