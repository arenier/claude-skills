---
type: regex
target: {source: file, path: docs/README.md}
match: contains
flags: i
weight: 1
---
pr-plugin[\s\S]*doc-plugin|doc-plugin[\s\S]*pr-plugin
