---
description: >
  Create a detailed technical specification (.spec.md) that serves as an implementable
  blueprint for Business Central features. Use when you need to create a spec, write
  a specification, or detail a requirement. Reads architecture.md if exists.
  Outputs to requirements/{req_name}/.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch, Skill
---

# AL Technical Specification Workflow

Your goal is to generate a **detailed implementable technical specification** for `${input:req_name}` (complexity: `${input:Complexity}`).

This is **NOT** the architecture phase. This phase produces the implementable blueprint: exact object IDs, field types, procedure signatures, event patterns, and AL code snippets.

## Guardrails

- **Never** create or modify real AL objects during this phase
- **Never** output to `/specs/` — always output to `requirements/{req_name}/`
- If `{req_name}.architecture.md` exists, read it first — the spec must implement what the architect designed
- If spec already exists, confirm with user before overwriting
- Complexity drives depth within a section, not which sections exist: LOW condenses §§6-8 and may omit §12; MEDIUM/HIGH fills every applicable section in full. At every tier, **omit a conditional section entirely if the feature doesn't touch that object type** (see the template's own `## Rules`) — never scaffold a code skeleton for an object type this feature never creates

## Step 1 — Read Context

### 1.1 Read global memory

```
Read CLAUDE.md
```

Extract: project app ID range, naming conventions (prefix), existing table IDs in use, current extension patterns.

### 1.2 Read architecture document (if exists)

```
Read requirements/${input:req_name}/${input:req_name}.architecture.md
```

If it exists: the spec MUST align with the architectural decisions (data flows, chosen patterns, integration points).
If it does not exist: proceed — spec will define structure from scratch (typical for LOW complexity).

### 1.3 Analyze codebase

Search for:
- Existing objects with similar patterns (`Grep`/`Glob`; **al-mcp** `al_symbolsearch` for symbol-level)
- Naming conventions in `/src`
- Available object ID ranges in `app.json`
- Existing event publishers relevant to this feature
- Existing API pages or codeunits if integration is involved

> **Verify every base-app event you subscribe to against symbols — this is the spec's job, not the planner's.** For each event the feature hooks into, confirm it **exists** in the current BC version via the AL LSP server (document symbols, hover / go-to-definition) or al-mcp `al_symbolsearch` (download symbols first if absent). Record the **verified** publisher object + exact event name in §5. If you cannot confirm an event exists, it does **not** enter the spec as fact — move it to §12 Open Questions. (A wrong or nonexistent event name passed downstream silently becomes a blind search burst in planning and a defect the reviewer must catch. Verify it once, here, at the cheapest point.)

### 1.4 Ground the spec in the framework (token-light)

This spec is the blueprint `aldc:al-conductor` and `aldc:al-developer` implement from — it must be a **reliable guide**, not proposed from memory. Ground it without bloating this (cheap) primitive:

- **Instructions (always) — reference, don't recite.** The hard micro-rules under `rules-templates/` / the project's `.claude/rules/al-*` (naming ≤26 PascalCase, `DataClassification` on every field, extension-only, the performance/error-handling safety-net) govern every object you propose. They are tiny — honor them, and cite the governing one where a section depends on it.
- **Skills (on demand — one per domain the spec actually designs).** Invoke the **Skill** tool for a domain **only when the spec covers it**: §5 events → `bc-dev:skill-events`; §6 pages → `bc-dev:skill-pages`; §8 permissions → `bc-dev:skill-permissions`; §9 API → `bc-dev:skill-api`; AI/Copilot → `bc-dev:skill-copilot`; performance-critical logic → `bc-dev:skill-performance`; §7 tests → `bc-dev:skill-testing`. Do **not** load skills for domains the spec doesn't touch; for **LOW** complexity keep it minimal.

This keeps the median cost low (most specs touch 1–2 domains) while making the spec a framework-grounded guide instead of a from-memory proposal.

---
---

## Step 2 — Generate Specification

Create `requirements/${input:req_name}/${input:req_name}.spec.md` following the canonical structure in `${CLAUDE_PLUGIN_ROOT}/docs/templates/spec-template.md` — `Read` that file (it's the single source of truth for the 12-section structure; **do not** re-derive the section layout from memory) and fill in every placeholder with real values from this feature (object IDs from `app.json` idRanges, actual field/procedure signatures, symbol-verified events).

**Apply the template's own `## Rules` section, in particular:**
- Omit §3/§5/§6/§8/§9 entirely for any object type this feature doesn't touch (a permission-set-only change doesn't get a Data Model or Pages section) — this is the largest lever on this document's size, since most features touch 2-4 of the 5 conditional sections, not all five.
- Complexity (`${input:Complexity}`) controls depth **within** the sections that do apply, not which sections exist.
- Fill `**Version**`/`**Date**`/`**Complexity**`/`**Status**` from this run's actual values, and set `${req_name}` throughout.

After Step 1's symbol verification, populate §2 (AL Object Inventory) and §5 (Event Integration) with the **verified** facts only — anything that didn't resolve goes to §12 Open Questions, never invented.

For the **Next Steps** section at the end of the generated file, use:

```markdown
## Next Steps

**Complexity: ${input:Complexity}**

> **MEDIUM / HIGH:**
>
> ✅ Spec complete. Next:
> 1. Human reviews and approves this spec
> 2. Start TDD orchestration:
>    ```
>    agent `al-conductor`
>    ```
>    Conductor will read this spec + architecture.md and orchestrate planning → implementation → review.

> **LOW:**
>
> ✅ Spec complete. Next:
> 1. Human reviews and approves this spec
> 2. Direct implementation:
>    ```
>    agent `al-developer`
>    ```
>    Developer reads this spec and implements directly (no TDD orchestration needed).
```

---
---

## Handoff

| Complexity | Handoff to | Purpose |
|-----------|-----------|---------|
| MEDIUM / HIGH | `agent al-conductor` | TDD-orchestrated implementation (planning → implementation → review) |
| LOW | `agent al-developer` | Direct implementation using this spec as blueprint |

## Success Criteria

- ✅ Spec file created at `requirements/${input:req_name}/${input:req_name}.spec.md`
- ✅ Object IDs verified against `app.json` idRanges
- ✅ Architecture document consulted (if exists)
- ✅ The feature's **own** procedure signatures are complete (no "TBD"); base-app event targets recorded as **verified publisher + event name + consumed fields** (exact param list resolved from symbols at code time, not transcribed)
- ✅ Every subscribed base-app event was symbol-verified to exist (unverifiable ones moved to Open Questions)
- ✅ Test scenarios defined in Given/When/Then format
- ✅ Handoff section points to correct next agent per complexity
