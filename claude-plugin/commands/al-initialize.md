---
description: >
  Initialize AL development environment and workspace for Business Central.
  Use when setting up a new project, initializing the workspace, or configuring
  the development environment.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch
argument-hint: "<ProjectName> <EnvironmentName>"
---

# AL Environment Initialization

**Inputs** — parse from `$ARGUMENTS`: `{ProjectName}`, `{EnvironmentName}`. Ask the user for any that are missing before starting; never leave a `{placeholder}` unresolved in an output file.

Your goal is to initialize the AL development environment and workspace for `{ProjectName}`.

This workflow covers environment setup, AL workspace configuration, and **ALDC rules injection** into your project.

## Phase 0: ALDC Rules Injection (Plugin Mode)

When ALDC is installed as a Claude Code plugin, path-scoped rules must be copied to the project's `.claude/rules/` directory. This phase handles that automatically.

> A `SessionStart` hook (`tools/rules/precondition_hook.sh`) checks for `.claude/rules/rules-floor-cheatsheet.md` on every session and nudges agents to offer this command when it's missing (or when the pre-8.0 layout is found). Running it again is safe: it overwrites the same files and migrates the old layout.

### Rules Installation — two tiers

Everything under `.claude/rules/` loads into **every** session and subagent that touches AL, so
only the condensed floor lives there; the full domain files are on-demand reference.

```bash
mkdir -p .claude/rules .claude/aldc-rules
R="${CLAUDE_PLUGIN_ROOT}/rules-templates"
# Tier 1 — auto-loaded (path-scoped to **/*.al and **/app.json), ~17 KB total
cp "$R/rules-floor-cheatsheet.md" "$R/compiler-authority-protocol.md"    "$R/tool-failure-protocol.md" "$R/agent-contract.md" .claude/rules/
# Tier 2 — on-demand reference, read by an agent only when a cheat-sheet line isn't enough
cp "$R"/al-*.md .claude/aldc-rules/
# Migrate a pre-8.0 install: the domain files used to sit in .claude/rules/ and auto-load (~90 KB)
for f in "$R"/al-*.md; do rm -f ".claude/rules/$(basename "$f")"; done
# Cross-feature decision log (replaces appending decisions to CLAUDE.md)
mkdir -p app/requirements && [ -f app/requirements/memory.md ] || echo "# Decisions" > app/requirements/memory.md
```

| Tier | File | Purpose |
|------|------|---------|
| auto | `rules-floor-cheatsheet.md` | One line per hard rule across the 7 domain files |
| auto | `compiler-authority-protocol.md` | All analyzers on every compile, zero new warnings, compiler is ground truth |
| auto | `tool-failure-protocol.md` | Try once, one alternate, then TOOL_BLOCKED vs CODE_ISSUE |
| auto | `agent-contract.md` | BCQuality, evidence markers, al-file-reader, test lane |
| on demand | `al-guidelines.md`, `al-code-style.md`, `al-naming-conventions.md`, `al-performance.md`, `al-error-handling.md`, `al-events.md`, `al-testing.md` | Rationale and worked examples behind each floor line |
| on demand | `al-agent-toolkit.md` | Agent SDK patterns (al-agent-builder reads it) |

Tests run on the environment the user picks from `.vscode/launch.json` (see
`bc-dev:skill-test-lane`). Run `python "${CLAUDE_PLUGIN_ROOT}/tools/testlane/lane.py" configs <test
project>`: if it reports `devEnv.suggest`, tell the user they can get a ready test container from
the repo's own `.AL-Go/localDevEnv.ps1` in one step (`bc-dev:skill-al-go-devenv`) — offer it,
don't start it unasked.

### CLAUDE.md Generation

Generate a project-level `CLAUDE.md` that references ALDC:

```markdown
# {ProjectName} — Claude Code Instructions

## Framework
This project uses **ALDC** (AL Development Collection) plugin for Claude Code.
All agents, skills and commands come from the `bc-dev` plugin.

## Quick Start
- `/bc-dev:al-spec-create` — Create specifications
- `/bc-dev:al-build` — Build extension
- `al-architect` — architecture (HIGH complexity)
- `al-developer` — direct implementation
- `al-conductor` — planned feature, parallel work packages

## Project-Specific Notes
[Add your project-specific instructions here]
```

**Human Review:** Confirm rules were copied correctly before proceeding to environment setup.

## Phase 1: Environment Setup

### Prerequisites

The SessionStart hooks already check and, where possible, install: the AL CLI (`al`), the
ALCops analyzers, Node/npx, Python and Git Bash. Nothing to do here unless a hook reported a
problem. VS Code with the AL extension remains the human's tool for debugging and publishing.

### VS Code Workspace Configuration

Create or update `.vscode/settings.json` in the workspace root:

```json
{
  // AL Language settings
  "al.enableCodeAnalysis": true,
  "al.codeAnalyzers": [
    "${CodeCop}",
    "${PerTenantExtensionCop}",
    "${UICop}",
    "${analyzerFolder}ALCops.ApplicationCop.dll",
    "${analyzerFolder}ALCops.DocumentationCop.dll",
    "${analyzerFolder}ALCops.FormattingCop.dll",
    "${analyzerFolder}ALCops.LinterCop.dll",
    "${analyzerFolder}ALCops.PlatformCop.dll",
    "${analyzerFolder}ALCops.Common.dll"
  ],

  // NAB AL Tools — use XLIFF target-state attributes instead of [NAB: *] tokens.
  // REQUIRED for the skill-translate MCP workflow; the nab-al-tools MCP server
  // reads this via the workspaceFilePath passed to `initialize`.
  "NAB.UseTargetStates": true,
  "NAB.ReplaceSelfClosingXlfTags": true,
  "NAB.DetectInvalidTargets": true
}
```

**Configuration Benefits:**
- Code analysis with CodeCop, PerTenantExtensionCop, UICop, and the ALCops suite (ApplicationCop, DocumentationCop, FormattingCop, LinterCop, PlatformCop — the successor to BusinessCentral.LinterCop, see https://alcops.dev/docs/lintercop-migration/). The `SessionStart` hook `tools/al-cli/ensure-alcops.sh` downloads the `ALCops.*.dll` files straight into the AL Language extension's analyzer folder (not just the VS Code extension, which only helps the editor) — so these `${analyzerFolder}` entries resolve for al-mcp and the AL LSP server too, not only when VS Code itself is open.

## Phase 2: Project Initialization

### Choose Project Type

**For New Projects:**
Scaffold the project structure directly with `Write` (`app.json`, folders, `.vscode/` configs — see the structure below), or have the human run VS Code `AL: Go!` to generate a starter project.

**For Existing Folders:**
Work in place — `Read` the existing `app.json` and lay out any missing folders with `Write`.

### Project Structure

Implement feature-based organization:

```
{ProjectName}/
├── .vscode/
│   ├── settings.json          # Workspace settings
│   └── launch.json            # Debug configurations
├── src/                       # feature-based, never by object type (rules floor)
│   └── <Feature>/<SubFeature>/<ObjectName>.<ObjectType>.al
├── test/                      # separate test project; mirrors src/ feature folders
│   └── <Feature>/<SubFeature>/<ObjectName>.Codeunit.al
├── app.json                   # Application manifest
├── .gitignore                 # Git ignore rules
└── README.md                  # Project documentation
```

**Multi-project workspace (app + test app / performance app):** when the requirement calls for a separate test app rather than an in-app `test/` folder, use sibling project folders instead — `app/`, `app-test/`, optionally `app-performance/` — each with its own `app.json` (the test/performance app declares the base app as a `dependencies` entry), plus a root `<name>.code-workspace` file listing each folder (generate it with `Bash: al workspace create <name>.code-workspace app app-test ...` if it doesn't exist). Load `skill-al-mcp-workspace` before building or troubleshooting this setup — it has the verified approach for keeping symbols in sync across projects, and the path/staleness gotchas to avoid.

### Download Symbols

Download required symbols directly via **al-mcp** `al_downloadsymbols` — `globalSourcesOnly=true` needs no auth and covers AppSource/Microsoft symbols; an environment-scoped download needs interactive browser auth, so confirm the target environment with the human first. Alternatively: VS Code `AL: Download Symbols`, or restore the symbol package cache in CI.

Verify all base application dependencies are available. For a multi-project workspace, each project (app, app-test, app-performance) needs its **own** `.alpackages` populated — downloading symbols for one project does not populate a sibling's cache.

### Create the Manifest

`app.json` **is** the manifest — write it directly with `Write` (id, name, publisher, version, idRanges, dependencies, platform/application).

**Human Review:** Validate manifest contents before proceeding.

## Phase 3: Launch Configuration

### 🔒 Human Gate: Authentication Configuration Review

**SECURITY CHECKPOINT - Configuration contains sensitive information**

Before creating launch.json:
1. **Review authentication method** with stakeholder
2. **Confirm server URLs** are correct for target environment
3. **Verify credentials handling** follows security policies
4. **Obtain approval** before saving configuration

### Configure Debugging

Create `.vscode/launch.json` based on your environment:

**For Cloud Sandbox:**
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "al",
            "request": "launch",
            "name": "Your own server",
            "server": "https://businesscentral.dynamics.com",
            "serverInstance": "BC",
            "authentication": "AAD",
            "startupObjectType": "Page",
            "startupObjectId": 22,
            "schemaUpdateMode": "Synchronize",
            "tenant": "default"
        }
    ]
}
```

**For On-Premises:**
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "al",
            "request": "launch",
            "name": "Local server",
            "server": "http://localhost",
            "serverInstance": "BC210",
            "authentication": "Windows",
            "startupObjectType": "Page",
            "startupObjectId": 22,
            "schemaUpdateMode": "Synchronize"
        }
    ]
}
```

**For Agent Debugging (Copilot features):**
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "al",
            "request": "attach",
            "name": "Attach to agent (Sandbox)",
            "clientType": "Agent",
            "environmentType": "Sandbox",
            "environmentName": "{EnvironmentName}",
            "breakOnNext": "WebClient"
        }
    ]
}
```

## Phase 4: Best Practices Setup

### Create .gitignore

Generate appropriate `.gitignore`:

```gitignore
# AL Compiler outputs
.alpackages/
.alcache/
.snapshots/
rad.json
*.app

# VS Code settings (optional)
.vscode/launch.json
.vscode/*.log

# Build artifacts
.netFramework/
bin/
obj/

# Test results
TestResults/
*.trx

# Temporary files
*.tmp
*.bak
*~
```

### Documentation Standards

Create comprehensive `README.md`:

```markdown
# {ProjectName}

## Overview
[Project purpose and business value]

## Key Features
- Feature 1: [Description]
- Feature 2: [Description]

## Architecture
[High-level architecture description]

## Naming Conventions
- Tables: `[BusinessEntity]` (e.g., `CustomerExtended`)
- Pages: `[BusinessEntity][PageType]` (e.g., `CustomerListPage`)
- Codeunits: `[Purpose]` (e.g., `SalesOrderProcessor`)
- ID Range: 50000-50099

## Development Guidelines
- Follow AL coding standards
- Use XML documentation for procedures
- Implement error handling with try-functions
- Write unit tests for business logic

## Dependencies
[List of extension dependencies]

## Setup Instructions
[How to set up the development environment]
```

### XML Documentation Pattern

Demonstrate documentation for procedures:

```al
/// <summary>
/// Calculates the total amount for a sales order including tax
/// </summary>
/// <param name="SalesHeader">The sales header record</param>
/// <returns>The total amount including tax</returns>
procedure CalculateTotalWithTax(var SalesHeader: Record "Sales Header"): Decimal
begin
    // Implementation
end;
```

## Phase 5: Verification

### Test Your Setup

1. **Open an AL File**
   - Navigate to any `.al` file in the project
   - Ensure syntax highlighting is active

2. **Rules in place**
   - `.claude/rules/` holds the 4 floor files; `.claude/aldc-rules/` the domain files

3. **Verify Code Analysis**
   - Introduce a small code issue
   - Check that warnings appear

4. **Test Build**
   - Run VS Code `AL: Download Symbols` (a human step in VS Code)
   - Attempt to compile the project
   - Verify no configuration errors

## Troubleshooting

### Authentication Issues

If authentication fails:
- Clear cached credentials in VS Code (`AL: Clear credentials cache`) — a human step, not an agent tool here
- Re-authenticate when prompted
- Verify launch.json authentication method is correct

### Symbol Issues

If symbols are missing:
1. Download symbols: **al-mcp** `al_downloadsymbols` (check the response's `cachePath` matches the project you targeted — in a multi-project session it can silently stick to a previously-targeted project), or VS Code `AL: Download Symbols` / restore the symbol cache in CI
2. If persistent, download source: VS Code `AL: Download Source` (a human step; to inspect base/app symbols use the AL LSP server (hover / go-to-definition) or al-mcp `al_symbolsearch`)
3. Verify app.json dependencies match BC version
4. In a multi-project workspace, prefer `Bash: al workspace compile <workspaceFile>` over rebuilding projects individually — it keeps every project's symbols in sync in one command. Load `skill-al-mcp-workspace` for the full troubleshooting flow.

## Success Criteria

Verify the setup is complete:

- ✅ Visual Studio Code is installed and configured
- ✅ AL Language extension is active
- ✅ Workspace settings are configured
- ✅ Project structure is organized
- ✅ Symbols downloaded successfully
- ✅ Manifest generated
- ✅ Launch.json configured
- ✅ README.md exists with project documentation
- ✅ Code completion is working
- ✅ Build succeeds without errors

## Next Steps

Once your environment is initialized:

**For Development:**
```
agent `al-developer`                    # Implement features (loads page/event skills on demand)
/al-build          # Build and deploy
```

**For Architecture:**
```
agent `al-architect`                    # Design solutions
```

**For TDD Orchestration:**
```
agent `al-conductor`                    # Plan → Implement → Review → Commit
```

## Security Considerations

**What Gets Sent to AI Services:**
- Code snippets from your workspace
- Currently open files
- Your prompts and questions

**What You Should NOT Include:**
- Sensitive credentials or passwords
- Customer data or PII
- Security keys or certificates

**Best Practices:**
- Review organization's AI usage policy
- Use `.gitignore` for sensitive files
- Use environment variables for credentials
- Close files with sensitive information when not needed

---
---

**Environment Initialization Complete! 🎉**

Your AL development environment is ready for Business Central development with optimized AI assistance.
