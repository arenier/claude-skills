# choose-model — evidence behind the mapping

Why [`SKILL.md`](SKILL.md) maps tasks to models and effort levels the way it does. Not loaded when the skill runs — read it when revising the mapping.

Collected 2026-09-29. Revisit when a new model ships or when real Claude Code sessions contradict it.

| | Sonnet 5.5 | Opus 5.5 | Source |
|---|---|---|---|
| Terminal-Bench 4.0 (agentic, terminal) | **70.6 %** | 66.4 % | Anthropic launch pages |
| FrontierCode 1.1 (hard code) | 46.2 % (max effort) | **54.4 %** | Anthropic launch pages |
| GDPval-AA v2.1 (knowledge work) | 1844 | 1846 | Anthropic launch pages |
| AA-Briefcase v1.1 | 1811 | 1822 | OrcaRouter article, citing Anthropic's table |
| AA Intelligence Index v4.3 — score / cost per task | 56 / $7.60 | **58 / $5.98** | Artificial Analysis, via OrcaRouter |
| Tokens generated over that suite | 410 M | **260 M** (≈ 1.6× less) | Artificial Analysis, via OrcaRouter |
| Per-token price (in / out, per M) | $2 / $10 | $4 / $20 | Anthropic launch pages |

Also from Anthropic: Opus 5.5 "performs at the level of Claude Fable 5.1 on most work" and beats it on GDPval-AA (1846 vs 1735); it finishes agentic tasks in about half the turns and output tokens of Opus 5.

From Anthropic's prompting guides: Opus 5.5 defaults to `medium` (Opus 5 defaulted to `high`), and `medium` matches or beats Opus 5 at `high`; it is strongest on multistep work in a real repository, long autonomous runs with parallel sub-agents, and code review (more bugs caught, fewer false alarms). Sonnet 5.5's guide recommends `medium` for well-specified agentic coding and `high` for harder or longer tasks, reserves `xhigh`/`max` for measured gains, and points to Opus for "the hardest long-horizon work"; its scope paragraph at `max` cut session cost by about a third with no quality change.

User feedback (r/ClaudeAI launch thread, bot-generated summary of ~50 comments, a few hours after release): Opus 5.5 as orchestrator and Sonnet 5.5 as worker is the most cited workflow; Sonnet 5.5 is near-identical to Opus on concrete tasks (bug fixing, basic research) but Opus still wins on nuanced judgment and makes fewer subtle or confidently wrong answers; Sonnet is reported verbose and "pushy", and one coding test saw it work outside its designated folder. Impressions, not measurements.

Caveats: the benchmark scores come from the vendor; the verbosity ratio comes from a single third-party harness, published by a routing vendor with an interest in "it depends", and hasn't been measured in Claude Code or across effort levels.

- https://www.anthropic.com/claude-opus-5-5
- https://www.anthropic.com/claude-sonnet-5-5
- https://www.orcarouter.ai/blog/claude-sonnet-5-5-vs-claude-opus-5-5
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5
