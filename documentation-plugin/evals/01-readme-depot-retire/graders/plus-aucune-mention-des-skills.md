---
type: regex
target: {source: file, path: docs/README.md}
match: not_contains
flags: i
weight: 1
---
deploy-app-gcp|backup-app-gcp|ln -s
