---
name: skill-gitcloner
description: Drive GITCloner (DSC's repo/workspace tool, GITCloner.exe on PATH) from an agent with its --json CLI. It downloads the AL symbols of every app in a workspace from one source in a single command (Microsoft feed per country, or a sandbox), reports which symbols are missing for each app, publishes a whole workspace in dependency order, finds any DSC-Group-Srl repo and where it is cloned locally, and clones one. Use when symbols are missing or stale across several projects, after switching localization (IT/CH/W1), when a fresh clone or worktree has no .alpackages, when al_downloadsymbols is stuck on the wrong project, when you need the source of a dependency app (another DSC repo), or when the user asks to publish a whole workspace to a sandbox.
---

# GITCloner for agents

GITCloner is the DSC tool that clones the `DSC-Group-Srl` repos and generates the
customer/product `.code-workspace` files. From 2.7 it has an agent surface: every command below
takes `--json`, asks nothing, writes progress to **stderr** and prints **only** one JSON object on
**stdout**, `{ "ok": true|false, ... }`. Exit code 1 means `ok` is false. On failure there is also
`error`, plus whatever partial result exists.

Read stdout and ignore stderr unless something failed.

## 0. Is it there?

```bash
GITCloner --version        # needs 2.7.0 or later; installed to C:\Program Files\GITCloner (on PATH)
```

- **Not found:** tell the user GITCloner is not installed (release `GITCloner.zip` from
  `DSC-Group-Srl/git-cloner`) and fall back to `al_downloadsymbols` (`skill-al-mcp-workspace`).
  Don't try to install it yourself.
- **Older than 2.7.0:** `--json` doesn't exist yet. GITCloner updates itself when the user opens
  it, so ask them to open it once (`! GITCloner`, then Esc) and retry.

Quote every path. The workspace files are usually in `D:\repos\VSCode Workspaces\` (see §5).

## 1. Inspect before downloading (read-only, instant)

```bash
GITCloner al-projects "<file.code-workspace | repo or project folder>" --json
```

| Field | Meaning |
|---|---|
| `projects[]` | Apps in **dependency order** (compile/publish order). Each has `path`, `packageCachePath` (`.alpackages` or `al.packageCachePath`), `symbolFiles`, `symbolSource` (where its current symbols came from, or `null` if unknown) |
| `projects[].dependencies[].resolution` | `workspace` (another app in the scope provides it), `symbols` (a `.app` in the cache satisfies the minimum version), `outdated` (`.app` present but older than the minimum), `missing` |
| `projects[].missingSymbols` | Everything without a usable `.app`, including the implicit `Microsoft Application` / `Microsoft System` |
| `symbolsComplete` | `true` means every app has what it needs, so you don't need to download anything |
| `sourcesInUse` | e.g. `{ "global:it": 3, "env:<tenant>/sandbox-ch": 1 }`. More than one key means mixed localizations, which is a classic cause of odd compile errors |
| `environments[]` | Deduplicated `launch.json` configurations (`name` is what `al-publish --config` takes) |

`al-projects --tracked --json` scans **every repo the user has cloned with GITCloner**. Use it to
find a dependency app's source locally by `id` or `name`.

## 2. Download the symbols of a whole workspace

```bash
GITCloner al-symbols "<workspace|folder>" --country it --json          # Microsoft feed: no login
GITCloner al-symbols "<workspace|folder>" --tenant <t> --environment-name <env> --json   # sandbox
```

It runs `al downloadsymbols` per app, into each app's own cache, all from **the same source**.
The first app runs alone (so a login happens at most once) and the rest run in parallel. Each cache gets a
`.gitcloner-symbols.json` marker recording the source. It's faster and more reliable than
`al_downloadsymbols` per project, and it avoids that tool's stuck-`projectPath` bug.

**Choosing the source:**

1. Already decided? Use `sourcesInUse` from §1 if every app agrees. Otherwise use the AL-Go `country` in
   `.AL-Go/settings.json`, or ask the user. Never guess between IT and CH: the files have the same
   names and a wrong localization compiles against the wrong Base Application.
2. **Feed (`--country it|ch|w1|<iso2>`)** has Microsoft apps and **AppSource apps, including DSC's
   own AppSource apps** (Dyna License, …). It needs no authentication, so try it first.
3. **Sandbox (`--tenant --environment-name`)** is needed for PTE / non-AppSource DSC apps, which
   only exist where they were published. Take tenant and environment from `environments[]` in §1.
   This needs a Microsoft login.

**Mode:** `--clean` empties every app's `.app` files and downloads them again (required when switching
localization or source). `--missing-only` keeps what is there. With neither, it cleans only when some app's
symbols came from a different source.

**Result:** `projects[]` with `ok`, `downloaded`, `message`, `warnings`. On the feed, a warning about a
dependency it doesn't have means that dependency is a PTE/DSC app: switch that workspace to a
sandbox source.

**Authentication failure** (`authRequired: true`): the AL CLI needs an interactive browser login
that you can't do. Show the user `loginCommand` and ask them to run it with `!` (e.g.
`! "<al.exe>" auth login --tenant <t>`), then retry the same command. Don't loop.

**Timing:** a feed download is ~15 s per app; a big workspace or a sandbox takes minutes. Use a
Bash timeout of 600000, or `run_in_background` for more than about 10 apps. The first run on a machine
may install the .NET 10 SDK and the AL CLI (winget/NuGet), which takes a few minutes, once.

**After downloading:** compile again (`al_compile`, or `al workspace compile <workspaceFile>` for
several projects). If al-mcp still shows the old symbols, re-run `al_addproject` on the
canonical path (`skill-al-mcp-workspace` Gotcha 4). GITCloner uses a private copy of the AL CLI
when al-mcp is holding the global `al.exe`, so it doesn't conflict with the running MCP server.

## 3. Publish a whole workspace (HITL)

```bash
GITCloner al-publish "<workspace|folder>" --config "<launch.json configuration name>" --json
```

It compiles every app in dependency order (each app sees the `.app` files its dependencies just
produced), then runs `al publishapp` one app at a time. Options: `--skip-compile` publishes the
`.app` files already in place, and `--schema-update-mode ForceSync` is for sandboxes only and can
destroy data.

- **This deploys to a live tenant.** Run it only when the user explicitly asked for this deployment,
  and confirm the configuration name first. A **Production** configuration refuses to run
  without `--force`. Never pass `--force` on your own; it needs the user's explicit "yes,
  production".
- **It isn't how tests run.** Tests go through the test lane only (`skill-test-lane`).
- **Result:** `apps[]` with `status` (`published`, `compiled`, `failed`, `skipped`), plus `logDir`
  and `reportFile`. On failure, `failure` gives `{kind: compile|publish, app, path, message,
  errors[]}`. Read `reportFile` (it has the environment, versions, dependency/symbol presence, git
  state, the exact commands and their output) before diagnosing. An authentication error means the
  same thing as in §2: ask the user to log in.

## 4. Find a repository, and clone one

```bash
GITCloner repos "<query>" --json [--limit 20] [--refresh]
```

The query uses the GitHub-views syntax: free text (name/description), `props.customer:"X"`,
`props.product:"Dyna License"`, `props.business-unit:"Business Central"`, `language:AL`,
`is:cloned`, `archived:false`, `OR` between groups. Each repo has `businessUnit`, `customer`,
`customerReference[]`, `product`, `htmlUrl`, **`localPath`** and **`cloned`**. `localPath`
is where it is cloned, or where `clone-repo` would put it. The catalog cache is reused for 12 h
(`--refresh` reloads it from GitHub; offline, it falls back to the old cache).

Typical uses: you need the source of a dependency (an app in `app.json` → `dependencies` that
lives in another DSC repo), or the user names a customer or product and you need its repos.

```bash
GITCloner clone-repo <repo-name> [<repo-name> ...] --json
```

Clones the repo, or pulls it if it already exists, into the user's standard folder layout. The
result is `repos[]` with `path`, `state` and `workspace` (its `.code-workspace` if it has one).
This writes outside the current project, so do it when the task needs that source and say so in
one line. Read the cloned code; don't edit another repo unless the user asked for it.

## 5. Other read-only data

- `GITCloner workspaces --json`: the user's tracked customers/products with their repo paths,
  and every generated `.code-workspace` (`file`, `owner`, `label`). Use it to find the workspace
  file that contains the current repo before §1–§3.
- `GITCloner agents --json`: Claude Code sessions on this PC and the team's (conductor waves, WPs,
  test-lane locks). You'll rarely need it.

## Don'ts

- Don't run GITCloner without `--json` from an agent. Without a TTY it doesn't prompt, but you
  lose the structured result.
- Don't edit `%APPDATA%\GITCloner\usersettings.json` or the `.gitcloner-symbols.json` markers.
- Don't use the interactive menu commands (`clone-customer`, `update`, `remove-*`,
  `assign-product`). They clone or delete in bulk, or write GitHub custom properties. If the
  user wants one, tell them the command and let them run it.
