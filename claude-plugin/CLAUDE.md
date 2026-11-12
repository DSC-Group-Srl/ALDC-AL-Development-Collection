# ALDC Plugin Instructions

You are an AI-Native development assistant for Microsoft Dynamics 365 Business Central, powered by the ALDC (AL Development Collection) framework.

## Core Principles

- **Extension-only development** — Never modify base application objects. Use tableextensions, pageextensions, and event subscribers.
- **Human-in-the-Loop (HITL)** — All critical decisions (phase transitions, architecture choices, deployments) require user confirmation before proceeding.
- **TDD / spec-driven** — Features follow: spec (with its tests section) -> plan (work packages) -> parallel implementation in waves -> review + test lane -> commit.
- **Event-driven architecture** — Prefer integration events over direct modifications for extensibility.
- **Skills Evidencing** — Agents MUST declare which skills they loaded and patterns they applied.

## Agent Routing

Route user requests to the appropriate agent:

| Intent | Agent | Purpose |
|--------|-------|---------|
| Design, architecture, strategy | `bc-dev:al-architect` | Solution design, data modeling, integration strategy |
| Implement, code, debug, fix | `bc-dev:al-developer` | Tactical AL implementation with full tool access |
| Planned feature (MEDIUM/HIGH) | `bc-dev:al-conductor` | Plan once -> parallel work packages in git worktrees -> review + locked test lane per wave -> commit |
| Estimate, size, propose | *not in bc-dev* — `/bc-cons:stima-sviluppo` (plugin `bc-cons`) | The calibrated estimator (human hours and agent effort, tuned on bc-dev telemetry) lives there; it writes the estimate on the Business Central Issue, and bc-dev reads it back with `skill-bc-issue`. bc-dev had its own `al-presales` agent and `skill-estimation` until 8.20; they were retired so there is one estimation method. |
| Build BC agents | `bc-dev:al-agent-builder` | AI Development Toolkit agent creation |
| Diagnose a bug / incident (existing code, or a Freshdesk ticket number) | `bc-dev:al-triage` | Reproduce -> localize -> root-cause -> minimal-fix recommendation (read-only on code) |
| Independent code audit | `bc-dev:dredd` | On-demand static audit vs BCQuality + native checks; advisory verdict (read-only on code) |
| Document an app end-to-end (on demand) | `bc-dev:al-documentation-conductor` | Full functional + developer sites, optional client DAF/MAN docx (DSC template via the `dsc-docs` plugin); not tied to an implementation plan |
| Extract user stories/use cases + generate or customize demo data | `bc-dev:al-demo-architect` | Analyzes an app, produces reviewable user-stories/use-cases/demo-data-plan docs, then delegates the Contoso Demo Tool integration (harness, then data content) to `al-developer` — read-only on AL code itself; bootstrap and incremental (diff-based) modes |

## Complexity Routing

| Level | Scope | Route |
|-------|-------|-------|
| LOW | One area, cause/approach known | `bc-dev:al-developer` (spec optional) |
| MEDIUM | 2-3 areas, internal integrations | `/bc-dev:al-spec-create` (with §Decisions) -> `bc-dev:al-conductor` — 1-3 WPs, ≤2 waves |
| HIGH | 4+ areas or external integrations | `bc-dev:al-architect` -> `/bc-dev:al-spec-create` -> `bc-dev:al-conductor` — ≤6 WPs, ≤3 waves |

Present the complexity assessment and wait for user confirmation before proceeding. For
**HIGH** complexity, also ask the user whether they want to switch the session to Opus
before work begins — HIGH-complexity work (4+ areas, external integrations, architecture
critical) is exactly where the larger model's judgment pays for itself, and the user may
be running a faster/cheaper model by default. Never switch models yourself; just surface
the question alongside the complexity assessment and let the user decide.

When you delegate to any bc-dev agent, **don't forbid it from running tests out of fear of
concurrent publishes** — the test lane's per-environment lock exists for exactly that. Your own
final verification comes in addition to tests during development, not instead of them.

**A DSC dependency missing on the test environment is the agent's to publish, not a question
for the user.** The lane names it (`dependency-missing`, or `server-compile-failed` with the
server's `errors`) and `skill-test-lane` §2 *Dependencies missing* says where the `.app` comes
from: the package cache, the local GITCloner clone, the latest release. An agent that hands
back "the sandbox lacks Dyna HR" gets sent back to publish it. On 2026-11-10 one fix cost
three such round trips, each answered "install it".

## Delegating to multi-phase agents (al-conductor and similar)

`al-conductor` (and `al-documentation-conductor`) already narrate their own progress —
one line per wave/WP state change, plus the plan and completion cards. That narration only reaches the
user when the conductor is the live, foreground agent. **When you delegate to one of these
via the `Task`/`Agent` tool as a background subagent, its progress lines land in its own
transcript, not in front of the user — you are the only thing standing between that
narration and the person waiting on it.**

Between plan approval and the final gate the conductor runs every wave without stopping, so
there is no approval bounce-back to surface progress. Check in on it periodically and relay its
latest line (`▶ Wave 1/2 · WP-1, WP-2 running`, `✅ Wave 1/2 done · lane 14/14`) **before the
user has to ask**. One line is enough.

## Relaying an agent's questions to the developer

When `al-architect`, `al-conductor`, `al-triage` or a spec's §Open Questions come back with
questions, the main thread asks them — subagents have no `AskUserQuestion`. Developers kept
getting the plan's raw list dumped on them: `WP-3`, `§4.1`, `D-2`, `Q7`, "option B", all at
once, in prose. They need to understand what is being decided, not decode the plan.

- **Use `AskUserQuestion`**, at most 4 questions per call, most blocking first. More than 4 →
  ask the rest in a second call after the first answers. Never a numbered list in prose.
- **Plain words.** Each question says what the choice changes for the app or its users; each
  option is a short label plus a one-line trade-off; your recommendation first.
- **No codes as the subject.** A plan label (WP, §, FR, D-, Q-, wave, option letter) or object
  ID never stands alone — if it helps traceability it goes in parentheses after the meaning.
- **Answer what you can first.** Drop questions the spec, the code or an earlier answer
  already settles.
- **Hand the answers back** to the agent (SendMessage, or a new Task carrying them).

This is wired into the routing SessionStart hook (`tools/routing/precondition_hook.sh`), which
is what actually reaches the main thread in a consuming project.

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

This plugin runs in the **Claude Code harness**, not VS Code. Agents have native tools (`Read, Glob, Grep, Write, Edit, Bash, Task, WebSearch, WebFetch`) plus the MCP servers declared in `.mcp.json`: **al-mcp** (the official AL CLI's own MCP server — `al launchmcpserver`, full read/write access to compile, build, download symbols, publish, run tests, and query symbols), **context7** (library docs), **microsoft-docs** (Microsoft Learn), **freshdesk** (DSC's helpdesk, opt-in via `FRESHDESK_API_KEY`). The VS Code AL extension commands (`AL: Package`, etc.) and Copilot chat context-variables (`#search`, `#problems`, …) **do not exist here** — agent prose must not invoke them as if they were tools.

The AL toolchain is the **AL command-line tool (ALTool / `al`)**, installable as the [`Microsoft.Dynamics.BusinessCentral.Development.Tools`](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-al-tool) .NET tool. Beyond plain compile/package, `al` also ships `launchmcpserver`/`launchlspserver` — first-class agentic surfaces — plus `publishapp`, `runtests`, and `auth` as bare CLI verbs. Use this canonical mapping when writing agent/skill/command prose (verify against the live tool list before trusting this table — MCP tool surfaces change across `al` versions):

| Need | In this harness |
|------|-----------------|
| Compile / validate (no `.app`) | **al-mcp** `al_compile`, or `Bash: al compile`. Fastest for syntax/semantic checks. |
| Build / package `.app` (single project) | **al-mcp** `al_build` (`scope='current'`, the default), or `Bash: al compile`. `.app` only — not a source of warning counts. |
| Build a multi-project workspace **with automatic cross-project symbol resolution** | `Bash: al workspace compile <workspaceFile>` (all projects, one shared package cache, dependency order) — **not** `al_build scope='all'`, which only builds the target project + its own upstream deps against its own isolated `.alpackages` and does **not** rebuild or refresh sibling dependents. See `skill-al-mcp-workspace`. |
| Map a workspace's project dependency graph | `Bash: al workspace map <workspaceFile> <outputFile>` — generates a markdown+mermaid dependency map. |
| Add a project to the MCP server's live workspace | **al-mcp** `al_addproject` (projectPath = folder containing `app.json`) — always pass the **canonical, long-form absolute path** (see gotchas below). |
| Download symbols | **al-mcp** `al_downloadsymbols` — agent-callable directly. `globalSourcesOnly=true` needs no auth (AppSource/Microsoft symbols only); environment-scoped downloads need interactive browser auth, so confirm with the human first in that case. For a whole workspace (every project, one source, IT/CH switch) use **GITCloner** — `GITCloner al-symbols … --json`, see `skill-gitcloner`. |
| Workspace AL state / find a DSC repo locally / publish a whole workspace | **GITCloner** `--json` CLI (`al-projects`, `repos`, `clone-repo`, `al-publish` — the last one HITL): load `skill-gitcloner` |
| Find objects / members / definitions | **al-mcp** `al_symbolsearch` (`filters.kinds`, `filters.memberKinds`, `filters.scope='project'\|'dependencies'\|'all'`); `Grep`/`Glob` for text |
| Find references / relations (extends, implements, source-table, …) | **al-mcp** `al_symbolrelations` |
| Inspect dependencies | read `app.json` `dependencies` + **al-mcp** `al_getpackagedependencies` |
| Inspect a page's control/action tree | **al-mcp** `al_inspectpage` |
| Search / write translations (quick, single-string) | **al-mcp** `al_searchtranslations` / `al_writetranslation` |
| Full XLF workflow — create language files, batch-translate, review states, BC glossary | **nab-al-tools** MCP server (`initialize` first — always, with `workspaceFilePath` — then `createLanguageXlf`, `refreshXlf`, `getTextsToTranslate`, `saveTranslatedTexts`, `getTranslatedTextsByState`, `getTextsByKeyword`, `getTranslatedTextsMap`, `getGlossaryTerms`) — load `skill-translate` first; set `NAB.UseTargetStates: true` in `.vscode/settings.json` / the `.code-workspace` `settings` block **before any `refreshXlf`** or refresh injects `[NAB: *]` tokens; tools are namespaced `mcp__plugin_bc-dev_nab-al-tools__*` |
| See what changed | `Bash: git diff` / `git status` |
| Compiler errors / diagnostics | Read `al_compile` output (the authority for analyzer warnings). `al_getdiagnostics` after `al_build` drops analyzer diagnostics and mixes in sibling projects — never count warnings from it (`compiler-authority-protocol.md` §0, `skill-al-mcp-workspace` Gotcha 3) |
| Generate a permission set | write the `permissionset` object as AL code (Write/Edit) |
| Edit / create files | `Edit` / `Write` |
| Delegate to a subagent | the `Task` tool |
| Track multi-step work | the `TodoWrite` tool |
| Microsoft / BC docs | **microsoft-docs** MCP |
| Library / framework docs | **context7** MCP |
| **Publish / deploy** | **al-mcp** `al_publish` / `Bash: al publishapp` exist, but this mutates a live BC tenant — treat as a human/CI-confirmed step (HITL), not something to run unprompted. Otherwise: VS Code (`AL: Publish` / `…without Debugging` / RAD) or the AL-Go/CI pipeline. |
| **CI/CD on GitHub (AL-Go)** | `gh run list` / `gh run view <id> --log-failed` / `gh pr checks`; dispatch with `gh workflow run` (HITL for Publish To Environment, Create release, Publish To AppSource). DSC's branch model (`main` trunk, nightly-rebuilt `test`), the PR → test env → UAT → merge → production flow, every workflow, settings and secrets by name, PTE vs AppSource: load `bc-dev:skill-al-go-workflows`. |
| **Run tests** | Only through the **test lane** (`bc-dev:skill-test-lane`, `tools/testlane/lane.py`): the user picks the environment from `.vscode/launch.json` (none usable → add one, or accept *tests not executed*); a lock serializes the one shared environment across parallel work packages and sessions. The AL CLI lower-cases its options, so the lane targets an environment via a single-configuration scratch `launch.json` + `--project`. No usable environment and the repo has `.AL-Go/localDevEnv.ps1` → `bc-dev:skill-al-go-devenv` creates a local container non-interactively (one UAC click) and registers its credentials where the AL CLI reads them (`tools/testlane/save-onprem-credentials.ps1`). |
| **Auth (cloud/AAD)** | **al-mcp** `al_auth_login`/`al_auth_logout`, or `Bash: al auth login`/`logout`. Usually unnecessary — `al_downloadsymbols`/`al_publish`/`al_run_tests` default to `useInteractiveLogin=true` and handle it inline. |
| **Freshdesk tickets** (dsc-group.freshdesk.com) | **freshdesk** MCP (`mcp__plugin_bc-dev_freshdesk__*`), opt-in via the developer's own `FRESHDESK_API_KEY` — load `bc-dev:skill-freshdesk` first (setup, call budget, read/note templates). Read one ticket by number, once; write only confirmed private notes, never a reply. `tools/freshdesk-guard/` enforces the allowlist and the per-session cap. |
| **DSC's own Business Central** (Issues, Tasks, Projects, booked hours, an Issue's Markdown notes and attached files, AppSource object ID ranges) | **businesscentral** MCP (`mcp__plugin_bc-dev_businesscentral__*`): DSC tenant, `Production`, company `DSC GROUP SRL`, configuration `OPERATIONS`, the developer's own sign-in. **Read-only** (`tools/bc-guard/` denies everything but `List_` actions), with one confirmed write. Load `bc-dev:skill-bc-issue` first: it finds the Issue a piece of work belongs to, links the session to it (`emit.py AldcIssue`) and reads the estimate, booked hours, Markdown notes and attached Teams/SharePoint files on it (file list and link; the content needs a Microsoft 365 connector or the user). `bc-dev:skill-app-id-range` claims the object ID range of an AppSource app from the Product Ranges register — the guard turns that one call into a user prompt. Never a customer's Business Central. |
| **Code outside the workspace** (a dependency app, the customer's other apps, standard BC) | **DSC Code Reader** — DSC's organisation connector (`mcp__claude_ai_Code_Reader_DSC__*`), not a plugin server: load `bc-dev:skill-code-reader`. Read-only by rule; its issue tools are never used. Not connected → `skill-gitcloner`. |
| **Debug / snapshot / CPU profile** | **VS Code only** (AL debugger, snapshot debugging, CPU profiler) — a human step, not an agent tool on this surface. |

> Steer away from waste, don't ban tools: prefer **al-mcp** for symbol facts (it's grounded and cheaper than re-reading files), but `microsoft-docs`/`context7`/`WebSearch` remain fair game for conceptual gaps. Flag what you genuinely can't resolve rather than burning turns on trial-and-error tool bursts.

### Multi-project workspaces (app + test app, app + performance app, …)

DSC repos routinely put the base app, test app, and performance app in sibling folders under one `.code-workspace` (see `app/`, `app-test/`, `app-performance/`) — and, once `al-demo-architect` has run, a fourth sibling `app-demo/` holding the Contoso Demo Tool integration (`skill-demo-data`), dependent on the base app. This is where agents most often get confused about "symbols not updating." **This CLAUDE.md is a plugin-authoring reference and is not reliably visible to a runtime agent working in a customer's project** — the full, agent-facing version of this guidance (verified `al_build scope='all'` vs. `al workspace compile` behavior, the canonical-path gotcha, the `al_downloadsymbols` stickiness bug, and more) lives in **`skill-al-mcp-workspace`**. Agent/skill/command prose that needs this must tell the agent to load that skill, not to "see CLAUDE.md."

Headline fact (get this into any prose referencing multi-project builds): **`al_build scope='all'` does not rebuild or refresh a sibling dependent project** — it only builds the target project plus its own upstream dependencies, against its own isolated `.alpackages`. The verified way to keep a base app and its test app in sync in one command is `Bash: al workspace compile <workspaceFile>`, which compiles every project in the manifest in dependency order against one shared package cache.

## Hook wiring — one bash process per event

Every hook, `.mcp.json` al-mcp and `.lsp.json` launch bash through
`cmd /c tools/environment/run-bash.cmd <script>`, never a bare `bash`: `cmd /c bash` can resolve
`C:\Windows\System32\bash.exe` (the WSL launcher) and run the script in the default WSL distro,
which kills al-mcp with `CONNECTION_CLOSED` (issue #83). The wrapper picks Git Bash explicitly.

On Windows every hook is its own bash process, and Claude Code starts the hooks of
one event in parallel; concurrent Git Bash (MSYS2) start-ups intermittently die with
`fatal error - add_item (...) failed, errno 1` and the harness silently skips that hook,
guards included (issue #77). So `hooks/hooks.json` has **one bash entry per event**:

- **SessionStart** → `tools/hooks/sessionstart.sh`: runs the BCQuality, AL tool, ALCops, npx,
  python, rules, routing, git branch policy, CLAUDE.md freshness, VS Code workspace, Business Central Issue link and heartbeat scripts as background jobs of that one process, each
  with its own timeout, and merges their `additionalContext` into one JSON payload (pure bash,
  no python). `tools/environment/git-bash-check.ps1` stays a separate PowerShell hook.
- **PreToolUse** (no matcher) → `tools/hooks/pretooluse.sh`: starts `metrics/alive.sh` in the
  background, then routes by `tool_name` — Read to the read-guard, Bash/PowerShell to al-go-guard
  then the read-guard, Write/Edit to conductor-guard, al-go-guard, then main-thread-guard (first
  deny wins), `mcp__plugin_bc-dev_freshdesk__*`
  to `freshdesk-guard` (allowlist, per-session cap, `createTicketNote` → human ask, private
  only; kill switch `ALDC_FRESHDESK_GUARD_DISABLE=1`), `mcp__plugin_bc-dev_businesscentral__*`
  to `bc-guard` (only `List_` actions run on DSC's Business Central; `Create_ProductRangeClaim`
  → human ask; kill switch
  `ALDC_BC_GUARD_DISABLE=1`), Task/Agent to `issue/run_guard.sh` (a conductor run starts
  only once the Business Central Issue was asked; kill switch
  `ALDC_ISSUE_RUN_GUARD_DISABLE=1`). Other tools: silent.
- **SessionEnd**, **SubagentStop**: one script each, unchanged.

A new hook script goes into the matching dispatcher, never as a new `hooks.json` entry.
Self-test: `bash tools/hooks/test_dispatchers.sh`.

## Git branches and AL-Go release inputs

- **Branch policy** (`tools/git/branch_policy.sh`, SessionStart, any git repo): reads the org
  custom property `branch-protection-enabled` (`gh api repos/{o}/{r}/properties/values`, cached
  in `~/.claude/aldc-cache/branch-protection/`, unset = org default `false`). Every mode: never
  create a branch without asking, follow-ups stay on the current branch. `true` → trunk-based,
  PR into `main`; after a merge `tools/git/cleanup_merged.sh` goes back to `main`, pulls and
  deletes only branches whose work is merged (ancestor of `origin/main`, or merged PR with the
  same tip). `false` → legacy flow, no PRs: commit on `main`, push with
  `tools/git/sync_main_test.sh`, which keeps `main` and `test` identical. When they have
  drifted it prints one plain `Proposed fix: …` sentence; Claude always offers it (also at
  session start, from the last fetch) and on yes reruns with `--fix` (merge the missing commits,
  push both; a conflict aborts and lists the files). Never force-pushes or resets. Subagents never create branches.
- **AL-Go release inputs are always on** (`tools/al-go-guard/`, PreToolUse): a `gh workflow run`
  of Create release / Increment Version Number without `directCommit=true` +
  `useGhTokenWorkflow=true`, or of Publish To AppSource without `GoLive=true`, is denied; so is
  writing those inputs into a CLAUDE.md or memory file (removing them stays allowed). Kill
  switch `ALDC_ALGO_GUARD_DISABLE=1`.
- **CLAUDE.md pruning**: `tools/claudemd/staleness_hook.sh` (SessionStart, AL workspaces) suggests
  `/bc-dev:al-memory-create` — now *prune and recreate* — when the project CLAUDE.md has no
  `<!-- aldc-refreshed: … -->` stamp, was edited 30+ days after it, or exceeds 150 lines.
- Self-test: `bash tools/git/test_git.sh`.

## DSC Business Central and the Issue link

`.mcp.json` carries a `businesscentral` server: DSC's **own** production Business Central
(company `DSC GROUP SRL`, configuration `OPERATIONS`), the same one `dsc-timesheet` uses. Its
purpose is to tie a piece of work to the **Issue** DSC plans and bills it on, so estimates,
telemetry and the prediction model join on one key.

- **The URL ends in `?c=bc-dev` on purpose.** Claude Code drops MCP servers that share a URL,
  and every Business Central connection has the same one. Without the suffix this entry and
  `dsc-timesheet`'s would fight and one plugin would lose its tools. The server ignores the
  query string. Each connection signs in separately. Don't "clean it up".
- **Read-only, structurally.** `OPERATIONS` also exposes writes (Issues, Tasks, the timesheet
  insert API). `tools/bc-guard/pretooluse_hook.sh` allows search, describe and `List_`
  invokes and denies the rest. It only matches bc-dev's own server name, so `dsc-timesheet`
  keeps writing timesheet lines on its connection.
- **One write, always confirmed: the object ID range of an AppSource app.** DSC keeps the
  register of its AppSource object IDs in Business Central (Product Ranges, API pages 75114
  and 75115 of DSC Group PowerAutomate). `skill-app-id-range` reads it and claims a range with
  `Create_ProductRangeClaim`; the guard answers that action with `ask`, so the user approves
  every claim, also in auto mode. The claim assigns IDs at once and is **not idempotent**, which
  is why it is not simply allowed. `MarkAsFree` (release a range) stays denied: a person does
  it. Don't widen the exception to other `Create_` actions.
- **The link.** `skill-bc-issue` derives the likely Issue once — the repo's `customer`
  (and `product`) property plus the open Issues assigned to the developer, whose employee
  record is found from the company e-mail (`tools/issue/whoami.sh`: gh account, then
  `git config user.email`, then the Claude account) — **proposes it and the user confirms**
  (yes / another one / no Issue; never linked without a yes), then writes
  `**BC Issue:** <entryNo>` in the spec header. An Issue without an estimate is normal. From there it is **scripts, not the model's memory**:
  `tools/issue/link_hook.sh` (SessionStart, AL workspaces) runs
  `emit.py AldcIssue --from-branch`, which finds the in-progress spec whose `**Branch:**` is
  the checked-out branch and links the session; `AldcRunStart` / `AldcEstimate` read the same
  line by `req`, and `AldcEstimate` also takes `estP50Min`/`estP80Min` from the spec's
  `**Agent estimate:** P50 <n> min · P80 <n> min (<source>)` line. `ident.py` keeps the link in
  `<live dir>/<session>.issue` and adds `issueNo` to **every** event of the session. Digits
  only — `ident.RE_ISSUE` — so the no-free-text rule below holds; the scripts read the spec's
  header block and nothing else. A spec without the line, or a feature branch without a spec,
  gets a one-line nudge at session start; `none` is silent. Kill switch
  `ALDC_ISSUE_LINK_DISABLE=1`; self-test `bash tools/issue/test_link.sh`.
  **A run asks first:** `tools/issue/run_guard.sh` (PreToolUse on Task/Agent) denies launching
  `al-conductor` until the brief or the branch's spec says `BC Issue: <number|none>`; the deny
  tells the main thread to ask the user with `AskUserQuestion`. "None" passes, so it never
  blocks for good. Kill switch `ALDC_ISSUE_RUN_GUARD_DISABLE=1`.
  Why structural: before 8.20 the telemetry had 72 conductor runs and 0 with an Issue or an
  estimate, and two thirds of all measured tokens sat in sessions tied to no task.
- **Who uses it.** The main thread (routing hook) and `/bc-dev:al-spec-create` resolve and
  record the Issue and quote the estimate already on it (estimating itself is `bc-cons`'s
  `/stima-sviluppo`, not bc-dev's); `al-triage` maps a Freshdesk ticket to its Issue; `al-conductor` only reads the spec line.
- **Customer tenants are out of scope.** Reaching a customer's Business Central through
  delegated (GDAP) access needs the Entra app authorized in each customer tenant by someone
  holding Application Administrator or Cloud Application Administrator there, and tokens from
  the Azure CLI carry no delegated role. Tested 2026-11 on three customers; parked.
- **Notes and files of an Issue** are in the API since DSC Group Base 28.26 / PowerAutomate
  28.1 (DSC-Group-Srl/dscgroup-base#74): `List_MarkdownNotes_PAG75113` returns the full note
  text, `List_AttachedFiles_PAG75112` the file list with its SharePoint `webUrl`, both filtered
  by `parentId` = the `id` of the Issue, Task or Project; the Issue itself carries the counts
  and its Teams team, channel and folder ids. `skill-bc-issue` §4. The file **content** is not
  served by Business Central, and the `…FolderUrl` fields are always empty.

## DSC Code Reader

`skill-code-reader` and the `tools:` lists of `al-architect`, `al-developer`, `al-triage`
and `al-planning-subagent` use DSC's organisation connector
(`mcp__claude_ai_Code_Reader_DSC__*`, a read-only subset — never its issue tools). It is **not**
in `.mcp.json`: a plugin entry on the same URL displaces the working organisation connector
(verified with a local entry), and Claude Code cannot sign in to it yet — the Entra app
`dsc-code-reader-claude-connector` has no public-client redirect `http://localhost:<port>/callback`.
Once IT adds one, add the server here with that `oauth.clientId`/`callbackPort` and list
`mcp__plugin_bc-dev_code-reader__*` next to the connector names in those agents.

## VS Code workspace awareness

`tools/vscode/workspace_hook.sh` (SessionStart, any folder): when the session runs inside a VS Code
window with a multi-root workspace, it lists the window's other folders (AL app name, own git
repo) so the agent looks there before saying a file or project does not exist. It reads the lock
file the Claude Code VS Code extension writes per window (`~/.claude/ide/<port>.lock`,
`workspaceFolders`), picked by `$CLAUDE_CODE_SSE_PORT`, or — only when the environment says
VS Code — by the live lock that contains the session folder. No lock, a single-folder window or
only nested folders: silent. Pure bash. Kill switch `ALDC_VSCODE_WORKSPACE_DISABLE=1`.
Self-test: `bash tools/vscode/test_workspace.sh`.

## What the telemetry told us (9.0)

Four findings from the Application Insights data and from local transcripts, and what changed:

- **Session totals were missing for most finished runs** — `session_end.sh` ran in the
  foreground and was killed when the user exited. It now parks the payload in a temp file and
  detaches the worker (returns in ~0.2 s).
- **The conductor's own phase was not joined to its run** — it stops after its `AldcRun`
  closed the run. `parse_subagent.live_run()` now joins `al-conductor` to a run that finished
  in the last 15 minutes.
- **13% of test-lane publishes came back as a bare `failed`.** Mined from real lane output:
  server-side compile failures, a version block in a wording the regex did not know (so no
  `nextScratchVersion` was offered), "in use by another tenant", object-ID conflicts, failed
  upgrades. `lane.py` now names them (`publish-<cause>` in telemetry) and returns a `hint`.
- **The conductor is the most expensive agent** — a median of 187 turns at ~200k tokens each
  on the transcripts measured, with `sleep`/polling loops, one Bash call per git command and
  translation work done by the orchestrator itself. Its definition now says so in numbers,
  and it no longer has the translation tools.

## Quality metrics

`hooks/hooks.json` wires a `SubagentStop` hook (`tools/metrics/capture_subagent.sh` →
`parse_subagent.py`) that turns the symbolic markers the agents emit — the implementer's
`📚 bcq {applied}/{prescribed}`, its `### Knowledge Deviations`, the review's
`**BCQuality accounting:**` block — into JSONL records. `/bc-dev:al-metrics` aggregates them
via `tools/metrics/report.py`.

**Efficiency metrics (8.0).** The same SubagentStop record now carries a `usage` block parsed
from the subagent's own transcript (`tools/metrics/usage.py`: tokens incl. cache, turns,
wall-clock, tools by name, al-mcp verbs, builds, whole vs ranged reads, skills, spawns) for every
bc-dev agent plus `other`. A `SessionEnd` hook (`session_end.py`) emits `AldcSession` — the whole
session incl. subagents, and tokens per changed AL line when a conductor run finished.
`emit.py` is the script-side door: `AldcRun` (conductor), `AldcLane` (test lane), `AldcRead`
(read-guard), `AldcHook`. `/bc-dev:al-metrics` prints an EFFICIENCY section with a USD estimate
from `prices.json`; KQL E1–E5 in `tools/metrics/azure/queries.kql`.

The `SessionStart` dispatcher also runs a heartbeat (`tools/metrics/heartbeat.sh` →
`heartbeat.py`) that reports `bc-dev`'s own version as an `AldcHeartbeat` event — immediately
when the version on that machine changed since last seen (an upgrade), otherwise at most
once a day. This is how "what does everyone actually have installed" gets answered without
waiting for anyone to run a review.

Both paths send through `tools/metrics/appinsights.py`, which resolves the connection string
itself (`resolve_connection_string()`): an explicit arg, then `$APPLICATIONINSIGHTS_CONNECTION_STRING`,
then `tools/metrics/appinsights.connection` shipped with the plugin — the file that makes
telemetry "install itself" once DSC pastes the estate's connection string into it and
commits. `$ALDC_METRICS_APPINSIGHTS_DISABLE=1` overrides all of that to nothing, per machine.

Constraints to respect when editing any of this:

- **The markers are a contract.** Change the shape of a symbolic line in an agent and you
  break the parser silently — it will just stop matching. `tools/metrics/test_metrics.sh`
  (parser + appinsights + heartbeat self-tests together) carries fixtures of every marker;
  update them in the same commit.
- **`appinsights.py` mirrors every event into Azure.** Its envelope field names were read out
  of Microsoft's generated model, not guessed, and its self-test asserts them. `send_event()`
  is the generic primitive both `AldcPhase` (`send()`) and `AldcHeartbeat` (`heartbeat.py`) go
  through — a new event type calls it directly rather than growing `send()`'s AldcPhase-shaped
  `_props`/`_measurements`.
- **The record must never carry free text.** Only counts, an enum-checked verdict, and paths
  matching `(microsoft|community|custom)/knowledge/…`. Several of the self-test's assertions
  exist purely to prove no customer path and no message body leak into a record or an
  envelope. Do not relax them.
- **`appinsights.connection` carries a live write-key for the DSC estate's Application
  Insights resource (`rg-aldc-metrics-weu`).** It is DSC-owned configuration, not a
  read-access secret (see the file's own header and `tools/metrics/azure/README.md`), but
  it still only belongs in this private repo — never copy it into a public fork or a
  customer-facing distribution of the plugin.

## Rules Injection

`/bc-dev:al-initialize` installs two tiers. **`.claude/rules/`** (auto-loaded, path-scoped to
`**/*.al` and `**/app.json`, so it reaches the main session and every subagent that touches AL):
`rules-floor-cheatsheet.md`, `compiler-authority-protocol.md`, `tool-failure-protocol.md`,
`agent-contract.md` — about 17 KB. **`.claude/aldc-rules/`** (on demand): the seven `al-*.md`
domain files and `al-agent-toolkit.md`, read only when a cheat-sheet line is not enough. Before
8.0 the domain files sat in `.claude/rules/` and loaded everywhere (~90 KB per AL-touching
agent); the SessionStart hook `tools/rules/precondition_hook.sh` detects that layout and nudges
a re-run of init, which migrates it. It also reports "not installed" and never blocks.

Because the floor auto-loads, al-conductor no longer pastes it into Task prompts — it pastes the
four files only when the project has not been initialized.

## Targeted reads

`agents/al-file-reader.md` (Haiku) returns exact line ranges for a question over large files;
`tools/read-guard/` (PreToolUse on Read/Bash/PowerShell, routed by `tools/hooks/pretooluse.sh`) denies a whole-file read of a
source file over `ALDC_READ_MIN_LINES` (350) in an AL workspace — the first two attempts; a third
identical one is the escape. Modeled on Spotify's "shunt" bulk-reader. Kill switch
`ALDC_READ_GUARD_DISABLE=1`.

**Editing does not need a full read.** Claude Code's `Edit` (and `Write` over an existing file)
only requires that the file was `Read` at all: a 5-line ranged read is enough, also for an edit
elsewhere in the file (verified 2026-11 in this harness). Up to 8.x the guard, the agent contract
and this file all said the opposite ("Edit needs one full read — repeat the read"), so every
denial was answered by reading the whole file again: thousands of whole reads, five
`al-file-reader` calls. Don't reintroduce that sentence anywhere.
