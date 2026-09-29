---
type: llm
focus: trace
weight: 2
---
- L'agent demande à l'utilisateur (par l'outil AskUserQuestion ou, à défaut, en texte) la nature de la tâche, le mode d'exécution (fil principal ou sous-agent) et s'il y a déjà eu un blocage avec un modèle moins cher.
- Il ne pose pas plus de trois questions de base à la fois.
- Il ne donne pas de recommandation ferme de modèle avant d'avoir ces réponses.
