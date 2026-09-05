# BCQuality task-context (construction reference)

The **task-context** is the input a BCQuality consumer hands to `entry.md`. Per
the BCQuality consumption contract, the **orchestrator builds it** and the agent
consumes it — for the TDD loop the orchestrator is `@al-conductor`; for an
on-demand audit the orchestrator is Dredd itself. This file is the single source
of truth for *how* to build it, so the rule lives in one place, not copied into
every agent.

## Shape

```yaml
task-context:
  goal: "<what needs doing>"            # e.g. "review AL source changes" | "audit AL source"
  inputs-available: [pr-diff, file-path] # whichever the orchestrator actually has
  technologies: [al]
  bc-version: <from app.json; OMIT if unknown>
  countries: <from app.json; OMIT if unknown>
  application-area: <union of the changed objects' areas; OMIT if undeterminable>
  enabled-layers: [microsoft, community, custom]
  # disabled-skills: OMIT. See "No pilot, no denylist" below.
```

Only `goal` and `inputs-available` are required.

## The one rule that matters: OMIT, don't fake

Per READ, an **omitted** filter dimension is `unknown`, **not** a wildcard.
Derive `bc-version`/`countries` from `app.json` and `application-area` from the
*changed objects*; **OMIT anything you cannot determine**. Never substitute
`[all]`/`[w1]` for convenience — it over-matches knowledge files and inflates
confidence. The contract caps findings derived from an `unknown` dimension at
`confidence: medium`, which is the correct, honest outcome.

## No pilot, no denylist

**Do not send `disabled-skills`.** Every BCQuality review leaf is active.

This used to describe a three-leaf pilot (performance / security / style) whose
source of truth was `aldc.yaml → external.bcquality.pilotSkills`. That pilot
never actually ran: the plugin installs `rules-templates/*.md` into
`.claude/rules/` and nothing else, so no `aldc.yaml` ever reaches a project,
`pilotSkills` was always undefined, and the denylist was always empty. Every
leaf Entry dispatches has been running from day one — the pilot existed only in
this document.

Rather than build the plumbing to carry a denylist into projects, the pilot is
abolished: the full leaf set is what we already consume, and saying so out loud
is what lets the review agents reason correctly about their **native residual**
(the checks they own because no active leaf covers them, not because a leaf was
switched off).

Consequences worth knowing:

- The residual with BCQuality mounted is the repo-structure checks A/C/F/G.
  With BCQuality absent it expands to the full A–G. Nothing in between.
- Leaf coverage now grows on its own whenever upstream adds one. The weekly pin
  bump PR calls out added or removed leaves for exactly this reason.
- To genuinely exclude a leaf — a deliberate decision, not a pilot — add it to
  `disabled-skills` at that point and record why here.

## After building it

Hand the task-context to the BCQuality entry point (`<home>/skills/entry.md`, where
`<home>` is the hook's shared cache — default `~/.claude/bcquality`) and **execute whatever
`dispatch[]` returns** — do not assume which skills come back. Entry owns
routing; the consumer owns only the convention "invoke entry.md first."
