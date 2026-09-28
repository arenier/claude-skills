---
type: regex
target: {source: file, path: docs/README.md}
match: not_contains
flags: i
weight: 1
---
(retir|ancien|supprim|ne contient plus|n'\w+ plus|désormais|deploy-app-gcp|backup-app-gcp)
