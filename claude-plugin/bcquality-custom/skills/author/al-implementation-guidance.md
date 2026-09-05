---
kind: action-skill
id: al-implementation-guidance
version: 1
title: AL implementation guidance
description: Prescriptive guidance for AL code about to be written. Use when the goal is to implement, generate, author, write or design AL objects — before the code exists. Returns the applicable knowledge as a worklist to write against, not findings about a diff.
inputs: [spec, file-path]
outputs: [findings-report]
bc-version: [all]
technologies: [al]
countries: [w1]
application-area: [all]
---

# AL implementation guidance

Every action skill BCQuality ships is a `review/` skill: they answer *"what is wrong with
this code?"* and need a diff or a file that already exists. Nothing answers *"what should I
know before writing it?"*, so an implementation goal reaches Entry and comes back
`no-match`.

This skill fills that gap. Same corpus, same READ semantics, same DO output contract —
different question. It emits **no defects**: there is no code yet to be wrong. It emits the
knowledge that applies to what is about to be written, each entry cited to its file, so the
implementer writes against the same rules the review will later judge by.

> **DSC note.** This is the only skill in our `/custom/` layer, and it is mechanism rather
> than knowledge: it retrieves Microsoft's corpus for a different question. DSC-specific
> *rules* belong in `/custom/knowledge/`, which is deliberately still empty.

## Source

All knowledge files under `*/knowledge/**` across the layers named in
`task-context.enabled-layers`. Use `knowledge-index.json` at the clone root for discovery
when it exists (Entry's Preparation step regenerates it); fall back to collecting by domain
folder when it does not.

Layer precedence per READ: `/custom/` over `/community/` over `/microsoft/`. A `/custom/`
article that overrides a shared one suppresses it — record that in `suppressed[]` exactly as
a review skill would, so the implementer can see which rule won.

## Relevance

Filter by frontmatter per READ's matching semantics: `bc-version`, `technologies`,
`countries`, `application-area`. An omitted task-context dimension is `unknown`, not a
wildcard — findings derived from an unknown dimension are capped at `confidence: medium`,
same as anywhere else.

## Worklist

This is where an authoring skill differs from a review skill, and the difference is the
whole point: **there is no diff to intersect against.** The task signal comes from what the
caller is about to build.

Derive the worklist from, in order of strength:

1. **Object types named in the input** — a phase creating a `tableextension` and an
   `[EventSubscriber]` pulls `data-modeling` and `events`; one creating an API page pulls
   `web-services`, `style` (the API-page articles) and `performance`.
2. **Domains the spec names explicitly** — telemetry, privacy, upgrade, AppSource
   compatibility, permissions.
3. **Keyword overlap** between article `keywords` and the vocabulary of the spec excerpt:
   the base objects touched, the operations described, the field types involved.

Then rank and **cap the worklist at 12 articles**. This cap is deliberate. READ requires
that a finding cite only an article opened and read *in full*, so an uncapped worklist would
pull the whole corpus into the implementer's context and defeat the point. Prefer:

- articles whose `## Anti Pattern` matches a construct the phase will certainly write, over
  articles that merely share a domain;
- `blocker`- and `major`-shaped rules (compile-breaking, data-losing, security) over style;
- `/custom/` articles over shared ones at equal relevance — they encode a house decision.

Drop the rest silently. An implementer given twelve rules applies twelve rules; an
implementer given sixty applies none.

## Action

Open each worklisted article in full and emit one finding per article:

- `severity: "info"` — always. These are prescriptions, not defects; nothing here gates.
- `message` — the rule stated **imperatively and self-contained**, so the implementer can
  act on it without opening the file: *"Copy event subscriber parameter names verbatim from
  the publisher; AL binds by name and a renamed parameter does not bind."* Not *"see the
  article on subscriber parameter names."*
- `references` — `[{ path, sha }]` pointing at the article. `id` MUST equal
  `references[0].path`, per DO: citation ids are never rewritten.
- `location` — omit. There is no code yet, so there is no line to point at. Emitting a
  fabricated location is worse than emitting none.
- `fix-hint` — where the article has a `## Best Practice`, the shape to write, in one line.
- `confidence` — as READ dictates from the dimensions actually known.

Do **not** emit agent findings here. The anti-correlation valve belongs in review, where
there is an artifact to judge; inventing prescriptions from the model's own opinion at
authoring time is how unreviewable house rules get born.

Set `outcome`:

- `completed` — a worklist was produced (even a short one).
- `no-knowledge` — the corpus has nothing for these domains. Say so plainly: it is a real
  and useful answer, and it tells the reviewer that this phase's domains are native
  residual, not covered ground.
- `not-applicable` — the inputs do not describe AL work.

## Output

Conforms to the DO output contract, with `summary.counts` reporting every finding under
`info`. The orchestrator hands the resulting list to the implementer as its prescriptive
worklist, and passes the same list to the reviewer so it can tell a **prescribed** rule from
one the review discovered on its own.
