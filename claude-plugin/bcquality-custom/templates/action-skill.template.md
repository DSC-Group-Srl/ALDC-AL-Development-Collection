# Template — BCQuality action skill (DSC `/custom/` layer)

Copy the block below to `skills/<family>/<id>.md`, strip this header, fill it in.

Write an action skill **only** when no existing BCQuality skill covers the job. Adding a
BC fact is a *knowledge file*, never a skill edit — BCQuality's own contributing rule, and
it applies to us too: skills are finders and appliers, knowledge files are what the agent
knows.

The one case where we genuinely need a new skill is the **proactive / authoring** path:
Microsoft ships 17 action skills and all of them are `review/`. A skill that returns
*applicable guidance* instead of *findings* has to be written by us.

---

```markdown
---
kind: action-skill
id: al-implementation-guidance
version: 1
title: AL implementation guidance
description: Returns the knowledge applicable to AL code about to be written, as a prescriptive worklist rather than findings.
inputs: [file-path, spec]
outputs: [findings-report]
bc-version: [all]
technologies: [al]
countries: [w1]
application-area: [all]
---

# AL implementation guidance

<What this skill does, in two sentences. Entry scores this `description` and `id`
against the caller's free-text `goal`, so the wording here is what makes the skill
reachable for goals like "implement", "generate", "write AL". Keyword overlap beats
prose.>

## Source

Which knowledge folders and tags to search, across the enabled layers.

## Relevance

Which frontmatter dimensions to filter on, per `skills/read.md` matching semantics.

## Worklist

How to narrow N candidates to the M that apply to *this* task — for an authoring skill,
the signal is the target objects and domains named in the spec, not a diff.

## Action

What to emit. For an authoring skill: one `info` finding per worklisted article, each
carrying a `references` object pointing at the knowledge file, so the caller can read the
rule before writing code. It emits no defects — there is no code yet to be wrong.

## Output

Conforms to the DO output contract (`skills/do.md`).
```

---

## Rules that bite

- `kind: action-skill` is what makes Entry consider the file at all. Without it the skill
  is invisible and is not even reported in `skipped[]`.
- `version` is copied into the dispatch record; bump it on every behavioural change so
  drift between dispatch and execution is detectable.
- The four step headings are the contract, not a suggestion — `skills/do.md` is the
  normative template and orchestrators parse against it.
- A skill that composes others declares them in `sub-skills` and becomes a super-skill,
  which changes Entry's precedence handling. Only do that deliberately.
- `skills/do.md:285` has a worked minimal example — *"a minimal action skill that cites
  applicable guidance for a changed AL file, without generating findings of its own"*.
  That is the closest upstream template to what an authoring skill needs. Start there.
