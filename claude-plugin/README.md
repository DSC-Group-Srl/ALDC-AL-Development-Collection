# ALDC — AL Development Collection for Claude Code

AI-Native Development toolkit for Microsoft Dynamics 365 Business Central.

## Installation

### From the DSC marketplace (recommended)

```
/plugin marketplace add DSC-Group-Srl/dscgroup-bc-nav-agentic-dev
/plugin install bc-dev
```

### Local development / testing

From a clone of the source repo ([`DSC-Group-Srl/ALDC-AL-Development-Collection`](https://github.com/DSC-Group-Srl/ALDC-AL-Development-Collection)),
register this directory as a local marketplace:

```
/plugin marketplace add ./claude-plugin
/plugin install bc-dev
```

Verify registration:

```
/plugin
/agents
/
```

You should see the user-facing agents (`al-architect`, `al-conductor`, `al-developer`, `al-presales`, `al-agent-builder`, `al-documentation-conductor`, plus the on-demand `al-triage`/`dredd`) and 11 slash commands prefixed with `/aldc:`.

## First-Time Setup

After installing the plugin, initialize your project:

```
/aldc:al-initialize
```

This will:
1. Copy path-scoped AL rules to your project's `.claude/rules/`
2. Generate a `CLAUDE.md` for your project
3. Set up VS Code workspace configuration
4. Configure launch.json for debugging

## Agents

| Agent | Command | Purpose |
|-------|---------|---------|
| AL Architect | `agent "aldc:al-architect"` | Solution design, data modeling, integration strategy |
| AL Conductor | `agent "aldc:al-conductor"` | TDD orchestration: plan, implement, review, commit |
| AL Developer | `agent "aldc:al-developer"` | Tactical implementation, debugging, code generation |
| AL Pre-Sales | `agent "aldc:al-presales"` | PERT estimation, SWOT analysis, cost breakdown |
| Agent Builder | `agent "aldc:al-agent-builder"` | Create custom agents for BC AI Development Toolkit |
| AL Documentation Conductor | `agent "aldc:al-documentation-conductor"` | Full app documentation on demand: functional + developer sites, optional client DAF/MAN docx |

### Agent Routing

```
New feature (MEDIUM/HIGH)?  -> aldc:al-architect -> /aldc:al-spec-create -> aldc:al-conductor
New feature (LOW)?          -> /aldc:al-spec-create -> aldc:al-developer
Bug fix / debugging?        -> aldc:al-developer
Architecture review?        -> aldc:al-architect
Full TDD cycle?             -> aldc:al-conductor
Project estimation?         -> aldc:al-presales
```

## Workflows (Slash Commands)

Invoked explicitly from the chat input. Implemented as plugin slash commands under `commands/`.

| Workflow | Command | Purpose |
|----------|---------|---------|
| Spec Create | `/aldc:al-spec-create` | Create functional-technical specifications |
| Build | `/aldc:al-build` | Build, package, deploy extensions |
| PR Prepare | `/aldc:al-pr-prepare` | Prepare pull requests with validation |
| Memory Create | `/aldc:al-memory-create` | Generate session continuity memory |
| Context Create | `/aldc:al-context-create` | Generate project context for AI |
| Initialize | `/aldc:al-initialize` | Full environment and workspace setup |
| Agent Create | `/aldc:al-agent-create` | Create a coded BC agent (Agent SDK) |
| Agent Task | `/aldc:al-agent-task` | Generate agent task integration code |
| Agent Test | `/aldc:al-agent-test` | Generate test codeunits for agents |
| Agent Instructions | `/aldc:al-agent-instructions-create` | Generate agent NL instructions |
| Quality Metrics | `/aldc:al-metrics` | Report independence-ratio, deviation rate, undeclared deviations and prescribed-vs-cited |

## Knowledge Skills

Loaded automatically by agents when needed:

| Skill | Domain |
|-------|--------|
| `skill-api` | API pages, OData, REST |
| `skill-copilot` | AI features, PromptDialog |
| `skill-debug` | Debugging, snapshot debugging |
| `skill-events` | Event subscribers, publishers |
| `skill-pages` | Page types, FastTabs, actions |
| `skill-performance` | CPU profiling, FlowField optimization |
| `skill-permissions` | Permission sets, XLIFF, security |
| `skill-testing` | TDD, AL Test Toolkit |
| `skill-translate` | XLF translation, NAB AL Tools |
| `skill-migrate` | BC version migration |
| `skill-estimation` | PERT estimation, complexity scoring |

## BCQuality (optional, auto-managed)

`aldc:dredd`, `aldc:al-triage`, and the `al-conductor` review phase can back their findings with [BCQuality](https://github.com/microsoft/BCQuality), a citable BC knowledge base. It is **not** a per-project clone: a `SessionStart` hook (`tools/bcquality/precondition_hook.sh` / `.ps1`) auto-installs and refreshes **one shared cache at `~/.claude/bcquality`**, reused by every AL project on the machine — no `../bcquality` folder cluttering your repo, no manual install step.

- First session ever: the hook kicks off a background clone and the session runs the native A–G checklist meanwhile (nothing blocks).
- Later sessions: the hook re-uses the cache instantly, and refreshes it in the background at most once every 12h (override with `$BCQUALITY_UPDATE_INTERVAL_HOURS`).
- **Source and version live in [`tools/bcquality/bcquality.pin`](tools/bcquality/bcquality.pin)** — the single source of truth both hooks read. It ships pinned to a BCQuality **release tag**, so every machine consults the same corpus and a run is reproducible; a weekly workflow in the source repo opens a PR when a newer release lands, with the added/changed/removed knowledge files listed in the body. To consume a fork, change `url` there.
- Override the location with `$BCQUALITY_HOME`. A project that must pin differently from the rest of the estate can still override `url`/`ref`/`pinnedCommit` via an `aldc.yaml → external.bcquality` block (optional, advanced use only) — it wins over the shipped pin.
- Absent or offline is never a blocker — agents fall back to the native A–G checklist and say so.

## Quality metrics (automatic)

A `SubagentStop` hook records what the BCQuality-guided flow actually produced, phase by
phase, and `/aldc:al-metrics` reports it.

Four numbers, each with a threshold that makes it actionable:

| | |
|---|---|
| **independence-ratio** | agent findings / total findings. Implementer and reviewer now draw on the same corpus, so the review can quietly stop being a measurement and become a consistency check. This is the only number that shows it happening — trending to zero means the review is agreeing, not measuring. |
| **deviation rate** | deviated / prescribed. Persistently high on the same article means that rule does not fit how we build: promote it to a `/custom/` override instead of deviating every phase. The report names the top offenders. |
| **undeclared deviations** | Must be zero. Non-zero means the worklist is not being read, and nothing else in the report can be trusted. |
| **cited vs prescribed** | How much the review still finds on its own in prescribed domains. High means the prescriptive pass is scoped too narrowly. |

**Why a hook and not OpenTelemetry.** Claude Code's built-in OTel exports tokens, cost and
tool decisions, and has no API for a plugin to emit its own metrics. These are semantic and
live in the subagents' final text; `SubagentStop` is the one hook that receives it.

**What is stored — and what is not.** Counts, verdicts, and BCQuality knowledge paths (public
Microsoft content). Never a message body, never customer AL, never a path inside the customer
repo, never the full cwd. Enforced in the parser and covered by its self-test
(`tools/metrics/test_parse.sh`), because these files travel.

Four lanes, three of them off until you turn them on:

- `$CLAUDE_PLUGIN_DATA/metrics/aldc-metrics.jsonl` — always; survives plugin updates.
- `<project>/.github/metrics/aldc-metrics.jsonl` — only if that directory exists. Create it to
  version metrics alongside the project.
- **`$APPLICATIONINSIGHTS_CONNECTION_STRING`** — the enterprise lane. Each record becomes an
  `AldcPhase` custom event in Azure Application Insights, numbers in `customMeasurements` and
  dimensions in `customDimensions`, so KQL can slice the four metrics by project, agent and
  verdict. Uses the standard Azure variable, so a machine or pipeline that already has it set
  needs nothing else. No SDK — the public ingestion contract, spoken with stdlib `urllib` and
  `gzip`. Deployment template, KQL and an importable workbook:
  [`tools/metrics/azure/`](tools/metrics/azure/README.md).
- `$ALDC_METRICS_ENDPOINT` (+ optional `$ALDC_METRICS_TOKEN`) — a plain webhook, for anywhere
  that is not App Insights. No credential ships in the plugin; plain HTTP is refused.

Capture is best-effort and never blocks a session. It needs a python interpreter on `PATH`;
without one it logs the gap to `metrics/capture.log` rather than failing.

## Core Principles

- **Extension-only development** — Never modify base application objects
- **Human-in-the-Loop (HITL)** — Critical decisions require user confirmation
- **TDD / spec-driven** — Features follow: spec -> architecture -> test-plan -> implementation -> review
- **Event-driven architecture** — Use integration events for extensibility
- **Skills Evidencing** — Agents declare which skills they loaded and patterns applied

## MCP Servers Included

- **al-mcp** — the official AL CLI's MCP server (`al launchmcpserver`): compile, build, download symbols, publish, run tests, and symbol/dependency queries
- **nab-al-tools** — [NAB AL Tools MCP server](https://github.com/jwikman/nab-al-tools/blob/main/extension/mcp-resources) (`npx @nabsolutions/nab-al-tools-mcp@next`, pre-release channel): full XLF translation workflow — create/refresh language files, retrieve and save translations, review states, keyword search, BC terminology glossary. See `skill-translate`. A `SessionStart` hook (`tools/nodejs/ensure-npx.sh`) checks `npx`/Node.js >= 20 is available and tries to install Node.js LTS if it's missing entirely — it never touches an existing Node install (e.g. a broken nvm/fnm setup), it just reports that case.
- **context7** — Library documentation lookup
- **microsoft-docs** — Microsoft Learn documentation search

## Plugin Structure

```
claude-plugin/
├── .claude-plugin/
│   ├── plugin.json        # Plugin manifest (name, version, MCP servers, hooks ref)
│   └── marketplace.json   # Marketplace entry (for local / remote distribution)
├── agents/                # user-facing agents (design, TDD conductor, dev, presales, agent builder,
│                          #   docs conductor, triage, dredd) + internal subagents (TDD + docs)
├── commands/              # 10 slash commands (/aldc:*)
├── skills/                # 15 knowledge skills (auto-loaded by agents)
├── rules-templates/       # AL coding rules copied by /aldc:al-initialize
├── hooks/hooks.json       # SessionStart preconditions (rules, BCQuality, AL CLI, Node/npx) + PostToolUse/Stop reminders
├── .mcp.json              # MCP server config (al-mcp, nab-al-tools)
├── CLAUDE.md              # Plugin-level guidance loaded by Claude Code
└── README.md              # This file
```

## Requirements

- Claude Code CLI v1.0.0+
- Visual Studio Code with AL Language extension
- Business Central sandbox or on-premises environment

## License

MIT

## Author

[javiarmesto](https://github.com/javiarmesto)

<!-- test: sample edit to trigger bc-dev-upstream-drift.yml detection -->
