---
max_turns: 20
timeout_seconds: 400
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, "Bash(python3:*)"]
runs: 3
---
Écris un how-to guide pour configurer la sauvegarde quotidienne du service, dans `docs/sauvegarde.md`. Sources, complètes : la sauvegarde est un job `backup` ; on l'active avec `svc backup enable --schedule '0 3 * * *'`, on vérifie qu'il est planifié avec `svc backup list`, on restaure une sauvegarde avec `svc backup restore <id>`.
