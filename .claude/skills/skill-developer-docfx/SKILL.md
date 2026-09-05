---
name: skill-developer-docfx
description: >
  Full workflow for creating a technical developer/internals documentation site for Business
  Central PTE (per-tenant) extensions, published as a docfx static site — the PTE counterpart
  to skill-aldoc. Use this skill whenever the user mentions: documenting how a PTE app works
  internally, writing a technical functionality site, mapping algorithms and business logic for
  developers or AI agents, architecture-overview docs, or building a "developer reference" for
  an extension that has no public API surface to run aldoc against. Also trigger when the user
  asks how a PTE extension's internals should be documented, or why aldoc isn't appropriate for
  a given app (no AppSource-facing interface).
---

# Developer Internals Documentation — docfx (PTE apps)

> Brand CSS template: `references/main.css`
> Agent-assisted sweep guide: `references/agent-sweep-guide.md`

---

## Overview

This skill is the **PTE counterpart to `skill-aldoc`**. Both produce a technical, developer-facing
docfx site at the same location — `docs/developer/en-US/` — but they map fundamentally different
things:

- **skill-aldoc** documents the app's **public interface surface** (objects, public procedures,
  integration events, fields, enum values) via XML doc comments, extracted from the compiled
  `.app` by the `aldoc` CLI tool. It suits AppSource/Global apps, which expose a real API surface
  for external consumers.
- **skill-developer-docfx** (this skill) documents **how the app works internally** — algorithms,
  data flow, module architecture, design rationale — for a PTE app. PTE apps typically have no
  meaningful public API surface to extract; what matters instead is that a developer (human or AI
  agent) picking up this codebase later can understand its internals well enough to safely extend
  or debug it.

Content here is written entirely in Markdown, hand-authored by reading the AL source — **no
aldoc, no dependency on XML doc comments** (though if they happen to exist, read them as one more
source of intent). This mirrors how `skill-functional-docfx` hand-authors content instead of
extracting it, just aimed at a developer audience instead of an end user.

**Never run this skill and skill-aldoc against the same app.** Determine app type first (PTE vs
AppSource/Global) — this skill assumes the caller (typically `al-documentation-subagent`, or a
user working on a known-PTE app) has already made that determination.

---

## Pipeline overview

```
.al sources → read & analyze → write internals/*.md → docfx build → _site/ (HTML)
```

No compile step is required to produce documentation (unlike aldoc, this skill never reads
compiled `.app` metadata) — but if the app doesn't currently compile, note that as a caveat in
`constraints.md` rather than blocking the documentation pass.

---

## Quick-reference: what to map and where

| Source material | Becomes | Written for |
|---|---|---|
| Module/folder structure, cross-codeunit dependencies, call graph between subsystems | `internals/architecture-overview.md` | "Where do I start reading this codebase?" |
| Key tables, their keys/relations, and *why* they're modeled that way | `internals/data-model.md` | "Why does this table look like this?" |
| Each significant algorithm or business-logic subsystem (posting routines, allocation engines, calculation/pricing logic, state machines, batch processing) | one page per subsystem under `internals/`, named from the actual source (e.g. `internals/allocation-algorithm.md`, `internals/posting-flow.md`) | "How does this actually work, step by step?" |
| Integration events (published) and internal event subscribers | `internals/integration-events.md` | "What hooks exist, and what already listens to them?" |
| Interfaces, enums, or facade codeunits meant as extension points | `internals/extension-points.md` | "Where do I plug in new behavior?" |
| Non-obvious behavior, workarounds, known tech debt, deliberate deviations from BC conventions | `internals/constraints.md` | "What will surprise me / what should I NOT casually refactor?" |

Not every app needs every page — omit a page if the app genuinely has nothing to say for that
category (e.g. no integration events published → skip `integration-events.md`). Do not pad with
empty sections.

---

## Phase 1 — Analysis and writing (ALWAYS do this before building)

### Step 1 — Choose your approach based on codebase size

**First action**: count the `.al` files in the source folder.

```powershell
(Get-ChildItem "app\Source" -Recurse -Filter "*.al").Count
```

| File count | Approach |
|---|---|
| **≤ 50 files** | Work manually — read each file inline, build the subsystem inventory, write pages directly (continue with Steps 2–3 below) |
| **> 50 files** | Use AI agents — read `references/agent-sweep-guide.md` and follow it. 1 agent per feature-folder group produces a technical summary of its module's algorithms/functionality. Return here only after the sweep is complete. |

### Step 2 — Build the subsystem inventory *(manual path only)*

Read the AL source with a different lens than a functional read: not "what does the user click,"
but "what does this code actually do and why is it built this way." For each folder/module,
identify:

- **Entry points** — public procedures or event subscribers that kick off a subsystem
- **The algorithm itself** — the actual logic: loops, calculations, state transitions, posting
  sequences, decision branches
- **Data touched** — which tables/fields are read, written, or locked, and in what order
- **Edge cases and guards** — validation, error paths, early exits, and *why* they exist
- **Dependencies** — which other subsystems/codeunits this one calls into or is called by

Classify each subsystem the same way `skill-aldoc` classifies procedures:
- **MISSING** — no internals documentation exists yet for this subsystem
- **SHALLOW** — a page exists but doesn't actually explain the algorithm (e.g. just restates
  object names)
- **OK** — already documented with real technical content

### Step 3 — Write every subsystem page *(manual path only)*

**Quality bar — every page must answer:**
1. What does this subsystem *do*, concretely — walked through step by step?
2. *Why* is it built this way — what business rule or technical constraint drove the design?
3. What would surprise a developer extending this later — edge cases, ordering dependencies,
   performance considerations, things that look like bugs but aren't?

A page that only restates object/procedure names ("PostAllocation posts the allocation") is
unacceptable — this is the same bar `skill-aldoc` applies to a single procedure, just at the
scope of a whole subsystem.

**Subsystem page template**

```markdown
# [Subsystem name, e.g. "Allocation Algorithm"]

[One paragraph: what this subsystem is responsible for and where it sits in the overall app.]

## Entry points
- `Codeunit "X".ProcedureName()` — [when/how this gets invoked]

## How it works
[Step-by-step technical walkthrough. Use numbered steps or a short sequence description.
Reference actual AL object/procedure/table names — this is a developer audience, unlike the
functional site.]

1. [Step 1 — what happens, which table/field is touched]
2. [Step 2 — ...]
3. [...]

## Data touched
| Table | How | Notes |
|---|---|---|
| [Table name] | Read / Write / Lock | [Why] |

## Edge cases and guards
- [Condition] → [what happens and why]

## Design rationale / non-obvious behavior
[Why this approach was chosen, any constraints that shaped it, anything that looks wrong at
first glance but is intentional.]
```

**architecture-overview.md template**

```markdown
# Architecture Overview

[One paragraph: what this app does, at a systems level.]

## Module map
| Module/Folder | Responsibility | Depends on |
|---|---|---|
| [Folder name] | [What it owns] | [Other modules] |

## Data flow
[Short description or ordered list of how data/control flows through the major subsystems for
the app's primary use case(s).]

## See also
- [Link to each subsystem page under internals/]
```

**data-model.md template**

```markdown
# Data Model

## [Table name]
[Why this table exists, its role, and non-obvious modeling decisions.]

**Key structure**: [primary key, notable secondary keys and why they exist]

**Relations**: [notable TableRelations and what they enforce]
```

**integration-events.md template**

```markdown
# Integration Events

## [EventName]
- **Published by**: `Codeunit "X".ProcedureName()`
- **Fires**: [before/after what]
- **Purpose**: [why a subscriber would want this hook]
- **Internal subscribers**: [any subscribers within this app itself, and why they subscribe]
```

**extension-points.md template**

```markdown
# Extension Points

## [Interface or facade name]
[What it abstracts, how to implement/extend it, existing implementations in this app.]
```

**constraints.md template**

```markdown
# Constraints and Known Behavior

## [Constraint or workaround title]
[What it is, why it exists, what NOT to do without understanding this first.]
```

### Step 4 — Self-review checklist before building

Before running `docfx build`, verify:

- [ ] Every significant algorithm/business-logic subsystem has a page under `internals/`
- [ ] Every page explains *how* (step-by-step) and *why* (rationale), not just *what* (name restatement)
- [ ] AL object/procedure/table names are used explicitly — this is a developer audience, unlike the functional site
- [ ] `architecture-overview.md` links to every subsystem page
- [ ] `data-model.md` covers every table with non-obvious modeling decisions
- [ ] `integration-events.md` exists if the app publishes any integration events; omitted otherwise
- [ ] `extension-points.md` exists if the app has interfaces/facades meant for extension; omitted otherwise
- [ ] `constraints.md` captures anything that would surprise a future maintainer
- [ ] No page is empty or a placeholder

---

## Phase 2 — Scaffold and build

### Folder skeleton

Unlike `skill-aldoc`, there is no `aldoc init` to scaffold this folder — create it directly if
it doesn't already exist. **Check first** — if `docs\developer\en-US\` already exists (e.g. from
a prior run of this skill, or because the app was previously AppSource and is now PTE), reuse it
and only add/update the `internals\` pages; do not overwrite `docfx.json`/`toc.yml`/`index.md`/
`template\` unless they're missing.

```powershell
$docs = "C:\<repo>\docs\developer\en-US"
New-Item -ItemType Directory -Force "$docs\internals"
New-Item -ItemType Directory -Force "$docs\template\ContentTemplate\public"
```

`docfx.json` (create if absent — note the `template` path is **local**, not `../`, since this
file lives directly inside `docs\developer\en-US\`, matching what `aldoc init` would have
produced structurally for the same folder):

```json
{
    "build": {
        "content": [
            {
                "files": [
                    "*.md",
                    "internals/*.md",
                    "toc.yml"
                ]
            }
        ],
        "resource": [
            {
                "files": [
                    "template/ContentTemplate/public/**"
                ]
            }
        ],
        "dest": "_site",
        "globalMetadata": {
            "_appName": "[App Name]",
            "_appTitle": "[App Name] — Developer Reference",
            "_appFooter": "Made with <a href=\"https://dotnet.github.io/docfx\">DocFx</a>",
            "_appLogoPath": "template/ContentTemplate/public/[app-icon].png",
            "_enableSearch": true,
            "_disableTocFilter": false,
            "_disableToc": false,
            "_noindex": false,
            "_disableNextArticle": true
        },
        "template": [
            "default",
            "modern",
            "template/ContentTemplate"
        ],
        "markdownEngineName": "markdig",
        "disableGitFeatures": true
    }
}
```

`toc.yml` (create if absent — regenerate the `items:` list to match whichever `internals/*.md`
pages actually exist for this app):

```yaml
- name: Overview
  href: index.md
- name: Architecture Overview
  href: internals/architecture-overview.md
- name: Data Model
  href: internals/data-model.md
- name: Internals
  items:
    - name: [Subsystem 1 name]
      href: internals/[subsystem-1].md
    - name: [Subsystem 2 name]
      href: internals/[subsystem-2].md
- name: Integration Events
  href: internals/integration-events.md
- name: Extension Points
  href: internals/extension-points.md
- name: Constraints
  href: internals/constraints.md
```

Omit any `toc.yml` entry whose page doesn't exist for this app.

`index.md` (create if absent):

```markdown
# [App Name] — Developer Reference

[App Name] is a Microsoft Dynamics 365 Business Central per-tenant extension by [Publisher]
that [short description].

This site documents the app's internal architecture and business logic for developers extending
or maintaining it — not a public API reference (this app has no AppSource-facing surface).

## Extension Info
| Property | Value |
|---|---|
| Publisher | [Publisher] |
| BC Application Version | [version] |
| Object ID Range | [from] – [to] |

## Start here
- [Architecture Overview](internals/architecture-overview.md)
- [Data Model](internals/data-model.md)
```

### Build

```powershell
docfx build "$docs\docfx.json"
docfx serve "$docs\_site" -p 9091
```

Use a distinct port from `skill-aldoc`'s default (9090) and `skill-functional-docfx`'s defaults
(8081/8082) if previewing multiple sites simultaneously.

---

## Phase 3 — Brand customization

### Find and copy the app icon

```
<repo>\app\Source\Media\     ← .png or .svg app icon
```

If not found, **ask the user** before proceeding.

```powershell
Copy-Item "C:\<repo>\app\Source\Media\<app-icon>.png" `
          "C:\<repo>\docs\developer\en-US\template\ContentTemplate\public\<app-icon>.png"
```

### Copy `main.css`

The brand CSS is bundled with this skill at `references/main.css` — the same starting theme used
by `skill-aldoc` and `skill-functional-docfx`. Adapt the colour variables in `:root` and
`[data-bs-theme="dark"]` for the target extension's palette.

```powershell
Copy-Item "<skill-references>\main.css" `
          "C:\<repo>\docs\developer\en-US\template\ContentTemplate\public\main.css"
```

> **Note**: if this app was ever AppSource and had `skill-aldoc` run against it, this folder and
> its `main.css` may already exist and be branded — reuse it rather than overwriting, unless the
> user asks for a rebrand.

---

## What gets overwritten

| Path | Overwritten by this skill? | Safe to edit? |
|---|---|---|
| `internals\*.md` | Yes — every content pass, only for subsystems touched | Yes (hand-authored, never auto-generated) |
| `_site\**` | Yes — every `docfx build` | No |
| `docfx.json` | Only if absent | Yes |
| `toc.yml` | Only if absent (or a new page's entry is appended) | Yes |
| `index.md` | Only if absent | Yes |
| `template\**` | Only if absent | Yes |

---

## Phase 4 — Agent-assisted full documentation sweep

When the codebase has many files (>50), use AI agents to produce the subsystem inventory and
write all pages, following the same 1-agent-per-folder-group approach as `skill-aldoc`'s sweep —
see `references/agent-sweep-guide.md` for the full grouping rules and workflow-script template,
adapted here to produce technical subsystem summaries instead of auditing XML doc coverage.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `docfx serve` shows file browser | `_site` path not specified | `docfx serve "...\_site" -p 9091` |
| Port already in use | Another docfx preview running | Use a different `-p` port |
| Logo not showing | Icon not in `template\ContentTemplate\public\` or wrong filename in `docfx.json` | Verify `_appLogoPath` matches the actual filename |
| CSS not applied | `main.css` missing, or `template` array in `docfx.json` doesn't point locally | Since this file lives inside `docs\developer\en-US\`, the template path is `template/ContentTemplate` (no `../`) |
| Page missing from nav | `.md` file exists under `internals\` but not in `toc.yml` | Add entry to `toc.yml` |
| Build error on missing file | `toc.yml` references a page that doesn't exist yet | Create the file or remove the `toc.yml` entry |
| Both this skill and `skill-aldoc` seem to apply | App type is ambiguous or was misdetected | Re-check `app.json` `idRanges` — AppSource/Global uses `skill-aldoc`, PTE uses this skill. Never run both against the same app. |
