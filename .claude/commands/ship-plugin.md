---
description: Ship bc-dev for testing - bump version, push main, run the marketplace sync, bump the marketplace entry on the sync branch, optionally close an issue
argument-hint: "[version | major | minor | patch] [#issue]"
---

Ship the current `claude-plugin/` changes so the user can install bc-dev from the marketplace
sync branch. Arguments: `$ARGUMENTS`. Both are optional:
- a version: explicit (`8.6`), or `minor` (the default, `8.5` → `8.6`), `major` (`8.5` → `9.0`),
  or `patch` (`8.5` → `8.5.1`, `8.5.1` → `8.5.2`). bc-dev versions are normally two-part, so a
  feature gets `minor` and a small fix gets `patch`.
- an issue on the marketplace repo (`#60`) that this ship fixes.

Constants:
- source repo: this one, branch `main`. The version lives in `claude-plugin/.claude-plugin/plugin.json`.
- marketplace repo `M=DSC-Group-Srl/dscgroup-bc-nav-agentic-dev`, base branch `bc`.
- sync workflow `bc-dev-upstream-drift.yml` ("bc-dev Plugin Upstream Sync"). It mirrors
  `claude-plugin/` into `plugins/bc-dev/` on branch `sync/bc-dev-plugin` and opens or updates a PR
  into `bc`. **Each run recreates that branch from `bc`**, so the marketplace bump below is always
  re-applied after the run, never before.

## Steps

Show the user the plan in one short block (new version, issue if any) before step 2. Pushing
and dispatching are what they asked for by calling this command, so don't ask again after that.

1. **Pre-flight.**
   - `git status` must be on `main`. Uncommitted changes outside `claude-plugin/` and `.claude/`:
     stop and ask.
   - `node scripts/sync-claude-workspace.js`, then `node scripts/sync-claude-workspace.js --check`.
   - If any file under `claude-plugin/tools/metrics/` changed since `origin/main`, run
     `bash claude-plugin/tools/metrics/test_metrics.sh` and stop if it fails.

2. **Bump and push the source.**
   - Read the current version from `plugin.json`, compute the new one, and write it back.
   - If there is uncommitted work, commit it together with the bump. Write a conventional message
     that describes the change and ends with `bump bc-dev to <new>`, plus `Fixes <M>#<n>` when an
     issue was given. Nothing to commit besides the bump: `chore: bump bc-dev to <new>`.
   - `git push origin main`.

3. **Run the marketplace sync.**
   - `gh workflow run bc-dev-upstream-drift.yml -R $M`, then find the run id with
     `gh run list -R $M --workflow bc-dev-upstream-drift.yml --limit 1`.
   - `gh run watch <id> -R $M --exit-status`. If it fails, show
     `gh run view <id> -R $M --log-failed | tail -40` and stop.
   - Check the sync branch picked up the new version:
     `gh api "repos/$M/contents/plugins/bc-dev/.claude-plugin/plugin.json?ref=sync/bc-dev-plugin" --jq .content | base64 -d`.

4. **Bump the marketplace entry on the sync branch**, not on `bc`.
   - Shallow-clone the sync branch into the scratchpad:
     `git clone --depth 1 -b sync/bc-dev-plugin https://github.com/$M.git <scratch>/mkt`.
   - In `.claude-plugin/marketplace.json`: set the `bc-dev` plugin entry's `version` to `<new>`,
     and bump `metadata.version` by one minor step (`6.25` → `6.26`). Edit only those two
     values; use a JSON-aware edit (node or jq) or check the diff by eye.
   - Commit `chore(marketplace): bc-dev <new>` (with the attribution trailer) and push to
     `sync/bc-dev-plugin`.

5. **Close the loop.**
   - `gh pr list -R $M --head sync/bc-dev-plugin` and give the user the PR URL.
   - If an issue was given, comment on it with what changed (1–3 sentences), the source commit
     link, the version, and "install from `sync/bc-dev-plugin` (#<PR>) to test". The
     `Fixes <M>#<n>` trailer already closed the issue across repos when `main` was pushed, so
     don't claim it closes later, and don't close or reopen it yourself.
   - Tell the user how to test: install/update bc-dev from the `sync/bc-dev-plugin` branch. The
     test project is `D:\repos\DSC GROUP\Business Central\dyna-arx` (sandbox
     `Products-Dev-Test`). Stash their uncommitted changes there before testing.

Report at the end: the new version, the source commit, the sync run, the marketplace commit, the
PR URL, and the issue comment URL if any.
