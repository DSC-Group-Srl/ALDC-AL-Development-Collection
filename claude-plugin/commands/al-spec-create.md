---
description: >
  Create a detailed technical specification (.spec.md) that serves as an implementable
  blueprint for Business Central features. Use when you need to create a spec, write
  a specification, or detail a requirement. Reads architecture.md if exists.
  Outputs to app/requirements/in-progress/{req_name}/.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch, Skill, mcp__plugin_bc-dev_al-mcp__al_symbolsearch, mcp__plugin_bc-dev_al-mcp__al_symbolrelations, mcp__plugin_bc-dev_al-mcp__al_downloadsymbols
argument-hint: "<req_name> <Complexity>"
---

# AL Technical Specification Workflow

**Inputs** — parse from `$ARGUMENTS`: `{req_name}`, `{Complexity}`. Ask the user for any that are missing before starting; never leave a `{placeholder}` unresolved in an output file.

Your goal is to generate a **detailed implementable technical specification** for `{req_name}` (complexity: `{Complexity}`).

This is the implementable blueprint — exact object IDs, fields, public procedure signatures,
symbol-verified events, and the test plan. At MEDIUM it also carries the design decisions
(§Decisions), so no separate architecture document is needed; at HIGH it implements
`{req_name}.architecture.md`.

## Guardrails

- **Never** create or modify real AL objects during this phase.
- Output only to `app/requirements/in-progress/{req_name}/` (the move to `archived/` is
  al-conductor's job when the requirement ships).
- If `{req_name}.architecture.md` exists (HIGH), read it first — the spec implements it and
  references its TD-ids instead of repeating them.
- If the spec already exists, confirm with the user before overwriting.
- There is **no separate test-plan file**: §7 of the spec is the test plan.

## Step 1 — Read context

1. `CLAUDE.md` — app ID range, prefix, conventions.
2. `{req_name}.architecture.md` if present.
3. The codebase: similar objects (`Grep`/`Glob`, al-mcp `al_symbolsearch`), naming, free IDs in
   `app.json` `idRanges` (app **and** test app), existing publishers/API pages in the area.
   Files over ~350 lines: ask `al-file-reader` for locations, then read ranges.

> **Verify every base-app event you subscribe to against symbols — here, once, at the
> cheapest point.** Confirm it exists in the current BC version via al-mcp `al_symbolsearch`
> or the AL LSP (download symbols first if absent). Record the verified publisher + event
> name + consumed fields in §5. Anything unconfirmed goes to §12 Open Questions, never into
> §5 as fact — a wrong event name downstream becomes a blind search burst and a review defect.

**Ground it, token-light.** The rules floor is loaded as project rules — honour it (naming,
`DataClassification`, extension-only). Invoke a domain skill only for a domain the spec
actually designs: §5 → `bc-dev:skill-events`, §6 → `bc-dev:skill-pages`, §8 →
`bc-dev:skill-permissions`, §9 → `bc-dev:skill-api`, AI → `bc-dev:skill-copilot`, hot paths →
`bc-dev:skill-performance`, §7 → `bc-dev:skill-testing`. LOW: keep it minimal.

## Step 2 — Write the spec

Create `app/requirements/in-progress/{req_name}/{req_name}.spec.md` from
`${CLAUDE_PLUGIN_ROOT}/docs/templates/spec-template.md` — `Read` it; it is the single source of
truth for the structure. Fill every placeholder with real values and apply its `## Rules`:

- Omit §3/§5/§6/§8/§9 entirely for object types the feature does not touch — the largest
  lever on this document's size.
- `{Complexity}` controls depth inside applicable sections. MEDIUM fills §Decisions (the
  architecture replacement); LOW may skip it.
- §2 must list every object **including test codeunits** with real free IDs — al-conductor
  builds its work packages directly from this table.
- §7 assigns every Given/When/Then scenario to a test codeunit from §2.

End the file with:

```markdown
## Next Steps

**Complexity: {Complexity}**

- **LOW** → approve this spec, then `agent al-developer` implements it directly.
- **MEDIUM / HIGH** → approve this spec (for HIGH this approval also covers the architecture),
  then `agent al-conductor` plans work packages, runs them, and tests them on the lane.
```

## Handoff

Spec approval is the **one** human gate before implementation starts.

| Complexity | Handoff to | Purpose |
|-----------|-----------|---------|
| LOW | `agent al-developer` | Direct implementation from this spec |
| MEDIUM / HIGH | `agent al-conductor` | Work-package plan → parallel implementation → review + test lane |

## Success Criteria

- Spec file created at `app/requirements/in-progress/{req_name}/{req_name}.spec.md`
- Object IDs (app and test) verified free within `idRanges`
- Architecture document consulted and referenced (HIGH)
- §Decisions filled (MEDIUM)
- The feature's own public procedure signatures complete (no "TBD"); base-app events recorded
  as verified publisher + event name + consumed fields
- Every subscribed base-app event symbol-verified (unverifiable ones in §12)
- §7 test scenarios in Given/When/Then, each assigned to a test codeunit
