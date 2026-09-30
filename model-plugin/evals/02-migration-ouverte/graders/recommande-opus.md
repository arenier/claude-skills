---
type: llm
weight: 2
---
Réponds PASS si la recommandation principale pour le fil principal, en tête de réponse, est Opus 5.5 avec l'effort `medium` ou `high`. Citer Sonnet 5.5 pour des sous-agents, ou `xhigh`/`max`/Fable comme escalade en cas d'échec, est permis.

Réponds FAIL si le fil principal est recommandé sur un autre modèle, ou d'emblée en `low`, `xhigh` ou `max`, ou si la réponse ne tranche pas.
