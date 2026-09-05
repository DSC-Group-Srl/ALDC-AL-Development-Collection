---
name: skill-aldoc
description: >
  Complete workflow for generating and customising technical developer documentation from
  AL (Business Central) source code using aldoc and docfx. Use this skill whenever the
  user mentions: generating AL docs, aldoc, docfx, documenting a BC extension, XML
  comments in AL, summary XML comments, ToolTip/Description for doc purposes, setting up or
  rebuilding a developer reference site, or customising the docfx brand theme. Also
  trigger when the user asks what to document in an AL object, how to add summaries to
  procedures, enums, or fields, or why summaries are not appearing in the generated site.
---

# AL Documentation — aldoc + docfx

> Full reference: `references/al-doc-guide.md`
> Brand CSS template: `references/main.css`

---

## Pipeline overview

```
.al sources → [Ctrl+Shift+B] → .app
                                   ↓
                              aldoc build  →  reference/*.md + toc.yml
                                   ↓
                              docfx build  →  _site/ (HTML)
```

aldoc reads XML doc comments from the **compiled `.app` metadata**, not from `.al` sources directly.
Every comment change requires: recompile → `aldoc build` → `docfx build`.

---

## Quick-reference: what to document and how

| AL element | Method | aldoc reads it? |
|---|---|---|
| Object (`table`, `codeunit`, `page`, `enum`, `report`, `permissionset`) | `summary XML comments` before the object declaration | Yes |
| Public procedure (no `local`) | `summary XML comments` + `<param>` + `<returns>` + `<remarks>` before `procedure` | Yes |
| Integration Event (`[IntegrationEvent] local procedure`) | `summary XML comments` + `<param>` + `<remarks>` before `[IntegrationEvent]` | Yes |
| Table field | `ToolTip = '...';` + `Description = '...';` (same text) inside `field()` block | Yes |
| Enum value | `summary XML comments` on the line **before** `value(N; X) { Caption = '...'; }` — value block on one line | Yes |
| `local procedure` | Do not document | — |
| Trigger (`OnRun`, `OnAfterGetRecord`, etc.) | Do not document | — |
| `[EventSubscriber] local procedure` | Do not document | — |

**Common mistake**: placing `summary XML comments` inside a `field()` body. The AL compiler accepts it silently, but aldoc ignores it completely. Always use `ToolTip` + `Description` for fields.

---

## Phase 1 — Documentation audit and writing (ALWAYS do this before building)

Before running any build commands, the AL source must be fully documented. This is not optional — the reference site is only as good as the XML comments in the code.

### Step 1 — Choose your approach based on codebase size

**First action**: count the `.al` files in the source folder.

```powershell
(Get-ChildItem "app\Source" -Recurse -Filter "*.al").Count
```

| File count | Approach |
|---|---|
| **≤ 50 files** | Work manually — read each file inline, flag issues, write missing summaries directly (continue with Steps 2–3 below) |
| **> 50 files** | Use AI agents — read `references/agent-sweep-guide.md` and follow it. It covers both the audit (scanning for missing/shallow/misplaced summaries) and the writing (adding what is missing), using 1 agent per folder group to stay within token limits. Return here only after the sweep is complete and the user has recompiled. |

### Step 2 — Scan existing comments *(manual path only)*

Read all `.al` files in the extension source. For each public-facing surface, record:

- Does it already have a `/// <summary>`? Is it present but shallow ("Gets the value.", one-liner with no business context)?
- For table fields: do both `ToolTip` and `Description` exist with identical, meaningful text?
- For enum values: is `/// <summary>` on the line immediately before the single-line `value(...)` block?

Build a mental (or explicit) inventory grouped by object. Flag:
- **Missing** — no documentation at all
- **Shallow** — exists but too brief to be useful to a developer (no business context, no mention of when/why to call it, no edge cases)
- **Misplaced** — `/// <summary>` inside a `field()` body (silently ignored by aldoc)

### Step 3 — Write or rewrite every public surface *(manual path only)*

Work through every AL file. Apply the rules below without exception.

**Quality bar — every summary must answer:**
1. What does this object/procedure/field/value *do or represent*?
2. *Why* does it exist — what business process or rule does it serve?
3. Any non-obvious behaviour, constraints, or side effects?

A summary that only restates the name ("Posts the document") is unacceptable. The minimum bar is something a developer unfamiliar with the extension can act on immediately.

**Objects (table, codeunit, page, enum, report, permissionset)**
```al
/// <summary>
/// [What the object is and its role in the extension.]
/// [Which business process it belongs to.]
/// [Any architectural notes — e.g. "central configuration table referenced by all document headers".]
/// </summary>
```

**Public procedures (no `local` keyword)**
```al
/// <summary>
/// [What the procedure does. Business context, not just technical description.]
/// [Entry point / caller context if relevant.]
/// </summary>
/// <param name="ParamName">[What this parameter is, direction (in/out), any constraints.]</param>
/// <returns>[What is returned and what it means. Omit if void.]</returns>
/// <remarks>
/// [Edge cases, conditions that skip logic, integration events raised, flags that alter behaviour.]
/// [Cross-references to related procedures or tables if relevant.]
/// </remarks>
```
Every `<param>` must be documented. `<returns>` only if non-void. `<remarks>` whenever there are integration events, conditional branches, or non-obvious side effects.

**Integration Events**
```al
/// <summary>
/// [Event name and when it fires — before/after what operation.]
/// [How subscribers should use it.]
/// </summary>
/// <param name="IsHandled">[If present: set to true to skip the default implementation.]</param>
/// <param name="...">...</param>
/// <remarks>
/// [What happens when IsHandled = true, if applicable.]
/// [Which procedure raises this event.]
/// </remarks>
```

**Table fields**
```al
field(N; "FieldName"; DataType)
{
    Caption = '...';
    ToolTip = '[What this field stores. Business meaning. Where it is used downstream.]';
    Description = '[Identical to ToolTip.]';
    DataClassification = ...;
}
```
`ToolTip` and `Description` must always contain the same text. Single quotes inside the text must be escaped as `''`.

**Enum values**
```al
/// <summary>[What this value means in business terms. When it is selected/assigned.]</summary>
value(N; ValueName) { Caption = '...'; }
```
The `/// <summary>` line must be immediately above the `value(...)` line. The `value(...)` block must be on a single line.

### Step 4 — Self-review checklist before building

Before running `aldoc build`, verify:

- [ ] Every object has a `/// <summary>` that provides business context, not just a name restatement
- [ ] Every public procedure has `/// <summary>`, all `<param>` tags filled, `<returns>` if non-void, `<remarks>` if there are events or non-obvious behaviour
- [ ] Every integration event has `/// <summary>` + all `<param>` tags + `<remarks>` explaining the IsHandled pattern if present
- [ ] Every table field has both `ToolTip` and `Description` with identical, meaningful text — no field left with the default empty string or a one-word placeholder
- [ ] Every enum value has `/// <summary>` on the line immediately before a single-line `value(...)` block
- [ ] No `/// <summary>` appears *inside* a `field()` body (the AL compiler will not warn, but aldoc ignores it)
- [ ] No `local procedure`, trigger, or event subscriber has XML doc comments

Only after this checklist passes: recompile (`Ctrl+Shift+B`) and proceed to Phase 2.

---

## Phase 2 — Build

### Locate aldoc

aldoc ships as a dotnet global tool via the `microsoft.dynamics.businesscentral.development.tools` NuGet package.
It is **not** guaranteed to be on `PATH` in PowerShell — always locate it explicitly first:

```bash
# Bash (Git Bash / WSL) — finds the exe under the dotnet tools store
find ~/.dotnet/tools/.store/microsoft.dynamics.businesscentral.development.tools -name "aldoc.exe" -path "*/net8.0/*" | head -1
```

```powershell
# PowerShell alternative
Get-ChildItem "$env:USERPROFILE\.dotnet\tools\.store\microsoft.dynamics.businesscentral.development.tools" `
  -Recurse -Filter "aldoc.exe" | Where-Object { $_.FullName -like "*net8.0*" } | Select-Object FullName
```

Use the returned path as `$aldoc` in all commands below.
If aldoc is not found there, check the VS Code extension (less reliable, may be outdated):
```powershell
Get-ChildItem "$env:USERPROFILE\.vscode\extensions\ms-dynamics-smb.al-*\bin\win32\aldoc.exe" | Select-Object FullName
```

### PowerShell session variables

Set once per session; all commands below reuse them.

```powershell
$aldoc = "<full path to aldoc.exe found above>"
$app   = "C:\<repo>\app\<Publisher>_<Name>_<version>.app"   # always the highest version
$docs  = "C:\<repo>\docs\developer\en-US"
```

Find latest `.app`:
```powershell
Get-ChildItem "C:\<repo>\app\*.app" | Sort-Object LastWriteTime -Descending | Select-Object Name, LastWriteTime
```

---

## Build commands

```powershell
# Full rebuild (after Ctrl+Shift+B in VS Code)
& $aldoc build --source $app --output $docs
docfx build "$docs\docfx.json"

# Preview — always pass explicit _site path; port 8080 may be reserved by OS, use 9090 if needed
docfx serve "$docs\_site" -p 9090
```

**First-time init only** (creates template/, docfx.json, index.md, toc.yml — overwrites customisations):
```powershell
& $aldoc init -o $docs -T $app
```

### Configure preview server in `.claude/launch.json`

To allow `preview_start` to serve the docfx site, create `.claude/launch.json` in the repo root:

```json
{
  "version": "0.0.1",
  "configurations": [
    {
      "name": "dyna-arx-docs",
      "runtimeExecutable": "docfx",
      "runtimeArgs": ["serve", "docs\\developer\\en-US\\_site", "-p", "9090"],
      "port": 9090
    }
  ]
}
```

Then use `preview_start` with `name: "dyna-arx-docs"` to serve the site without a Bash command.

---

## Brand customisation — required steps after `aldoc init`

### A — Find and copy the app icon

The icon must be in `template\ContentTemplate\public\` for docfx to pick it up.

**Always look here first:**
```
<repo>\app\Source\Media\     ← .png or .svg app icon
```

If no icon is found there, **ask the user where the icon file is** before proceeding.

Once located:
```powershell
New-Item -ItemType Directory -Force "C:\<repo>\docs\developer\en-US\template\ContentTemplate\public"
Copy-Item "C:\<repo>\app\Source\Media\<app-icon>.png" `
          "C:\<repo>\docs\developer\en-US\template\ContentTemplate\public\<app-icon>.png"
```

### B — Copy `main.css`

The brand CSS is in `references/main.css` (bundled with this skill). It contains the DynaARX gradient theme as a starting point — adapt the colour variables in the `:root` block and the `[data-bs-theme="dark"]` block for the target extension's palette.

```powershell
Copy-Item "<skill-references>\main.css" `
          "C:\<repo>\docs\developer\en-US\template\ContentTemplate\public\main.css"
```

Key variables to customise at the top of the file:
```css
:root {
  --brand-primary:   #c0175c;   /* main accent */
  --brand-secondary: #6b1a9a;   /* secondary accent */
  --brand-blue:      #1a3a8f;   /* link / heading colour */
  --brand-gold:      #f0a800;   /* border / highlight */
  --brand-gradient:  linear-gradient(135deg, #c0175c 0%, #6b1a9a 45%, #1a3a8f 100%);
}
```

No changes to `docfx.json` are needed — docfx picks up `main.css` automatically from the `public/` folder.

### C — Update `docfx.json`

```json
"globalMetadata": {
  "_appName": "<App Name>",
  "_appTitle": "<App Name> — Developer Reference",
  "_appFooter": "Made with <a href=\"https://go.microsoft.com/fwlink/?linkid=2247728\">ALDoc</a> and <a href=\"https://dotnet.github.io/docfx\">DocFx</a>",
  "_appLogoPath": "public/<app-icon>.png"
}
```

### D — Write `index.md`

Minimal template:
```markdown
# <App Name> — Developer Reference

<App Name> is a Microsoft Dynamics 365 Business Central extension by <Publisher>
that provides <short description>.

## Features
- Feature 1
- Feature 2

## Extension Info
| Property | Value |
|---|---|
| Publisher | <Publisher> |
| BC Application Version | <version> |
| Object ID Range | <from> – <to> |
```

---

## What gets overwritten

| Path | Overwritten by aldoc? | Overwritten by docfx? | Safe to edit? |
|---|---|---|---|
| `reference\**` | Yes — every build | No | No |
| `_site\**` | No | Yes — every build | No |
| `docfx.json` | No | No | Yes |
| `template\**` | Only on `aldoc init` | No | Yes |
| `index.md` | Only on `aldoc init` | No | Yes |
| `toc.yml` | Only on `aldoc init` | No | Yes |

---

## Phase 3 — Agent-assisted full documentation sweep

When the codebase has many undocumented files (>50), use AI agents to write all missing summaries automatically, then have the user recompile once at the end.

### Token-efficient approach: 1 agent per namespace folder

**Rule: never spawn more than 1 agent per namespace/folder group.** Each agent iterates all files in its group sequentially. This replaces the naïve "1 agent per file" approach, which hits API rate limits on codebases with 100+ files.

### How to group files

Before writing the workflow, explore the source tree to understand the extension's actual structure:

```powershell
# List all first- and second-level folders under Source/
Get-ChildItem "app\Source" -Directory -Recurse -Depth 1 | Select-Object FullName
```

Then apply these grouping rules:

1. **One agent per top-level feature folder** (e.g. `Sales`, `Purchases`, `Configuration`, `Connector`, `Security`, `Log`) — this is the default and sufficient for most extensions.
2. **Split large folders** (>25 files) into A/B halves — e.g. `Configuration/Page` → `Config-Pages-A` + `Config-Pages-B`. Split by object type or alphabetically.
3. **Merge tiny folders** (<5 files each) into one group — e.g. `Log` + `Utility` → one agent.
4. **Deep interface hierarchies** (e.g. `Connector/Interface/<IName>/`) — group each interface subfamily as its own agent if it has >10 files, otherwise merge with its parent folder.
5. **Aim for 15–25 files per group** and **15–25 total agents**. Fewer agents = lower token cost; more agents = faster wall-clock time. Default to fewer unless the user asks for speed.

**Examples of how the same pattern adapts to different extensions:**

| Extension type | Typical top-level folders → agent groups |
|---|---|
| Sales/Purchase integration | `Sales`, `Purchases`, `Configuration`, `Connector`, `Security`, `Log/Utility` |
| Warehouse/Logistics | `Warehouse`, `Inventory`, `Shipping`, `Setup`, `Reports`, `Security` |
| HR/Payroll | `Employee`, `Payroll`, `Absences`, `Setup`, `Integration`, `Security` |
| Simple utility extension (<50 files) | One or two groups covering all files |

Adapt to whatever folder structure the specific extension actually uses — never assume a fixed layout.

### Workflow script template

```javascript
export const meta = {
  name: 'doc-sweep',
  description: 'Add missing XML doc summaries to all AL source files, 1 agent per folder group',
  phases: [{ title: 'Sweep groups', detail: '1 agent per namespace folder' }],
}

const SWEEP_PROMPT = (files) => `You are adding XML doc comments to AL (Business Central) source files.

Process each file IN ORDER:
1. Read the full file
2. Identify ALL missing /// <summary> documentation
3. Use Edit to write missing summaries (skip if already present)

FILES:
${files.map((f, i) => \`\${i + 1}. \${f}\`).join('\\n')}

WHAT TO DOCUMENT (add if missing):
- Object-level: every table/codeunit/page/pageext/tableext/enum/enumext/interface/permissionset
- Public procedures (not local): /// <summary> + <param> per param + <returns> if non-void + <remarks> if events/non-obvious
- Integration events ([IntegrationEvent] local procedure): /// <summary> + <param> + <remarks>
- Enum values: /// <summary>one line</summary> immediately before each single-line value(N; Name) { ... }

DO NOT document: local procedures, triggers, event subscribers, anything already preceded by /// <summary>

Quality bar: every summary must explain WHAT it does, WHY it exists (business context), and any non-obvious behaviour.

Report: "Completed: X files processed, Y summaries added total"`

const GROUPS = [
  { label: 'Config-Enum-ControlAddin', files: [ /* ... */ ] },
  // ... one entry per folder group
]

phase('Sweep groups')
await parallel(GROUPS.map(group => () =>
  agent(SWEEP_PROMPT(group.files), { label: group.label, phase: 'Sweep groups' })
))
return { groupsProcessed: GROUPS.length }
```

### Two-pass sweep for large codebases

For codebases with 200+ files, split the sweep into two passes to avoid overwhelming agents:

**Pass 1 — Object-level only** (fast, ~10 agents):
Each agent adds `/// <summary>` only at object declaration level (first lines of file). This is the most impactful change for the docfx site's namespace pages.

**Pass 2 — Procedures, events, enum values** (heavier, ~20 agents):
Each agent opens every file and adds summaries to all undocumented public procedures, integration events, and enum values. Run after Pass 1 is committed and user has verified Pass 1 output.

After both passes complete, tell the user: **"All summaries written. Please recompile (`Ctrl+Shift+B`), then let me know to run `aldoc build` + `docfx build`."**

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Summaries missing from site after editing `.al` | `.app` not recompiled after changes | `Ctrl+Shift+B` → `aldoc build` → `docfx build` |
| `summary XML comments` in `field()` ignored | aldoc ignores XML doc inside field blocks | Use `ToolTip` + `Description` properties |
| `aldoc` not found in PowerShell | Not on `PATH` | Find full path via `find ~/.dotnet/tools/.store` (see Phase 2) |
| `aldoc build` unknown verb `generate` | Wrong aldoc version syntax | Use `aldoc build --source $app --output $docs` (no `generate` verb) |
| `aldoc build` can't find `.app` | Wrong path / stale version | `Get-ChildItem "app\*.app" \| Sort-Object LastWriteTime -Descending` |
| `docfx serve` shows file browser | `_site` path not specified | `docfx serve "$docs\_site" -p 9090` |
| Port 8080 already in use | OS reserved port | Use port 9090 instead |
| Object's summary missing despite `/// <summary>` in source | `ObsoleteState = Pending` | Expected — aldoc intentionally skips obsolete-pending objects |
| Summaries skipped inside `#if not CLEAN27` block | Object is `ObsoletePending` and inside preprocessor block | Expected — nothing to fix; aldoc treats it as obsolete |
| Missing symbols on `aldoc build` | BC version mismatch in `.alpackages` | Run `AL: Download Symbols` in VS Code |

---

## Full reference

For complete code examples (table, tableextension, codeunit, enum, integration events), see:
`references/al-doc-guide.md`
