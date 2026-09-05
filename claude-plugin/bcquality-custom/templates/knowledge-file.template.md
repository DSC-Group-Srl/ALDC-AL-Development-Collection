# Template — BCQuality knowledge file (DSC `/custom/` layer)

Copy the block below to `knowledge/<domain>/<slug>.md`, strip this header, fill it in.
`<slug>` is kebab-case and states the rule, not the topic:
`object-prefix-registry` — good. `naming` — bad.

Admission test, from BCQuality's README, applied to *our* layer:

> If this file did not exist, would a capable LLM writing or reviewing DSC AL code make a
> mistake this file would have prevented?

If the answer is no — the rule is generic good practice, or Microsoft's layer already
covers it — **do not write the file**.

---

```markdown
---
bc-version: [all]              # or [26..28], or [26..] for "26 and later"
domain: style                  # style | performance | security | privacy | testing |
                               # data-modeling | error-handling | events | interfaces |
                               # ui | upgrade | telemetry | web-services | appsource | query
keywords: [prefix, affix, object-naming, dsc]
technologies: [al]
countries: [it, w1]            # ISO codes, or [w1]
application-area: [all]
---

# <One-line imperative statement of the rule>

## Description

What the rule is and *why* it exists here rather than in Microsoft's layer. State the
DSC-specific fact — the registry value, the range, the convention — plainly. No code
fences: samples live in sibling `.al` files.

## Best Practice

The recommended shape, in prose.

See sample: `<slug>.good.al`.

## Anti Pattern

What to avoid and the signal a reviewer should look for.

See sample: `<slug>.bad.al`.
```

---

## Hard limits

- under 100 lines total (target: under 50)
- all six frontmatter fields present
- `## Description` mandatory
- zero fenced code blocks in the article body
- every `See sample:` filename must exist as a sibling file

## Overriding a Microsoft rule

Same `domain` and an overlapping `keywords` set is what makes `/custom/` win by layer
precedence. Say so explicitly in `## Description` — *"overrides
`microsoft/knowledge/style/<file>.md` because …"* — so the suppression is legible in the
review report instead of looking like an accident.

Before writing an override, check the Microsoft article actually says what you think it
says. Most apparent conflicts turn out to be our rule being wrong.
