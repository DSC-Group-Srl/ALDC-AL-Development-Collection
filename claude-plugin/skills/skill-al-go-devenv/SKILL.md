---
name: skill-al-go-devenv
description: Create a test environment for an AL-Go repo with the scripts AL-Go ships in every template — .AL-Go/localDevEnv.ps1 (local Docker BC container) or cloudDevEnv.ps1 (SaaS sandbox) — non-interactively, then register its credentials so the test lane can publish and run tests without prompts. Use when the test lane reports no usable environment (devEnv.suggest), when a publish is rejected with target-not-allowed (OnPrem test app on a SaaS sandbox), or when the user asks for a local container to run tests.
---

# AL-Go dev environment → test lane

Every AL-Go template repo carries `.AL-Go/localDevEnv.ps1` and `.AL-Go/cloudDevEnv.ps1`.
`localDevEnv.ps1` creates a BC container from the repo's own `.AL-Go/settings.json`
(country, artifact, dependencies), compiles and publishes **every app and test app**, and adds
a matching configuration to `.vscode/launch.json`. That is exactly what the test lane needs.

`T="${CLAUDE_PLUGIN_ROOT}/tools/testlane"`

## When to offer it

- `python "$T/lane.py" configs <test-project>` returns `devEnv.suggest: true` — no configuration
  is both compatible and reachable (a Docker config whose container does not exist counts as
  unreachable).
- `lane.py publish` returns `target-not-allowed` — an `OnPrem`/`Internal` test app on a SaaS
  sandbox. Only a local container can run it.

Offer it as one option next to "add a configuration" and "no tests": *"Create a local test
container with the repo's AL-Go script — one UAC click, ~20–40 min unattended."* Use
`devEnv.recommended`: `local` whenever the test app targets OnPrem/Internal; `cloud` only for a
Cloud-target app on a machine without Docker.

## 1. Preflight (agent, read-only)

- `docker info --format '{{.OSType}}'` must print `windows` (Docker Desktop → *Switch to Windows
  containers*). Not running → ask the user to start it.
- `.AL-Go/settings.json`: note `country`, `appFolders`/`testFolders`, and
  `appDependencyProbingPaths` — dependencies from other repos are fetched with `gh auth token`,
  so `gh auth status` must be logged in with access to those repos.
- Free disk: artifacts + image need roughly 15–25 GB.

## 2. Create (one UAC click)

```bash
pwsh -NoProfile -File "$T/create-devenv.ps1" -RepoRoot <repo root> [-ContainerName <name>] [-Kind local|cloud]
```

- Prints `{ok, pid, log, container, username}` and returns immediately; the elevated window
  runs `localDevEnv.ps1 -containerName … -auth UserPassword -credential … -licenseFileUrl none`,
  which asks nothing. Tell the user to accept the UAC prompt.
- Container name defaults to `<repo>-test`. **Reuse the name the repo's existing Docker config
  already points at** (e.g. `server: http://dyna-arx-test/BC/` → `-ContainerName dyna-arx-test`) so
  that configuration starts working instead of a second one being added.
- Password: `-Password`, else `$ALDC_DEVENV_PASSWORD`, else `P@ssw0rd123` (the container's SQL
  rejects trivial passwords). Local and disposable — never a shared server's credential.
- Wait for the log's marker in the background (`run_in_background`), never with sleep loops:
  `until grep -qa "ALDC-DEVENV-\(DONE\|FAILED\)" "<log>"; do sleep 15; done`. A transient
  `Timeout downloading file` is retried by BcContainerHelper itself — keep waiting.
- `ALDC-DEVENV-FAILED` → show the last ~30 log lines and stop; do not retry blindly.
  AL-Go's script catches its own errors and only prints `Error: …`, so the launcher reads the
  transcript for that line — trust the marker, not the process exit.
- The launcher runs **Windows PowerShell 5.1** on purpose: under PowerShell 7,
  BcContainerHelper's Hyper-V probe (`Get-WindowsOptionalFeature`) fails with "interface not
  registered" / "Interfaccia non registrata" after the image is already pulled.
- A retry after a failure is much faster: artifacts and the BC image stay cached.

## 3. Register credentials for the AL CLI (once per container)

The AL CLI never prompts for a UserPassword login: it reads a per-user protected
`UserPasswordCache.dat` next to its own executable, keyed `<server>_<instance>` (lower-cased).
VS Code keeps a separate copy, so logging in from VS Code does not help the CLI.

```bash
pwsh -NoProfile -File "$T/save-onprem-credentials.ps1" -Server http://<container>/BC/ -ServerInstance BC -Username admin -Password '<password>'
```

It writes one entry through the CLI's own library into every installed `altool` version and
leaves other entries untouched. If the harness blocks it, ask the user to run it with `! `.

## 4. Verify through the lane

```bash
python "$T/lane.py" configs <test-project>        # the container's config: reachable, usable
```

Then one lane cycle (`skill-test-lane` §2) on a single test codeunit. The apps are already
published by the script, so `publish` returning `already-current` is expected.
`UserNotAuthenticatedException` → step 3 was skipped or used a different server URL/instance.

## Notes

- The script edits `.vscode/launch.json` of the app/test projects when it adds a
  configuration — mention it; it is a normal, reviewable change.
- AL-Go recommends a personal wrapper (e.g. `<name>-devenv.ps1` calling `localDevEnv.ps1` with
  your parameters) instead of editing the script, which AL-Go updates overwrite.
- Remove a container when done: `Remove-BcContainer <name>` (BcContainerHelper, elevated).
