---
name: choose-model
description: Recommends which Claude model (Haiku 4.5, Sonnet 5.5, Opus 5.5, Fable 5.1) and effort level (low/medium/high/xhigh/max) to use for the task at hand, or for a sub-agent about to be spawned. Asks a short quiz (task nature, execution mode, prior blocking) with conditional follow-ups, then outputs a model+effort recommendation and the command to switch (`/model <name>`). Trigger on "quel modèle utiliser", "which model should I use", "dois-je passer sur Opus", "Sonnet ou Opus", "quel effort pour cette tâche", or before spawning a sub-agent whose model isn't obvious. Assumes a Max/Team subscription (not pay-per-token API) — session/context budget matters more than per-token price.
argument-hint: [description de la tâche à faire — optionnel]
---

# choose-model

Helps pick a `model` + `effort` pair for the task in front of the user (or a sub-agent about to be spawned), instead of defaulting to whatever model the session happens to be on. This skill decides nothing on its own — it asks a short quiz, then gives a recommendation the user can accept or override.

Assumes a **Max/Team subscription**, not pay-per-token API billing: per-token cost isn't the constraint, session/context budget is. If the user is actually on pay-per-token billing, say so up front and weigh cost more heavily in the recommendation.

## The axis that decides Sonnet vs Opus: bounded or open-ended

Sonnet 5.5 and Opus 5.5 are close on benchmarks, so capability alone no longer separates them. What does is **whether the size of the work is predictable**:

- **Bounded** — the scope is known before starting: a targeted bug fix, a script, tool/terminal-driven agent work, tests on a known surface, a document/slide/spreadsheet. Sonnet 5.5 is as good or better here (it leads on Terminal-Bench) and faster.
- **Open-ended** — nobody can say up front how many files, turns or tokens it will take: a refactor across modules, a migration, a design choice that commits the rest of the work, an investigation. Opus 5.5 leads on the hardest code, and it is markedly less verbose — on Max/Team, fewer output tokens means less session and context budget burnt for the same result.

**When unsure which one it is, treat it as open-ended.** Guessing "bounded" wrongly costs a long, verbose Sonnet run; guessing "open-ended" wrongly costs little, since Opus 5.5 is also fast.

## Method

1. Ask the base questions below with `AskUserQuestion`, one call (all 3 in the same call — they don't depend on each other).
2. If the answers land in a grey zone (see "Conditional follow-ups"), ask exactly the matching follow-up — never more than one extra round.
3. Look up the mapping table, state the recommendation, and give the switch command. Don't hedge with multiple options — pick one and justify it in a sentence.
4. If the task changes mid-session (new sub-task, got stuck), re-run the quiz rather than assuming the old recommendation still holds.

## Base questions

**Q1 — Task nature**
- Trivial: reading a file / formatting / a one-line fix
- Bounded: known scope — targeted bug fix, script, terminal/tool-driven work, tests, docs/slides
- Open-ended: multi-file refactor, migration, design choice, debugging that's resisting
- Deep research or a long-form deliverable over a multi-hour session

**Q2 — Execution mode**
- Main thread, real-time interaction
- Sub-agent / delegated task / async batch processing

**Q3 — Prior blocking signal**
- No, clean start
- Yes — already tried a cheaper model, it failed/got stuck 2-3 times on this exact point

## Conditional follow-ups

Ask **at most one**, only when it changes the recommendation:

- **Q1 = "bounded" but the description hints at more** (several files/modules, an implicit design choice, "and then we'll see") → *"Can you say roughly how many files it touches and when it's done, before starting?"* — a "no" moves it to the open-ended tier.
- **The session is already long / a harder task is expected soon** → *"Do you need to preserve context budget for something harder later in this session?"* — a "yes" pushes toward a cheaper model/effort now, or toward splitting into a fresh session instead of running one marathon on the expensive model (context budget doesn't reset with rate limits — spending it on a trivial task starves the hard task later). Don't push an open-ended task down to Sonnet to save budget: its verbosity can cost more than it saves.
- **Q2 = "sub-agent" but Q1 = open-ended/research tier** → *"Is the sub-agent itself doing the hard reasoning, or just executing a well-scoped delegated step?"* — only the latter gets the economy discount.

## Mapping table

| Q1 (task nature) | Q2 = main thread | Q2 = sub-agent (well-scoped) | Q3 = blocked → escalate to |
|---|---|---|---|
| Trivial / read / format | **Haiku 4.5**, effort `low`–`medium` | Haiku 4.5, effort `low` | Sonnet 5.5, effort `medium` |
| Bounded | **Sonnet 5.5**, effort `medium` (well-specified) – `high` (harder or longer) | Sonnet 5.5, effort `medium` (Haiku 4.5 if purely mechanical) | Opus 5.5, effort `high` |
| Open-ended / multi-file / stuck debug | **Opus 5.5**, effort `medium`–`high` | Sonnet 5.5, effort `high` only if the delegated step is itself bounded; otherwise Opus 5.5, effort `medium` | Opus 5.5, effort `xhigh`–`max` |
| Deep research / long-form, multi-hour | **Opus 5.5**, effort `high` | rarely delegated as-is; scope it down first | Opus 5.5 `xhigh`–`max`, then Fable 5.1 `high`–`max`, or split the session |

Context-budget follow-up answered "yes" → shift one column left (cheaper) for the *current* task, and if the harder task is imminent, recommend starting a **new session** for it rather than running both on the same expensive model back to back.

### Effort rules

- **Never carry an effort level over from the previous model.** Level names don't map to the same amount of thinking across models: Opus 5.5 at `medium` matches or beats Opus 5 at `high` on coding and knowledge work, and at a given level it thinks more per turn than Opus 5, especially at `xhigh`/`max`. Someone who ran Opus 5 at `high` should start Opus 5.5 at `medium`.
- **`xhigh` and `max` are escalations, not defaults**, on both models — only once the level below has fallen short on this exact point. On Sonnet 5.5 they also change behavior: after finishing, it starts its own review rounds, launches reviewer sub-agents and makes related fixes it noticed, which costs time and tokens on routine work.
- **No `low` for Sonnet 5.5 on code.** At `low` it can report a change as done without running the tests or the build; at `low` and `medium` on long agentic tasks it may also stop to check in before finishing. `low` stays fine for Haiku-tier trivial work and for Opus 5.5 on latency-sensitive chat.

**An open-ended task splits into orchestrator + workers.** Opus 5.5 in the main thread plans, cuts the work into steps and makes the judgment calls; each step it delegates that is bounded on its own goes to a Sonnet 5.5 sub-agent. When the recommendation is Opus 5.5 for an open-ended task that will fan out, say so in the output, so the sub-agents aren't spawned on Opus by inheritance.

## Output format

One line, no options menu:

> **Recommendation: `<model>`, effort `<level>`.** `<one-sentence reason citing the quiz answers>`. Switch with `/model <model-id>`.

Model ids: `claude-haiku-4-5-20251001`, `claude-sonnet-5-5`, `claude-opus-5-5`, `claude-fable-5-1`.

When the recommendation is a **Sonnet 5.5 sub-agent that writes code**, follow the line with the scope paragraph from Anthropic's Sonnet 5.5 prompting guide, to paste into the sub-agent's prompt (it limits the unrequested tests, docs and files Sonnet adds at every effort level):

```text
When the work the user asked for is done and checked, stop and report. Don't add features, tests, files, docs or refactors that weren't asked for. If you think one would help, mention it at the end instead of doing it.
```

If that sub-agent runs at `xhigh`/`max` (an escalation), add the guide's second paragraph too:

```text
When the work the user asked for is done and its checks pass, stop and report. Don't start extra rounds of review or hardening on your own, and don't launch reviewer sub-agents unless the user asked for a review. If you think a deeper review is worth doing, say so at the end.
```

## Guardrails

- Don't ask more than 3 base questions + 1 follow-up — this is a quiz, not a grilling session.
- Don't recommend Fable 5.1 by default, not even for the research tier — Opus 5.5 performs at its level on most work. Fable is a proven escalation only, once Opus 5.5 at `xhigh`/`max` has fallen short on this exact point.
- Never recommend Sonnet 5.5 for an open-ended task on the grounds that it's "cheaper": it's half the per-token price but produces more tokens per task, which is the number that counts on Max/Team.
- A Sonnet 5.5 sub-agent that writes files gets an explicit scope — the paths it may touch, ideally an isolated worktree — and its diff is read before it's accepted, on top of the scope paragraph above. Anthropic documents that it adds unrequested tests, docs and small files at every effort level, and early users report it can wander outside its designated folder.
- Never silently assume pay-per-token billing changes the recommendation — ask if it's unclear, since the whole mapping above is built for Max/Team.
- If the user already knows their answer to a question from earlier context in the conversation (e.g. they just said "this is a sub-agent for formatting"), skip asking it again — fill it in and only ask what's still unknown.


## Evidence

The benchmarks, guides and user feedback behind this mapping, with their caveats, are in [`EVIDENCE.md`](EVIDENCE.md). Not needed to run the quiz — read it only when revising the mapping.
