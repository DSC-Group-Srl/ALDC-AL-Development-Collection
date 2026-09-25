# ALDC — Claude Code Instructions

## What this repository is

**The source of the `bc-dev` Claude Code plugin.** Everything shipped lives under
`claude-plugin/`; a GitHub Action mirrors that directory into
`plugins/bc-dev/` in
[`dscgroup-bc-nav-agentic-dev`](https://github.com/DSC-Group-Srl/dscgroup-bc-nav-agentic-dev),
the DSC marketplace, and that is how the plugin reaches its users.

This is a fork of
[`javiarmesto/AL-Development-Collection-for-GitHub-Copilot`](https://github.com/javiarmesto/AL-Development-Collection-for-GitHub-Copilot).
Upstream ships a GitHub Copilot / VS Code product built from root-level `agents/`,
`skills/`, `instructions/` and `prompts/` trees, packaged as a VSIX and an npm package.
**We removed that whole chain**: DSC uses Claude Code only, the fork is never published
upstream, and keeping a second copy of every rule produced contradictions between the two
trees. The weekly upstream sync is path-filtered to `claude-plugin/**` for the same reason.

Reasoning and history: [`.github/plans/bcquality-proactive-integration.md`](.github/plans/bcquality-proactive-integration.md).

> `docs/framework/` predates the plugin-only layout and still describes the upstream
> structure in places. Treat `claude-plugin/` as the truth and the framework docs as
> design background.

## Layout

```
claude-plugin/              # THE PRODUCT — everything below ships to the marketplace
  .claude-plugin/           #   plugin.json (manifest, MCP servers, version)
  agents/                   #   15 agents: architect, conductor, developer, presales,
                            #   triage, dredd, agent-builder, demo-architect, 3 conductor
                            #   subagents, 3 doc agents, al-file-reader (Haiku locator)
  commands/                 #   11 slash commands (/al-spec-create, /al-build, /al-metrics, …)
  skills/                   #   26 skills, loaded on demand (incl. skill-test-lane, skill-al-go-devenv, skill-plugin-feedback)
  rules-templates/          #   AL rules. /al-initialize copies the floor (cheat sheet, 2
                            #   protocols, agent-contract) to .claude/rules/ (auto-loaded) and
                            #   the al-*.md domain files to .claude/aldc-rules/ (on demand)
  hooks/hooks.json          #   SessionStart, PreToolUse, SubagentStop, SessionEnd wiring
  tools/                    #   hook scripts: bcquality, al-cli, rules, routing, read-guard,
                            #   conductor-guard, metrics; testlane/ (shared test env + lock)
  docs/templates/           #   report/plan templates the agents fill in
  bcquality-custom/         #   DSC's BCQuality /custom/ layer — scaffolded, not populated

.claude/                    # this repo dogfooding its own plugin — GENERATED, never edit
scripts/sync-claude-workspace.js   # regenerates .claude/ from claude-plugin/
docs/framework/             # ALDC framework spec and design docs (background)
docs/decisions/             # ADRs
.github/plans/              # requirement sets and decision docs
.github/workflows/          # upstream sync, BCQuality pin bump, evidence check
```

## Editing rules

- **Edit `claude-plugin/`, never `.claude/`.** The latter is generated. After changing
  agents, skills or rules, run `node scripts/sync-claude-workspace.js`
  (`--check` in CI fails on drift).
- **A rule lives in exactly one place.** `claude-plugin/rules-templates/` is the source;
  `rules-floor-cheatsheet.md` is its condensed form, auto-loaded (with the two protocols and
  `agent-contract.md`) in every session and subagent that touches AL. Changing a rule means changing both, in the same commit.
- **Where BCQuality already has a knowledge file, defer to it.** Our rules cover what
  BCQuality does not reach — mostly procedure (how to structure a test, a PromptDialog, a
  permission set) and DSC conventions. Duplicating a Microsoft rule here recreates the
  contradiction this repo just spent a cleanup removing.
- **Bump the version in two places** when shipping: `claude-plugin/.claude-plugin/plugin.json`
  and the marketplace entry. The sync does not do it for you.

## BCQuality

An external, citable BC knowledge base ([`microsoft/BCQuality`](https://github.com/microsoft/BCQuality),
300 knowledge files + 485 AL samples across 17 review domains) that backs the findings of
`dredd`, `al-triage` and the conductor's review phase.

- **One shared user-scope cache** at `~/.claude/bcquality`, auto-installed and refreshed in
  the background by the `SessionStart` hook. Not a per-project clone.
- **Source and version**: [`claude-plugin/tools/bcquality/bcquality.pin`](claude-plugin/tools/bcquality/bcquality.pin),
  read by both hooks and by `validate_evidence.py`. Pinned to a release tag.
- **`.github/workflows/bcquality-pin-bump.yml`** opens a PR weekly when a newer release
  lands, listing the knowledge files and review leaves that changed.
- **Every review leaf is active.** There is no pilot and no `disabled-skills` — see
  `claude-plugin/docs/templates/bcquality-task-context.md`.
- Absent or offline never blocks: the agents fall back to the native A–G checklist.

## Agent routing

| Intent | Agent |
|--------|-------|
| Design, architecture, data modeling | `al-architect` |
| Implement, code, debug, fix | `al-developer` |
| Planned feature: plan once → parallel work packages → review + test lane per wave | `al-conductor` |
| Diagnose an existing bug from a symptom | `al-triage` |
| Independent quality audit | `dredd` |
| Estimate, size, propose | `al-presales` |
| Build a BC agent with the Agent SDK | `al-agent-builder` |

```
New feature (HIGH)?   → al-architect → /al-spec-create → al-conductor   (≤6 WPs, ≤3 waves)
New feature (MEDIUM)? → /al-spec-create → al-conductor                  (1-3 WPs, ≤2 waves)
Change (LOW)?         → al-developer
Bug fix / debugging?       → al-triage (diagnosis) → al-developer (fix)
Quality audit?             → dredd
```

Complexity assessment is presented to the user, who confirms before work starts (HITL).

## Core principles

- **Extension-only** — never modify base BC objects. TableExtension, PageExtension, event
  subscribers.
- **Human-in-the-loop** — critical decisions and phase transitions wait for confirmation.
- **TDD** — tests first, then the minimum code to pass, then refactor.
- **Least privilege** — the minimum permission set; XLIFF for every user-facing string.

## Plans

Requirement sets live in `.github/plans/`:

```
.github/plans/
  memory.md                          # cross-session decisions
  {req_name}/
    {req_name}.spec.md
    {req_name}.architecture.md       # HIGH only: decisions, risks, diagrams
    {req_name}.plan.md               # work-package graph + wave log
    {req_name}-complete.md
```

## Build

There is no build step for the plugin: it is markdown, shell and JSON. AL compilation in a
consuming project is the AL CLI's job (`al compile`), driven by `al-developer`.
