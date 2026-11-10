---
name: skill-test-lane
description: Run AL unit tests against the ONE shared Business Central test environment without trampling other runs — pick the environment from .vscode/launch.json, take the lane lock, publish app + test app, run the test codeunits, parse results, release. Use whenever tests must actually execute (al-conductor after each wave, al-developer when asked to run tests), or when a publish/test run collides with another session.
---

# Test Lane

Most projects have exactly one environment that can run tests. Parallel work packages, a second
Claude session or another developer's agent on the same machine would otherwise publish over
each other mid-run. Every publish + test sequence therefore goes through
`tools/testlane/lane.py`, which serializes access with a lock keyed by the environment identity.

`L="${CLAUDE_PLUGIN_ROOT}/tools/testlane/lane.py"` — every command prints one JSON line.

## 1. Choose the environment (once per run, human decision)

```bash
python "$L" configs <test-project-dir>      # e.g. app-test
```

- Show the user the `configurations` (name · envType · where) and ask which one to run tests
  on. `compatible: false` means the test app's `app.json` `target` (OnPrem/Internal) will be
  rejected by that environment (a SaaS sandbox) — say so instead of offering it as a choice.
- An OnPrem (Docker) configuration carries `reachable`; an unreachable one is not usable (its
  container does not exist or is stopped).
- Every configuration carries `lock` — same shape as `status`: `{"locked": false}`, or
  `locked: true` with `holder` (pid/session/host/since), `ageS` and `stale` (older than 30 min,
  recovered on the next `acquire`). A held lock is not a reason to skip tests: `acquire --wait`
  queues behind it. Show it next to the name so the user picks knowing.
- **No usable configuration** → offer, in this order: (1) **create one with the repo's AL-Go
  script** when `devEnv.suggest` is true (`bc-dev:skill-al-go-devenv` — one UAC click, ~20–40 min
  unattended, `devEnv.recommended` says local vs cloud); (2) add a configuration to
  `.vscode/launch.json` by hand (then re-run `configs`); (3) explicitly accept that **no tests
  will be run**. If they accept, the run
  records `lane=skipped` and every report says **tests not executed** — never PASS.
- The chosen name is the authorization for publish + run against that environment for this
  run only. al-conductor writes it into `{req}.plan.md` (`**Test environment:**`) so a resumed
  run does not ask again.

## 2. One lane cycle

```bash
python "$L" prepare <test-project-dir> "<config name>"   # -> scratch, envKey
python "$L" acquire <envKey> --wait 900                  # blocks while another run holds it
python "$L" publish <scratch> <base-app .app>            # dependency order: base app first
python "$L" publish <scratch> <test-app .app>
python "$L" run     <scratch> <codeunit-id> [<id> ...]   # the wave's test codeunits
python "$L" release <envKey>                              # ALWAYS — also after any failure
```

- **Build first, publish the fresh `.app`.** Compile both projects (all analyzers on) into the
  output folder you then publish from; never publish a stale `.app` from the project folder.
- **Release is not optional.** If anything between acquire and release fails, release anyway,
  then report. A dead holder is recovered automatically after 30 minutes (`--stale`).
- `acquire` returning `acquired: false` after the wait → report who holds it (`holder`) and
  stop; do not force it (`status <envKey>` shows the holder at any time).

### Scratch version — bump the revision, never the build

The environment the lane uses is often also the AL-Go `DeployTo` target of `main`, and AL-Go
CI builds `major.minor.<CI/CD run number>.0`. A scratch build published as `X.Y.(N+1).0` takes
the number the **next CI run** will produce: BC keeps every uploaded `.app` per App ID +
version, so that CI deploy is rejected for good, and every older CI build is now "below an
installed version" too. The sandbox is left without the app until a later CI run (#89).

- Publish first with the version as it is. When BC refuses it, `publish` returns
  `version-below-installed` or `version-already-uploaded` with `blockingVersion` and
  `nextScratchVersion`. Set **both** `app.json` files (app and test app) to
  `nextScratchVersion`, rebuild, publish again.
- `nextScratchVersion` keeps major.minor.build of the blocking build and adds 1 to the
  **revision**: installed CI `28.20.80.0` → scratch `28.20.80.1`, then `.2` on the next fix
  loop. It is above the installed build (publish accepted), below the next CI build
  `28.20.81.0` (CI deploy not blocked), and never a number CI uploads.
- Never compute a version yourself as build + 1, and never take "the smallest version that
  publishes" from a repo's CLAUDE.md as license to change the build number.
- **The scratch version is never committed.** Restore the `version` field of both `app.json`
  files before the commit (`git checkout -- <app.json>` only when nothing else in that file
  changed; otherwise edit the field back).
- **Cleanup.** The AL CLI has no uninstall/unpublish verb, and the agent does not mint tokens
  for the BC automation API to do it. With revision versions there is usually nothing to
  clean: the next CI build is higher and upgrades over the scratch build. If the user wants
  the environment back on the CI build right away, tell them to uninstall and unpublish the
  scratch versions in **Extension Management** (test app first, then the app), and list the
  versions the lane published this run.

## 3. Read the results — classifications, not log scraping

`publish.result`:

| result | meaning | action |
|---|---|---|
| `published` | ok | continue |
| `already-current` | this exact package is already there | continue (not an error) |
| `version-below-installed` | a higher version (`blockingVersion`) is installed | set both `app.json` to `nextScratchVersion`, rebuild, publish again (§2 Scratch version) |
| `version-already-uploaded` | a different `.app` with this App ID + version was uploaded before | same: `nextScratchVersion`, rebuild, publish again |
| `target-not-allowed` | app target not allowed on this env (OnPrem app on SaaS) | stop; offer a local container via `bc-dev:skill-al-go-devenv`, or pick another config |
| `auth-required` | no cached AAD token | ask the user to run `! al auth login` once, then retry |
| (run) `UserNotAuthenticatedException` | UserPassword server, no credential in the AL CLI's cache | `tools/testlane/save-onprem-credentials.ps1` (see `skill-al-go-devenv` §3) |
| `tool-blocked` | TLS/proxy/timeout signature | TOOL_BLOCKED per tool-failure-protocol — stop |
| `server-compile-failed` | the server could not compile the package against what is installed there | a dependency is missing or older on the environment, or symbols are newer than the environment: check installed dependency versions, refresh symbols from this environment, rebuild, publish again |
| `in-use-elsewhere` | another tenant on the same server has this exact version installed | bump the scratch revision in both `app.json`, rebuild, publish again |
| `object-id-conflict` | an object ID is already taken by another installed app | fix the ID in the source; do not retry |
| `scope-conflict` | already deployed in the other scope (global vs per-tenant) | stop; ask the user which environment to use |
| `upgrade-failed` | data upgrade or schema synchronization failed | a real defect of the change: read `reason` |
| `environment-not-found` | the server does not know this environment name | re-check the configuration picked for the lane |
| `failed` | anything else; `reason` has the server's text | treat as a real defect of the build |

Every named cause comes with a `hint` in the payload — follow it instead of retrying the same
publish.

`run`: `ok` is true only if at least one test executed and none failed. `notFound: true` on a
codeunit means the test app is not published (or was rejected) — a failed lane run, never a
pass. `failures[]` names failing methods; map each codeunit back to the work package that
owns it (the plan lists codeunit → WP).

## 4. RED/GREEN honestly

- New objects: RED is compile-level (the test references symbols that do not exist yet).
  Do not publish just to watch it fail.
- Changed behavior (bug fix, altered logic): RED must be a **real** lane run of the new test
  against the unfixed code, before the fix is merged.
- New entry point with dependent tests downstream (a page action, subscriber or public
  procedure that several new tests go through): write the **first** test that exercises it,
  take it RED (per the two cases above) and then GREEN on a **real lane run**, and only then
  write the tests that depend on it. A clean compile proves nothing about an entry point that
  never ran — otherwise every dependent test fails at the same line on first run. Standalone
  work (al-developer) only; inside al-conductor the wave's lane run plays this role.
- GREEN is a lane run of the wave's codeunits; the final run before completion runs **all**
  test codeunits of the test app.

## 5. Metrics

`acquire`, `publish` and `run` emit `AldcLane` events themselves (lock wait, publish/run
seconds, pass/fail counts) — nothing to do. The conductor's `AldcRun` event carries
`lane=ran|skipped`.

## Limits

- Serializes runs on **one machine**. Two developers on different machines sharing one
  environment are not covered — agree on who owns the environment, or use one each.
- The AL CLI lower-cases its options, so the lane targets an environment only through the
  scratch project's single-configuration `launch.json`. Don't try `--environmentName` flags.
