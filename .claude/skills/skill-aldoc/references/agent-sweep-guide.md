# Agent-assisted documentation sweep (>50 files)

This guide replaces the manual Phase 1 workflow when the source folder contains more than 50 `.al` files. Agents handle both the **audit** (reading files, detecting issues) and the **writing** (adding missing summaries). The user recompiles once at the end.

---

## Overview

Each agent is assigned a folder group. It iterates every file in its group sequentially and does three things in one pass:

1. **Read** — scan for missing, shallow, or misplaced documentation
2. **Report** — produce a concise per-file audit list
3. **Write** — apply all fixes inline using Edit

This single-pass approach keeps token usage low while giving a complete picture of what was found and changed.

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

Examples of how the pattern adapts to different extension types:

| Extension type | Typical groups |
|---|---|
| Sales/Purchase integration | `Sales`, `Purchases`, `Configuration`, `Connector`, `Security`, `Log+Utility` |
| Warehouse/Logistics | `Warehouse`, `Inventory`, `Shipping`, `Setup`, `Reports`, `Security` |
| HR/Payroll | `Employee`, `Payroll`, `Absences`, `Setup`, `Integration`, `Security` |
| Small utility (<50 files) | Use manual Phase 1 instead — agents add overhead |

Never hardcode folder names — derive them from the actual source tree.

---

## Step 2 — Choose single-pass or two-pass

| Codebase size | Approach |
|---|---|
| 50–150 files | **Single pass** — audit + write in one sweep |
| 150+ files | **Two passes** — objects only first (fast, high site impact), then procedures + events + enum values |

**Pass 1 — Object-level** (fast): each agent audits and fixes `/// <summary>` at object declaration level only. Covers all namespace pages in the docfx site.

**Pass 2 — Procedures, events, enum values** (heavier): after Pass 1 is verified, each agent audits and fixes all public procedures, integration events, and enum values.

---

## Step 3 — Workflow script template

```javascript
export const meta = {
  name: 'doc-sweep',
  description: 'Audit and fix XML doc summaries in all AL source files, 1 agent per folder group',
  phases: [
    { title: 'Audit & Fix', detail: '1 agent per namespace folder — reads, diagnoses, writes' },
  ],
}

const SWEEP_PROMPT = (files) => `You are auditing and documenting AL (Business Central) source files.

For each file listed below, work IN ORDER:

## Step A — Audit
Read the full file. For every public-facing surface identify:
- MISSING: no /// <summary> present
- SHALLOW: /// <summary> exists but only restates the name with no business context
- MISPLACED: /// <summary> appears inside a field() body (aldoc ignores it — must use ToolTip + Description instead)
- OK: already documented with meaningful content

## Step B — Report (one line per issue)
Print a compact audit list:
  [filename] > ObjectName.ProcedureName — MISSING / SHALLOW / MISPLACED

## Step C — Write
For every MISSING or SHALLOW item: use Edit to add or rewrite the summary in the source file.
For every MISPLACED item: remove the misplaced /// <summary> and ensure ToolTip + Description are set.
Skip OK items entirely.

FILES TO PROCESS:
${files.map((f, i) => \`\${i + 1}. \${f}\`).join('\\n')}

WHAT TO DOCUMENT:
- Objects (table/codeunit/page/pageext/tableext/enum/enumext/interface/permissionset): /// <summary> block before the object declaration
- Public procedures (no local keyword): /// <summary> + <param> per param + <returns> if non-void + <remarks> if integration events or non-obvious behaviour
- Integration events ([IntegrationEvent] local procedure): /// <summary> + <param> + <remarks>
- Enum values: /// <summary>one line</summary> on the line immediately before value(N; Name) { Caption = '...'; }
- Table fields: ToolTip = '...'; and Description = '...'; with identical meaningful text inside field() body

DO NOT document: local procedures, triggers, event subscribers.

Quality bar for every summary:
1. What does it do / represent?
2. Why does it exist — what business process does it serve?
3. Any non-obvious behaviour, constraints, or side effects?

A summary that only restates the name is unacceptable.

End your response with a summary line:
"Completed: X files | Y missing fixed | Z shallow rewritten | W misplaced corrected"
\`

const GROUPS = [
  { label: 'FeatureA', files: [ 'C:\\repo\\app\\Source\\FeatureA\\File1.al', /* ... */ ] },
  { label: 'FeatureB', files: [ /* ... */ ] },
  // one entry per folder group — derived from the actual source tree (Step 1)
]

phase('Audit & Fix')
await parallel(GROUPS.map(group => () =>
  agent(SWEEP_PROMPT(group.files), { label: group.label, phase: 'Audit & Fix' })
))
return { groupsProcessed: GROUPS.length }
```

---

## Step 4 — After the sweep completes

Review the per-agent audit summaries to confirm all issues were resolved. Then tell the user:

> "Audit and fixes complete. Please recompile in VS Code (`Ctrl+Shift+B`), then let me know and I'll run `aldoc build` + `docfx build` to regenerate the site."

Do not run `aldoc build` until the user confirms the new `.app` is ready — aldoc reads from the compiled binary, not the `.al` source files.
