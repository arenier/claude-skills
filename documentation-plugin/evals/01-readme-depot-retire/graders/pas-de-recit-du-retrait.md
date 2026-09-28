---
type: regex
target: {source: file, path: docs/README.md}
match: not_contains
flags: i
weight: 1
---
(retir|ancien|supprim|n'\w+ plus|désormais|écart)
