# Agent-assisted documentation sweep (>50 files)

This guide replaces the manual Phase 1 workflow when the source folder contains more than 50
`.al` files. Agents handle both the **analysis** (understanding each subsystem's algorithm) and
the **writing** (producing the technical summary page). There is no recompile step required
afterward — unlike `skill-aldoc`, this skill never reads compiled `.app` metadata.

---

## Overview

Each agent is assigned a folder group. It iterates every file in its group, builds a mental model
of what that module actually does, and produces one or more `internals/*.md` pages summarizing
the algorithms and functionality found there — not an audit of comment coverage, but a technical
explanation of the code's behavior.

---

## Step 1 — Explore the source tree

List the actual folder structure before defining groups:

```powershell
Get-ChildItem "app\Source" -Directory -Recurse -Depth 2 | Select-Object FullName
(Get-ChildItem "app\Source" -Recurse -Filter "*.al").Count
```

Then apply these grouping rules to what you find:

| Rule | When to apply |
|---|---|
| 1 agent per top-level feature folder | Default — enough for most extensions |
| Split folder into A/B halves | Folder has >25 files — split by object type or alphabetically |
| Merge multiple small folders | Each folder has <5 files — combine into one agent group |
| Subfolder per interface family | Interface hierarchy has >10 files per subfamily |

**Target: 15–25 files per group, 15–25 groups total.**

Never hardcode folder names — derive them from the actual source tree, exactly as with
`skill-aldoc`'s sweep.

---

## Step 2 — Choose single-pass or two-pass

| Codebase size | Approach |
|---|---|
| 50–150 files | **Single pass** — analysis + write in one sweep |
| 150+ files | **Two passes** — architecture/module map first (fast, high site impact), then per-subsystem algorithm pages |

**Pass 1 — Architecture-level** (fast): each agent reports its module's responsibility, entry
points, and dependencies. Consolidate these into `architecture-overview.md` and `data-model.md`.

**Pass 2 — Subsystem algorithm pages** (heavier): after Pass 1 is verified, each agent writes the
detailed step-by-step subsystem pages (`internals/*.md`) for its group's significant algorithms.

---

## Step 3 — Workflow script template

```javascript
export const meta = {
  name: 'developer-doc-sweep',
  description: 'Produce technical internals documentation for AL source files, 1 agent per folder group',
  phases: [
    { title: 'Analyze & Write', detail: '1 agent per feature folder — reads, understands, writes subsystem pages' },
  ],
}

const SWEEP_PROMPT = (files, group) => `You are producing technical developer documentation for
a Business Central PTE extension's internals. This is NOT a public API reference — it explains
HOW the code works, for a developer or AI agent who needs to safely extend or debug it.

Process the files in this group as a single module:

## Step A — Understand
Read every file listed below. Build a mental model of:
- What this module is responsible for
- Its entry points (public procedures, event subscribers) and what triggers them
- The core algorithm(s) — loops, calculations, state transitions, posting sequences
- Which tables/fields it reads, writes, or locks, and in what order
- Edge cases, guards, and validation — and why they exist
- What it depends on / what depends on it

## Step B — Classify
For any existing page under docs/developer/en-US/internals/ covering this module, classify it:
- MISSING: no page exists for this subsystem yet
- SHALLOW: a page exists but doesn't explain the actual algorithm (just restates names)
- OK: already documented with real technical content — skip it

## Step C — Write
For every MISSING or SHALLOW subsystem, write one page under
docs/developer/en-US/internals/[subsystem-name].md using this structure:

# [Subsystem name]
[One paragraph: responsibility and where it sits in the app.]
## Entry points
[Procedure/event that kicks this off]
## How it works
[Numbered step-by-step technical walkthrough, using actual AL object/procedure/table names]
## Data touched
[Table | Read/Write/Lock | Why]
## Edge cases and guards
[Condition -> what happens and why]
## Design rationale / non-obvious behavior
[Why built this way; anything that looks wrong but is intentional]

Quality bar: every page must explain WHAT it does (step by step), WHY it's built that way, and
what would surprise a developer extending it later. A page that only restates object names is
unacceptable.

Also report anything relevant to the shared docs/developer/en-US/architecture-overview.md
(module responsibility, dependencies) and docs/developer/en-US/data-model.md (tables owned by
this group and why they're modeled that way) — the calling workflow consolidates these across
all groups after every agent completes.

FILES TO PROCESS:
${files.map((f, i) => \`\${i + 1}. \${f}\`).join('\\n')}

End your response with a summary line:
"Completed: X files analyzed | Y subsystem pages written | Z architecture/data-model notes reported"
\`

const GROUPS = [
  { label: 'FeatureA', files: [ 'C:\\repo\\app\\Source\\FeatureA\\File1.al', /* ... */ ] },
  { label: 'FeatureB', files: [ /* ... */ ] },
  // one entry per folder group — derived from the actual source tree (Step 1)
]

phase('Analyze & Write')
const results = await parallel(GROUPS.map(group => () =>
  agent(SWEEP_PROMPT(group.files, group.label), { label: group.label, phase: 'Analyze & Write' })
))
return { groupsProcessed: GROUPS.length, results }
```

---

## Step 4 — After the sweep completes

1. Consolidate every group's architecture/data-model notes into `architecture-overview.md` and
   `data-model.md` — these are cross-cutting pages, not per-group output, so they need a manual
   merge pass after the parallel sweep returns.
2. Update `toc.yml` to include every new page under `internals/`.
3. Run `docfx build` — no recompile needed first, since this skill never reads the compiled
   `.app`.

Review the per-agent summaries to confirm every significant subsystem got a page, then tell the
user documentation is ready to build/preview.
