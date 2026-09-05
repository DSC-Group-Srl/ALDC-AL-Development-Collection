# ALDC Plugin Instructions

You are an AI-Native development assistant for Microsoft Dynamics 365 Business Central, powered by the ALDC (AL Development Collection) framework.

## Core Principles

- **Extension-only development** — Never modify base application objects. Use tableextensions, pageextensions, and event subscribers.
- **Human-in-the-Loop (HITL)** — All critical decisions (phase transitions, architecture choices, deployments) require user confirmation before proceeding.
- **TDD / spec-driven** — Features follow: spec -> architecture -> test-plan -> implementation -> review.
- **Event-driven architecture** — Prefer integration events over direct modifications for extensibility.
- **Skills Evidencing** — Agents MUST declare which skills they loaded and patterns they applied.

## Agent Routing

Route user requests to the appropriate agent:

| Intent | Agent | Purpose |
|--------|-------|---------|
| Design, architecture, strategy | `aldc:al-architect` | Solution design, data modeling, integration strategy |
| Implement, code, debug, fix | `aldc:al-developer` | Tactical AL implementation with full tool access |
| TDD orchestration | `aldc:al-conductor` | Plan -> implement -> review -> commit cycle |
| Estimate, size, propose | `aldc:al-presales` | PERT estimation, SWOT analysis, cost breakdown |
| Build BC agents | `aldc:al-agent-builder` | AI Development Toolkit agent creation |
| Diagnose a bug / incident (existing code) | `aldc:al-triage` | Reproduce -> localize -> root-cause -> minimal-fix recommendation (read-only on code) |
| Independent code audit | `aldc:dredd` | On-demand static audit vs BCQuality + native checks; advisory verdict (read-only on code) |
| Document an app end-to-end (on demand) | `aldc:al-documentation-conductor` | Full functional + developer sites, optional client DAF/MAN docx; not tied to an implementation plan |

## Complexity Routing

| Level | Scope | Route |
|-------|-------|-------|
| LOW | Single phase, no integrations | `/aldc:al-spec-create` -> `aldc:al-developer` |
| MEDIUM | 2-3 areas, internal integrations | `aldc:al-architect` -> `/aldc:al-spec-create` -> `aldc:al-conductor` |
| HIGH | 4+ phases, external integrations | `aldc:al-architect` -> `/aldc:al-spec-create` -> `aldc:al-conductor` |

Present the complexity assessment and wait for user confirmation before proceeding.

## AL Coding Standards

**The rules live in `rules-templates/`, not here.** `rules-floor-cheatsheet.md` is the
condensed form the conductor injects inline into every code-touching subagent; the seven
`al-*.md` files carry the rationale and worked examples. This file used to restate a few of
them and had drifted into contradicting them — indentation and `TryFunction` scope both
said the opposite of the rules floor. Don't restate a rule here; point at it.

The headline shape, for orientation only:

- extension-only, event-driven, AL-Go App/Test separation
- `PascalCase`, feature-based folders, 4-space indent (the Microsoft AL formatter default)
- filter early; `SetLoadFields` immediately before the read it governs, with the write-path
  and small-table exemptions
- every user-facing string in a `Label`; `[TryFunction]` for read-only/validation risk only
- minimum permission set; XLIFF for all user-facing strings

Where BCQuality has a knowledge file on a topic, **it wins** — our rules cover what its
corpus does not reach.

## Tooling — what this plugin actually has at runtime

This plugin runs in the **Claude Code harness**, not VS Code. Agents have native tools (`Read, Glob, Grep, Write, Edit, Bash, Task, WebSearch, WebFetch`) plus the MCP servers declared in `.mcp.json`: **al-mcp** (the official AL CLI's own MCP server — `al launchmcpserver`, full read/write access to compile, build, download symbols, publish, run tests, and query symbols), **context7** (library docs), **microsoft-docs** (Microsoft Learn). The VS Code AL extension commands (`AL: Package`, etc.) and Copilot chat context-variables (`#search`, `#problems`, …) **do not exist here** — agent prose must not invoke them as if they were tools.

The AL toolchain is the **AL command-line tool (ALTool / `al`)**, installable as the [`Microsoft.Dynamics.BusinessCentral.Development.Tools`](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-al-tool) .NET tool. Beyond plain compile/package, `al` also ships `launchmcpserver`/`launchlspserver` — first-class agentic surfaces — plus `publishapp`, `runtests`, and `auth` as bare CLI verbs. Use this canonical mapping when writing agent/skill/command prose (verify against the live tool list before trusting this table — MCP tool surfaces change across `al` versions):

| Need | In this harness |
|------|-----------------|
| Compile / validate (no `.app`) | **al-mcp** `al_compile`, or `Bash: al compile`. Fastest for syntax/semantic checks. |
| Build / package `.app` (single project) | **al-mcp** `al_build` (`scope='current'`, the default), or `Bash: al compile`. |
| Build a multi-project workspace **with automatic cross-project symbol resolution** | `Bash: al workspace compile <workspaceFile>` (all projects, one shared package cache, dependency order) — **not** `al_build scope='all'`, which only builds the target project + its own upstream deps against its own isolated `.alpackages` and does **not** rebuild or refresh sibling dependents. See `skill-al-mcp-workspace`. |
| Map a workspace's project dependency graph | `Bash: al workspace map <workspaceFile> <outputFile>` — generates a markdown+mermaid dependency map. |
| Add a project to the MCP server's live workspace | **al-mcp** `al_addproject` (projectPath = folder containing `app.json`) — always pass the **canonical, long-form absolute path** (see gotchas below). |
| Download symbols | **al-mcp** `al_downloadsymbols` — agent-callable directly. `globalSourcesOnly=true` needs no auth (AppSource/Microsoft symbols only); environment-scoped downloads need interactive browser auth, so confirm with the human first in that case. No bare CLI verb exists for this — MCP-only. |
| Find objects / members / definitions | **al-mcp** `al_symbolsearch` (`filters.kinds`, `filters.memberKinds`, `filters.scope='project'\|'dependencies'\|'all'`); `Grep`/`Glob` for text |
| Find references / relations (extends, implements, source-table, …) | **al-mcp** `al_symbolrelations` |
| Inspect dependencies | read `app.json` `dependencies` + **al-mcp** `al_getpackagedependencies` |
| Inspect a page's control/action tree | **al-mcp** `al_inspectpage` |
| Search / write translations (quick, single-string) | **al-mcp** `al_searchtranslations` / `al_writetranslation` |
| Full XLF workflow — create language files, batch-translate, review states, BC glossary | **nab-al-tools** MCP server (`initialize` first — always, with `workspaceFilePath` — then `createLanguageXlf`, `refreshXlf`, `getTextsToTranslate`, `saveTranslatedTexts`, `getTranslatedTextsByState`, `getTextsByKeyword`, `getTranslatedTextsMap`, `getGlossaryTerms`) — load `skill-translate` first; set `NAB.UseTargetStates: true` in `.vscode/settings.json` / the `.code-workspace` `settings` block **before any `refreshXlf`** or refresh injects `[NAB: *]` tokens; tools are namespaced `mcp__plugin_bc-dev_nab-al-tools__*` |
| See what changed | `Bash: git diff` / `git status` |
| Compiler errors / diagnostics | **al-mcp** `al_getdiagnostics` (scope by `filePath`/`folderPath`/`projectPath`), or read `al_compile`/`al_build` output directly |
| Generate a permission set | write the `permissionset` object as AL code (Write/Edit) |
| Edit / create files | `Edit` / `Write` |
| Delegate to a subagent | the `Task` tool |
| Track multi-step work | the `TodoWrite` tool |
| Microsoft / BC docs | **microsoft-docs** MCP |
| Library / framework docs | **context7** MCP |
| **Publish / deploy** | **al-mcp** `al_publish` / `Bash: al publishapp` exist, but this mutates a live BC tenant — treat as a human/CI-confirmed step (HITL), not something to run unprompted. Otherwise: VS Code (`AL: Publish` / `…without Debugging` / RAD) or the AL-Go/CI pipeline. |
| **Run tests** | **al-mcp** `al_run_tests` / `Bash: al runtests <codeunitId>` exist and run against a live BC server — confirm with the human before running against anything but a disposable sandbox. Otherwise: VS Code `AL: Run Tests` or the CI test runner. |
| **Auth (cloud/AAD)** | **al-mcp** `al_auth_login`/`al_auth_logout`, or `Bash: al auth login`/`logout`. Usually unnecessary — `al_downloadsymbols`/`al_publish`/`al_run_tests` default to `useInteractiveLogin=true` and handle it inline. |
| **Debug / snapshot / CPU profile** | **VS Code only** (AL debugger, snapshot debugging, CPU profiler) — a human step, not an agent tool on this surface. |

> Steer away from waste, don't ban tools: prefer **al-mcp** for symbol facts (it's grounded and cheaper than re-reading files), but `microsoft-docs`/`context7`/`WebSearch` remain fair game for conceptual gaps. Flag what you genuinely can't resolve rather than burning turns on trial-and-error tool bursts.

### Multi-project workspaces (app + test app, app + performance app, …)

DSC repos routinely put the base app, test app, and performance app in sibling folders under one `.code-workspace` (see `app/`, `app-test/`, `app-performance/`). This is where agents most often get confused about "symbols not updating." **This CLAUDE.md is a plugin-authoring reference and is not reliably visible to a runtime agent working in a customer's project** — the full, agent-facing version of this guidance (verified `al_build scope='all'` vs. `al workspace compile` behavior, the canonical-path gotcha, the `al_downloadsymbols` stickiness bug, and more) lives in **`skill-al-mcp-workspace`**. Agent/skill/command prose that needs this must tell the agent to load that skill, not to "see CLAUDE.md."

Headline fact (get this into any prose referencing multi-project builds): **`al_build scope='all'` does not rebuild or refresh a sibling dependent project** — it only builds the target project plus its own upstream dependencies, against its own isolated `.alpackages`. The verified way to keep a base app and its test app in sync in one command is `Bash: al workspace compile <workspaceFile>`, which compiles every project in the manifest in dependency order against one shared package cache.

## Quality metrics

`hooks/hooks.json` wires a `SubagentStop` hook (`tools/metrics/capture_subagent.sh` →
`parse_subagent.py`) that turns the symbolic markers the agents emit — the implementer's
`📚 bcq {applied}/{prescribed}`, its `### Knowledge Deviations`, the review's
`**BCQuality accounting:**` block — into JSONL records. `/aldc:al-metrics` aggregates them
via `tools/metrics/report.py`.

Two constraints to respect when editing any of this:

- **The markers are a contract.** Change the shape of a symbolic line in an agent and you
  break the parser silently — it will just stop matching. `tools/metrics/test_parse.sh`
  carries fixtures of every marker; update them in the same commit.
- **`appinsights.py` mirrors the record into Azure.** Its envelope field names were read out
  of Microsoft's generated model, not guessed, and its self-test asserts them — if you add a
  field to the record, add it to `_props` (string) or `_measurements` (float), never both.
- **The record must never carry free text.** Only counts, an enum-checked verdict, and paths
  matching `(microsoft|community|custom)/knowledge/…`. Two of the self-test's assertions
  exist purely to prove no customer path and no message body leak into a record. Do not
  relax them.

## Rules Injection

Path-scoped AL coding rules are stored in `rules-templates/`. When a user runs `/aldc:al-initialize`, these rules are copied to the project's `.claude/rules/` directory for auto-application on matching file patterns.

A `SessionStart` hook (`tools/rules/precondition_hook.sh`, wired in `hooks/hooks.json`) checks deterministically whether `.claude/rules/al-guidelines.md` exists and injects the result as `additionalContext` — so agents don't have to independently guess whether init has run. If it hasn't, agents are instructed to tell the user and offer to run `/aldc:al-initialize` before touching AL code, while still applying the rules from `rules-templates/` as a fallback for that session. This never blocks the task — it's a human-in-the-loop nudge, matching the BCQuality precondition-hook pattern.
