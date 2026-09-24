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
- **No usable configuration** → ask the user to either add one to `.vscode/launch.json` (then
  re-run `configs`) or explicitly accept that **no tests will be run**. If they accept, the run
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

## 3. Read the results — classifications, not log scraping

`publish.result`:

| result | meaning | action |
|---|---|---|
| `published` | ok | continue |
| `already-current` | this exact package is already there | continue (not an error) |
| `target-not-allowed` | app target not allowed on this env (OnPrem app on SaaS) | stop; tell the user; pick another config |
| `auth-required` | no cached AAD token | ask the user to run `! al auth login` once, then retry |
| `tool-blocked` | TLS/proxy/timeout signature | TOOL_BLOCKED per tool-failure-protocol — stop |
| `failed` | anything else; `reason` has the server's text | treat as a real defect of the build |

`run`: `ok` is true only if at least one test executed and none failed. `notFound: true` on a
codeunit means the test app is not published (or was rejected) — a failed lane run, never a
pass. `failures[]` names failing methods; map each codeunit back to the work package that
owns it (the plan lists codeunit → WP).

## 4. RED/GREEN honestly

- New objects: RED is compile-level (the test references symbols that do not exist yet).
  Do not publish just to watch it fail.
- Changed behavior (bug fix, altered logic): RED must be a **real** lane run of the new test
  against the unfixed code, before the fix is merged.
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
