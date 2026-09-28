---
type: regex
target: {source: file, path: docs/cli.md}
match: not_contains
flags: i
weight: 0.5
---
(auparavant|désormais|dorénavant|anciennement|précédemment|n'(est|sont|existe) plus|ne \w+ plus|a été (remplacé|renommé|supprimé)|obsolète|changelog)|renomm|version 3|\bv3\b
