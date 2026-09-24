# Template — Plan (work-package graph + wave log)

`app/requirements/in-progress/{req}/{req}.plan.md`, written by al-conductor after plan approval
and appended to after every wave. It is also the resume point: a restarted conductor reads it
and continues after the last logged wave. Replace placeholders; drop sections that are empty.

```markdown
# Plan: {req} — {title}

{1–2 sentences: what gets built, why.}

**Tier:** {MEDIUM|HIGH} · **Base:** {commit sha the run started from} · **Branch:** aldc/{req}
**Test environment:** {launch.json configuration name | none — tests not executed (accepted by user)}
**Approved:** {date}

## Work packages

| WP | Title | Wave | Depends on | Owns (globs) | Objects (IDs) | Test codeunits (IDs) | Domains | Review |
|----|-------|------|-----------|--------------|---------------|----------------------|---------|--------|
| WP-1 | Data model | 1 | — | `app/src/Feature/Tables/**` | Table 50100 "…", Enum 50101 "…" | 50200 "… Tests" | tables | light |
| WP-2 | Posting logic | 2 | WP-1 | `app/src/Feature/Posting/**`, `app-test/src/Feature/Posting/**` | Codeunit 50110 "…" | 50210 "…" | events, performance | full |

**Shared single-writer files** (applied by the conductor per wave, never by a WP):
permission sets, `app/app.json`, `app-test/app.json`, `Translations/*.xlf`, `.vscode/*`.

**Codeunit → WP:** 50200 → WP-1 · 50210 → WP-2

## Open questions

1. {question — options} → {answer, once given}

## Wave log

### Wave 1 — {date}
- WPs: WP-1 · review: {verdict} ({b}/{M}/{m}) · lane: {passed/total | not executed} · fix rounds: {n}
- Evidence: 🟢 BCQuality {sha} · 📚 {P}/{C}/{D} · 🧠 {skill·tag, …}
- Shared files applied: {… | none}

## Deferred

- {what} — surfaced in wave {k} by {WP-n | review} — {later wave | backlog}
```

## Rules

- WP `owns` globs must not overlap; shared files appear in no WP.
- IDs are allocated here, from the app's and the test app's `idRanges` — workers never choose.
- MEDIUM: 1–3 WPs in ≤2 waves. HIGH: ≤6 WPs in ≤3 waves. Split only for disjoint files or a
  real dependency.
- No code blocks, no step-by-step TDD recipes (the implementer owns the method).
