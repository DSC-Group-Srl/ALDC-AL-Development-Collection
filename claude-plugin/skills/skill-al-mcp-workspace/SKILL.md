---
name: skill-al-mcp-workspace
description: "Operating the al-mcp AL CLI tool correctly — full tool capability map, and multi-project workspace troubleshooting (app + test app + performance app). Use when a build/compile fails for no visible reason, symbols seem stale or out of date, you're working across sibling AL projects, or you're generally unsure what al-mcp/the al CLI can actually do here."
---

# Skill: Operating al-mcp & Multi-Project AL Workspaces

## Purpose

This plugin runs in the **Claude Code harness**, not VS Code — the VS Code AL extension commands (`AL: Publish`, `AL: Download Symbols`, …) and Copilot `#…` context-variables do not exist here. The real surface is **al-mcp**, the official AL CLI's own MCP server (`al launchmcpserver`), plus the bare `al` CLI via `Bash`. This skill is the accurate, verified reference for what these can do, and — the most common failure mode — how to make a multi-project workspace (base app + test app + performance app) actually see each other's changes.

Every behavior below was verified by hands-on testing against a live `al-mcp` session, not assumed from tool descriptions (some tool *descriptions* turned out to be misleading — noted where relevant).

## When to Load

Load this skill when:
- A build/compile reports failure and it's not obvious why (especially: `al_getdiagnostics` shows zero errors right after `al_build` reported "Build failed")
- Working with more than one AL project in the same session (app + test app, app + performance app, or any dependency chain)
- A symbol that "should" be there is reported missing, especially right after editing a *different* project
- You're about to call `al_downloadsymbols`, `al_build`, or `al_addproject` with a path that isn't obviously already in canonical form
- You're unsure whether a runtime step (publish, run tests, download symbols, debug) has an agent tool at all

## Tool capability map

| Need | Tool |
|------|------|
| Compile / validate (no `.app`) | **al-mcp** `al_compile`, or `Bash: al compile` |
| Build / package `.app` (single project) | **al-mcp** `al_build` (`scope='current'`, default), or `Bash: al compile` |
| Build a multi-project workspace **with automatic cross-project symbol resolution** | `Bash: al workspace compile <workspaceFile>` — **not** `al_build scope='all'`. See Pattern 1, it's the whole point of this skill. |
| Generate a workspace manifest from folders | `Bash: al workspace create <workspaceFile> <folder1> <folder2> ...` |
| Map a workspace's dependency graph | `Bash: al workspace map <workspaceFile> <outputFile>` — markdown + mermaid graph |
| Register a project in the MCP server's live session | **al-mcp** `al_addproject` — **canonical long-form absolute path only** (Gotcha 1) |
| Download symbols | **al-mcp** `al_downloadsymbols` — `globalSourcesOnly=true` needs no auth; MCP-only, no bare CLI verb (Gotcha 2 applies) |
| Find objects/members | **al-mcp** `al_symbolsearch` (`filters.kinds`, `filters.memberKinds`, `filters.scope='project'\|'dependencies'\|'all'`) |
| Find relations (extends, implements, source-table, …) | **al-mcp** `al_symbolrelations` |
| Inspect dependencies | read `app.json` `dependencies` + **al-mcp** `al_getpackagedependencies` |
| Inspect a page's control/action tree | **al-mcp** `al_inspectpage` |
| Search/write translations | **al-mcp** `al_searchtranslations` / `al_writetranslation` |
| Diagnostics | **al-mcp** `al_getdiagnostics` (by `filePath`/`folderPath`/`projectPath`) — but see Gotcha 3, it can disagree with the build result |
| Publish/deploy | **al-mcp** `al_publish` / `Bash: al publishapp` exist, but deploy to a live BC tenant — HITL by default, don't call unprompted |
| Run tests | **al-mcp** `al_run_tests` / `Bash: al runtests <codeunitId>` exist, but run against a live server — confirm target with the human first |
| Auth | **al-mcp** `al_auth_login`/`al_auth_logout`, or `Bash: al auth login`/`logout` — usually unnecessary, `useInteractiveLogin=true` is the default and handles it inline |
| Debug / snapshot / CPU profile | VS Code only — no agent tool here |

## Core Patterns

### Pattern 1: Build a multi-project workspace (the actual fix for "symbols don't update")

**Do not reach for `al_build scope='all'` expecting it to rebuild a sibling test app when you change the base app.** Verified behavior: `al_build`'s `scope='all'` builds the *target* project plus whatever *it itself* depends on (upstream) — it does not build downstream dependents, and each project still reads/writes its **own isolated** `.alpackages` folder. Editing the base app is invisible to the test app's compiler afterward; the tool description ("compiles entire workspace with dependencies") is more optimistic than what it actually does.

**What actually works — `Bash: al workspace compile`:**

```bash
# Once, to generate the manifest (or reuse the repo's existing .code-workspace):
al workspace create MyProject.code-workspace app app-test app-performance

# Every time you want a build that keeps every project in sync:
al workspace compile MyProject.code-workspace
```

This compiles every project in the manifest **in dependency order**, sharing **one package-cache/output folder at the workspace root** (not each project's own `.alpackages`). Because the base app's freshly-built `.app` lands in the same shared folder the test app reads its dependencies from, the test app sees the base app's latest change **in the same command** — no manual symbol copy, no `outputPath` trick, no separate download step. This was confirmed end-to-end: editing a base-app codeunit and immediately running `al workspace compile` picked it up in the dependent project on the very next call.

If you don't have (or don't want) a `.code-workspace` file, or you're doing a single quick one-off bridge rather than a repeatable workspace build, use Pattern 2 instead.

### Pattern 2: One-off bridge via al-mcp (no shell-out, single dependency hop)

1. Rebuild the base app: **al-mcp** `al_build` with `scope='current'` and `outputPath` set to the dependent project's `.alpackages` folder — **`outputPath` must be a directory, not a filename**; the tool names the file itself. Passing a filename creates a wrongly-nested subfolder.
2. Only then does the dependent project's `al_build`/`al_compile` see the change.
3. This does not scale past one hop and does not stay in sync automatically — prefer Pattern 1 for anything beyond a single quick check.

### Pattern 3: Live cross-project symbol lookup (no rebuild needed at all)

`al_symbolsearch` / `al_symbolrelations` with `filters.scope='all'` (or `'project'`) see **every project registered via `al_addproject`, straight from its current source on disk** — this is genuinely live, no build step involved. Use this for "did I already define this in the other app?" or "what in the test app references this table?" — don't reach for a rebuild just to answer a lookup question. This is a completely different mechanism from compilation (Patterns 1–2); don't conflate the two, and don't expect a `scope='all'` symbol search to mean the projects will *compile* together too.

## Gotchas (verified, not theoretical)

1. **Canonical paths only.** Every `projectPath` argument on every al-mcp tool must be the canonical, long-form absolute path. A Windows short 8.3-alias segment (anything like `~1`, e.g. an abbreviated username or folder) breaks matching: `al_getpackagedependencies` hard-fails ("Project not found"), and `al_build`/`al_compile` can silently evaluate the *entire* session instead of the one project named — so one broken/stale sibling project fails builds of an otherwise-healthy one. If a build fails for no visible reason, resolve the real path first (`(Get-Item $path).FullName` in PowerShell, or `readlink -f`/`realpath` in Bash) and retry before assuming the code is broken.
2. **`al_downloadsymbols`'s `projectPath` can get permanently stuck.** Once it has successfully targeted a project, later calls naming a *different* project can silently report success while `cachePath` in the response still points at the earlier project — and if that earlier project's folder is later deleted, subsequent calls hard-fail referencing the gone path, for the rest of the server's lifetime, regardless of what `projectPath` you pass. **Always check the returned `cachePath` matches the project you intended.** If it's stuck on the wrong (or a deleted) project, don't keep retrying the tool — copy the needed `.app` symbol packages directly into the target project's `.alpackages` via `Bash` instead, or fall back to `al workspace compile`, which doesn't go through this code path.
3. **`al_build` can report failure while `al_getdiagnostics` on the same project shows zero errors.** These two are not always in sync. If this happens, don't trust either one blindly — cross-check with a bare `al_compile` call (which reflects live compiler state) or `Bash: al compile` directly in the project folder.
4. **A project's compiled state can go stale mid-session even when you've done everything right** — e.g. after correctly placing an updated dependency `.app`. If a fix doesn't seem to register, re-run `al_addproject` on that exact project path to force a refresh before spending more turns debugging code that's probably already correct.
5. **There is no `al_removeproject`.** Once a project is added to the session it stays there. Only add projects actually relevant to the current task — an irrelevant broken sibling (e.g. a test app mid-refactor) will keep tainting whole-session builds per Gotcha 1 for the rest of the session. If a session's project set has gotten into a bad state, the clean fix is a fresh session, not fighting the existing one.

## Quick Reference

```bash
# Multi-project build that keeps a base app + test app in sync
al workspace create MyProject.code-workspace app app-test
al workspace compile MyProject.code-workspace

# Map the dependency graph
al workspace map MyProject.code-workspace map.md
```

```
# al-mcp: register projects for live cross-project lookup (canonical paths!)
al_addproject projectPath=<canonical path to app>
al_addproject projectPath=<canonical path to app-test>
al_symbolsearch query="*" filters.scope="all"   # see across every registered project, live from source

# al-mcp: one-off single-hop bridge (no shell-out)
al_build scope="current" projectPath=<base app> outputPath=<app-test's .alpackages DIRECTORY>
```
