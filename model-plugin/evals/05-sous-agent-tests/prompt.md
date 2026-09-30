---
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Skill, AskUserQuestion]
runs: 3
---
Je vais déléguer à un sous-agent l'écriture des tests unitaires du module `parser/` : trois fichiers, périmètre connu, rien d'autre à toucher. Aucun essai avant. Quel modèle et quel effort pour ce sous-agent, et qu'est-ce que je mets dans son prompt pour qu'il reste dans son périmètre ?
