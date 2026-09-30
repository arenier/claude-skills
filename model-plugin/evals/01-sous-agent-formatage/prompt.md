---
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Skill, AskUserQuestion]
runs: 3
---
Avant de lancer un sous-agent, je veux savoir quel modèle et quel effort lui donner. Sa tâche : reformater 40 fichiers JSON (indentation à 2 espaces, clés triées), rien d'autre, aucune décision à prendre. C'est un premier essai, rien n'a échoué avant.
