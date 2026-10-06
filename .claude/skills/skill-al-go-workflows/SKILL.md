---
name: skill-al-go-workflows
description: How DSC Group runs AL-Go for GitHub on its Business Central repos — PTE (al-pte template) and AppSource/Global (al-appsource template) — the main/test branch model, the nightly Rebuild Test Branch, the PR → test environment → functional test/UAT → merge → release → production flow, every workflow in the repo and when to dispatch it, where each AL-Go setting goes, the secrets each workflow expects (by name), and how to read and fix a failed run with gh. Use whenever the user mentions AL-Go, GitHub Actions/workflows, CI/CD, a pipeline, a failed build or PR check, the test branch, publishing to a test/production environment, creating a release, publishing to AppSource, Template Sync, Update AL-Go System Files, DeployTo/environments settings, appDependencyProbingPaths, signing, or self-hosted runners in a DSC AL repo.
---

# AL-Go workflows — the DSC way

Every DSC AL repo is created from one of two template repos in `DSC-Group-Srl`, both built on
[AL-Go for GitHub](https://aka.ms/AL-Go) (AL-Go-Actions v9.x):

| Template | For | GitHub custom property `app-type` | `.github/AL-Go-Settings.json` `type` |
|---|---|---|---|
| `al-pte` | Per-Tenant Extensions for one customer | `PTE` | `"PTE"` (upstream `microsoft/AL-Go-PTE`) |
| `al-appsource` | DSC products on AppSource (`dyna-*`, …) | `Global / AppSource` | `"AppSource App"` (upstream `microsoft/AL-Go-AppSource`) |

**Identify the flavour before saying anything about a repo**: read `.github/AL-Go-Settings.json`
`type`; AppSource repos also carry `PublishToAppSource.yaml`, `deliverToAppSource` in
`.AL-Go/settings.json`, `app/AppSourceCop.json` and the `CustomJobSignLocal` job in `CICD.yaml`.

Shared layout, from the templates: `app/` (appFolders), `app-test/` (testFolders),
`app-performance/` (bcptTestFolders), `app-pagescripting/*.yml` (pageScriptingTests), `guides/`,
`<repo>.code-workspace`. `.AL-Go/settings.json` sets `"country": "it"`,
`"runs-on": "self-hosted"`, `"githubRunner": "self-hosted"` and the BCPT thresholds.

## 1. Branch model: `main` is the trunk, `test` is rebuilt every night

- **`main`** is the default branch and always production-ready. Direct push is disabled, so every
  change lands through a PR into `main`. The PR has **no merge requirements**: no required
  approval and no required status check. The PR's CI build is *informative*. It runs on every PR
  but doesn't block the merge, and whoever opened the PR decides when to merge. The branch is
  deleted automatically after the merge. (The template README still says "required PR review,
  required CI status check". The deck and the live repos say otherwise. Follow the deck.)
- **`test`** is a throwaway integration branch with no branch protection on it. Only the rebuild
  bot writes to it. `RebuildTestBranch.yaml` runs nightly at 01:00 UTC (and on dispatch). It
  deletes `test`, recreates it from `main`, then merges every open PR that targets `main`, oldest
  first. The script does **not** look at check status, so a PR with a red build is merged too. A
  PR that conflicts or can't be fetched is skipped, the author gets an `@`-mention comment on it,
  and the job summary lists merged and skipped PRs.
- Feature branches are cut from `main` and PR back into `main`. **Never** PR into `test`, base a
  branch on `test` or commit to it: the next night's rebuild throws it away. (A PR whose base is
  `test` shows up as a "Pull Request Build" on `test`. Retarget it to `main`.)
- The company-wide standard says the opposite (`test` default, `main` production only). The
  templates deviate **on purpose** because CI/CD and AppSource delivery are wired to `main`. Do
  not "fix" this. Changing it means rewiring branch protection, the default branch and delivery.

## 2. The lifecycle of a change (DSC "Pipeline CI-CD")

```
integration ready for functional test
   │
   ├─ first time? ── yes ─▶ open PR into main  (/bc-dev:al-pr-prepare)
   │                 no  ─▶ @al-triage on the PR → fix on the SAME branch (PR updates itself)
   ▼
nightly Rebuild Test Branch (or dispatch it)  ──▶  test = main + all open PRs
   ▼
CI/CD on test  ──▶  test environment regenerated (DeployTo<env>, continuousDeployment)
   ▼
functional test (consultant)  /  UAT (consultant + key user)
   ▼
outcome?  KO ─▶ back to the top (it is no longer "first time")
          OK ─▶ the DEV selects the PRs with outcome OK and merges/rebases them into main
   ▼
release + deploy  ──▶  Publish To Environment → production (GitHub environment)
```

How each step maps to the repo:

1. **PR.** The developer prepares it with `/bc-dev:al-pr-prepare`. `PullRequestHandler.yaml`
   ("Pull Request Build") builds it and runs the tests on the PR. The check doesn't block the
   merge, so report a red build to the user explicitly instead of letting it slide. Functional
   validation before release is always the consultant's job, not a code review.
2. **Back from a KO.** Diagnose with `bc-dev:al-triage` against the PR's branch, fix with
   `bc-dev:al-developer` on the same branch, and push. Don't open a second PR. The next rebuild
   picks the fix up.
3. **Test environment.** The intended behaviour is an automatic deploy every night, or a
   manual one when it's needed sooner. `CICD.yaml` deploys to every environment whose
   `DeployTo<env>.Branches` includes the branch being built (see §4). Since 2026-10-05 the
   `al-pte` template ships `CICDPushBranches` `main, release/*, feature/*, test`, and the YAML
   trigger with it, so a synced PTE repo builds `test` on every nightly push. `al-appsource`
   doesn't (AppSource repos have no test environment). **Check before you rely on it**:
   `grep -n "branches:" .github/workflows/CICD.yaml` must list `test`. A branch added to
   `CICDPushBranches` in one repo only reaches the YAML when AL-Go regenerates it, and Template
   Sync puts the template's YAML back (§5), so change it in the template. If it isn't there,
   **dispatch CI/CD on `test`**: `gh workflow run CICD.yaml --ref test`. To put a single PR's build on an
   environment without going through `test`, use Publish To Environment with
   `appVersion=PR_<number>`.
4. **Merge into `main`.** Only PRs whose test outcome was OK. *Merge* = a merge commit;
   *rebase* = the PR's commits replayed onto `main` with no merge commit. Either is allowed, so
   follow what the repo's branch protection allows. The developer does the merge, after the
   human OK. An agent never merges unprompted.
5. **Release and production.** `CreateRelease.yaml` promotes a build to a GitHub release (semver
   tag). `PublishToEnvironment.yaml` deploys it to production through a **GitHub environment**.
   Both are run by hand, and GitHub asks for **no approval**, production included. The developer
   starts them. An agent still asks its user first (§7). AppSource repos deliver with
   `PublishToAppSource.yaml` instead. Release and deploy are separate steps today. Automating
   them (one combined step, scheduled deploys) is still being decided, so don't describe it as
   available. The exact procedure and inputs are in **Releasing to production** below.
6. **Notifications.** Rebuild Test Branch reports skipped PRs only as an `@`-mention comment, and
   a failed pipeline only shows up in Actions. The DSC recommendation: on every repo you work on
   actively, **Watch → All Activity** (or at least Actions), and in
   github.com/settings/notifications turn on the Actions channel. Otherwise a conflicting PR
   silently stays out of `test`.

### Releasing to production (the DSC convention)

Release from `main`, and only after the PRs that passed functional test/UAT are merged. Show the
user the exact commands with the inputs filled in, and dispatch only after a yes.

**Step 1 — Create release** (both PTE and AppSource). DSC always fills the inputs like this:

| Input | DSC value | Why |
|---|---|---|
| `buildVersion` | `latest` (default) | the latest successful CI/CD build of `main` |
| `name` | **`<tag> - <one sentence on what this release does>`**, e.g. `1.4.0 - Credit check on sales orders and posting date fix on returns` | it's what people read in the Releases list. Lead with the version, then a single statement. No bullet list |
| `tag` | the version being released, as semver `Major.Minor.0` | releases move in **0.1.0** steps, so read `version` from `app/app.json` on `main`: `1.4.0.0` → tag `1.4.0` |
| `releaseType` | `Release` | |
| `createReleaseBranch` | `false` (default) | |
| `updateVersionNumber` | `+0.1` | bumps `main` to the next minor (`1.4` → `1.5`) right after the release |
| `directCommit` | `true` | the bump is committed straight to `main`, with no PR |
| `useGhTokenWorkflow` | `true` | `main` blocks direct pushes, and only the `GhTokenWorkflow` app is on the ruleset's bypass list |

```bash
v=$(jq -r .version app/app.json | cut -d. -f1,2)   # e.g. 1.4
gh workflow run CreateRelease.yaml --ref main \
  -f buildVersion=latest -f name="$v.0 - Credit check on sales orders and posting date fix on returns" \
  -f tag=$v.0 -f releaseType=Release -f updateVersionNumber=+0.1 \
  -f directCommit=true -f useGhTokenWorkflow=true
gh run watch <run-id>                                  # wait for it to finish before step 2
gh release view $v.0                                   # the release exists, with its .app files
```

If `tag` already exists, the version on `main` wasn't bumped after the last release. Stop and
tell the user. Never re-tag.

**Step 2 uses `appVersion=current`, never the tag.** `current` is the latest published release.
An explicit `x.y.z` in `appVersion` is **not** looked up as a release tag. AL-Go matches it
against the **build artifact version**, which is `repoVersion` plus the build number
(`<repo>-main-Apps-1.0.11.0.zip`). It is not the tag (`28.0.0`) and not the `app.json` version
(`28.0.11.0`). In a repo whose `repoVersion` doesn't track `app.json`, the tag never matches,
and Deliver/Deploy fails with `Could not find any Apps artifacts for projects *, version 28.0.0`.
Confirm that `current` points at the release step 1 just created before you dispatch:

```bash
gh release view --json tagName,isDraft,isPrerelease   # no tag = the latest release; expect tagName == $v.0
```

If it is not `$v.0` (step 1 hasn't finished, or someone released in between), stop and tell
the user.

**Step 2a — PTE: Publish To Environment** to the customer's production environment.

```bash
gh workflow run PublishToEnvironment.yaml --ref main \
  -f appVersion=current -f environmentName='<Customer>-Production' -f createEnvIfNotExists=false
```

- `environmentName` is the GitHub environment name. It must already exist with its
  `AUTHCONTEXT` and a `DeployTo<env>` whose `Branches` includes `main` and
  `continuousDeployment: false`, so production is never deployed by a push. If it doesn't exist,
  stop: adding an environment is the manual step in **Environments** below. Never
  `createEnvIfNotExists=true` for production.
- Check the run: the `Deploy to <env>` job is green, and it ends with the environment URL.

**Step 2b — AppSource: Publish To AppSource.**

```bash
gh workflow run PublishToAppSource.yaml --ref main -f appVersion=current -f projects='*' -f GoLive=true
```

- **`GoLive=true` ("go live after validation") is the DSC default.** The submission goes live
  by itself once Microsoft's technical validation passes, with no second trip to Partner Center.
- It needs `deliverToAppSource.productId` set (not `<productId>`) and the `AppSourceContext`
  secret. Validation takes hours to days. The run only covers the submission, so tell the user
  the outcome arrives from Partner Center.

### Environments: Dev, Test, Production

| | Dev | Test | Production |
|---|---|---|---|
| **PTE** | local container / sandbox, published by hand from VS Code (or the test lane) | the customer's tenant, published by the pipeline | the customer's tenant, `Publish To Environment` |
| **AppSource** | DSC environments | DSC environments | DSC stops at Partner Center: submission, then Microsoft's technical validation, then the marketplace. Customers install it into their own tenant. Their Dev/Test/Prod is **not** DSC's pipeline |

**Adding a BC environment to a repo is a manual step owned by Tommaso Celano**, and access for
others is being opened gradually. The steps are: the `AUTHCONTEXT` secret (the JSON is in
RoyalTS, folder "DSC GROUP"), the Entra ID app registration enabled on the customer's tenant,
that app added to the **Microsoft Entra Applications** page of every target BC environment, and
the permissions **D365 BASIC** + **D365 EXTEN. MGMT.** Claude never attempts any of these. When
a deploy needs a new environment, say so and point the user to Tommaso.

**Who can do what.** A *Developer* creates branches, opens PRs, merges them into `main` and
starts production releases, with no approval at any step, but can't push directly to `main`. A
*BU Manager* can do all of that and also changes branch protection, custom properties and
permissions. Exceptions to the repository standard go to the BU Manager.

## 3. Workflow catalogue

`Dispatch` = `gh workflow run <file> --ref <branch> -f <input>=<value> …`.

| Workflow (file) | Trigger | What it does | HITL |
|---|---|---|---|
| **CI/CD** (`CICD.yaml`) | push to `main` (PTE template also `release/*`, `feature/*`), dispatch | Build + test all projects, deploy to environments with continuous deployment on that branch, deliver (AppSource), ALDoc. AppSource adds `CustomJobSignLocal` (§6) before Deploy/Deliver | dispatch on `test`: low-risk, still confirm |
| **Pull Request Build** (`PullRequestHandler.yaml`) | PR into `main`, merge queue | Build + test the PR. This is the PR's required check | automatic |
| **Rebuild Test Branch** (`RebuildTestBranch.yaml`) | cron `0 1 * * *`, dispatch | §1. DSC-custom | dispatch: confirm (it force-replaces `test`) |
| **Publish To Environment** (`PublishToEnvironment.yaml`) | dispatch | `appVersion` (`current`·`prerelease`·`draft`·`latest`·`x.y.z`·`PR_<id>`; `x.y.z` is the build artifact version, not the release tag, see §2) to `environmentName` (mask, `PROD*`, `*`); `createEnvIfNotExists` | **always**: it mutates a live tenant |
| **Create release** (`CreateRelease.yaml`) | dispatch | `buildVersion`, `name`, `tag` (semver), `releaseType`, release branch, `updateVersionNumber`, `directCommit`, `useGhTokenWorkflow`. DSC values: §2 *Releasing to production* | **always** |
| **Publish To AppSource** (`PublishToAppSource.yaml`) — AppSource only | dispatch | Delivers `appVersion` (`current` after a release, §2) to Partner Center (`deliverToAppSource.productId`). DSC always sets `GoLive=true` (goes live after technical validation) | **always** |
| **Increment Version Number** | dispatch | `versionNumber` (`+0.1` / `Major.Minor`) for `projects` (`*`), PR or direct commit | confirm |
| **Test Current / Next Minor / Next Major** (`Current.yaml`, `NextMinor.yaml`, `NextMajor.yaml`) | dispatch | Build + test against `////latest`, next minor, next major (`.github/Test *.settings.json`, `versioningStrategy: 15`). Use before a BC upgrade or when a customer moves version | safe to suggest |
| **Create Online Dev. Environment** | dispatch | Creates/reuses a SaaS sandbox and publishes the apps | confirm |
| **Create a new app / test app / performance test app**, **Add existing app or test app** | dispatch | AL-Go scaffolding. DSC templates already ship `app/`, `app-test/`, `app-performance/`, so these are rarely needed | confirm |
| **Deploy Reference Documentation** | dispatch | ALDoc to GitHub Pages. DSC documentation is normally built with `skill-aldoc` / `skill-developer-docfx` | confirm |
| **Update AL-Go System Files** (`UpdateGitHubGoSystemFiles.yaml`) | dispatch | Pulls a newer AL-Go from Microsoft and regenerates workflow YAMLs from settings | **run it in the template, not the app repo** (§5) |
| **Template Sync** (`TemplateSync.yaml`) | cron Monday 05:00 UTC, dispatch | Opens a `[template-sync]` PR from `al-pte`/`al-appsource`. DSC-custom | review the PR like any other |
| **Initialize Template Repository** | first push to `main`, dispatch | One-off: renames `TEMPLATE.code-workspace` → `<repo>.code-workspace`, regenerates app GUIDs, rewrites `.templatesyncignore`, opens PR `chore/initialize-template-repo`. Self-disables afterwards | — |
| **Troubleshooting** | dispatch | AL-Go self-diagnosis. `displayNameOfSecrets=true` shows secret **names**, never values | safe |

## 4. Settings: what goes where

| File / variable | Scope | DSC puts here |
|---|---|---|
| `.AL-Go/settings.json` | project | `country`, folders, `runs-on`/`githubRunner`, `appSourceCopMandatoryAffixes`, `appDependencyProbingPaths`, `deliverToAppSource`, `bcptThresholds`, `repoVersion`. Listed in `.templatesyncignore`: the app team owns it |
| `.github/AL-Go-Settings.json` | repo | **template-owned**: `type`, `templateUrl`/`templateSha`, `CICDPushBranches`, `CICDPullRequestBranches` as the template sets them. Not in `.templatesyncignore`, so Template Sync replaces it every Monday (§5). **Never put per-repo values here** |
| `.github/Test Current|Next Minor|Next Major.settings.json` | per workflow | `artifact` (`////latest`, `////nextminor`, `////nextmajor`), `versioningStrategy: 15` |
| `vars.ALGoOrgSettings` / `vars.ALGoRepoSettings` | org / repo variable | JSON merged on top of the files. Read by every workflow |
| GitHub environment variable `ALGoEnvironmentSettings` | Deploy step only, wins over everything | an environment-specific `DeployTo<env>` (no env name inside the variable) |

Test-environment deploy for a PTE. Put it in **`.AL-Go/settings.json`**, which the repo owns.
AL-Go reads it after the repo settings file, and in DSC's single-project repos that's all the
deploy step needs. (This is how `fujitsu-base`, `martesana-base` and `bigben-base` have it.)

```json
"environments": [ "Customer-Test" ],
"DeployToCustomer-Test": {
  "EnvironmentType": "SaaS",
  "EnvironmentName": "Customer-Test",
  "Branches": [ "main", "test" ],
  "continuousDeployment": true
}
```

The key after `DeployTo` must match the `environments` entry exactly. Deploy authenticates with
the first secret found among `<env>-AuthContext`, `<env>_AuthContext`, `AuthContext`
(environment or repo secrets).

A dependency on another DSC repo (as `dyna-arx` → `dyna-license`) goes in `.AL-Go/settings.json`:

```json
"appDependencyProbingPaths": [
  { "repo": "DSC-Group-Srl/dyna-license", "release_status": "latestBuild",
    "branch": "main", "AuthTokenSecret": "GhTokenWorkflow" }
]
```

Before suggesting any other setting, look it up in the official list,
<https://aka.ms/algosettings> (also `.github/RELEASENOTES.copy.md` in the repo). Don't invent
keys, because AL-Go ignores unknown ones without a warning.

## 5. Template plumbing: why most fixes belong in the template

- **Template Sync replaces files wholesale.** It merges unrelated histories with `-X theirs`
  (no merge base), so any file not listed in `.templatesyncignore` is overwritten with the
  template's copy every Monday. That includes every workflow YAML, `.github/AL-Go-Settings.json`,
  `.vscode/settings.json` and every `.gitignore`.
- So **workflow changes, AL-Go upgrades (Update AL-Go System Files) and trigger changes made in
  an app repo don't last**. Make them in `DSC-Group-Srl/al-pte` / `al-appsource` and let them
  flow out. Changes that are really per-repo go in a file the template doesn't ship (a nested
  `.gitignore`) or in a file listed in `.templatesyncignore` (`app/app.json`, `changelog.json`,
  `.AL-Go/settings.json`, `app/app.ruleset.json`, `app/AppSourceCop.json`, the per-folder
  README/CLAUDE.md). Per-repo AL-Go settings (`environments`, `DeployTo<env>`, dependencies) go in
  `.AL-Go/settings.json`.
- **Review every `[template-sync]` PR before merging it.** `gh pr diff <n>` and stop if it:
  - removes keys from `.github/AL-Go-Settings.json`. Per-repo config is about to be lost, so move
    it to `.AL-Go/settings.json` first.
  - adds back `TEMPLATE.code-workspace`. The templates now list it and `*.code-workspace`, and
    Initialize also requires the all-zero app id, but a repo's own `.templatesyncignore` wins
    over the template's. If it's missing there, the sync re-adds the file. **Never merge a
    `chore/initialize-template-repo` PR on a repo whose `app/app.json` already has a real id**:
    it regenerates the id, and BC treats the app as a different one.
  - Lines in `.templatesyncignore` go through `xargs`, so **a path with spaces never matches**.
    Use a glob (`*.code-workspace`).
  - wipes repo-specific lines from a `.vscode/settings.json` or `.gitignore`. Move them to a file
    the template doesn't ship, or list the file in the repo's `.templatesyncignore`.
- **CODEOWNERS.** `/.github/`, `/.AL-Go/`, `*.code-workspace`, `**/.vscode/settings.json`,
  `**/.gitignore` are owned by `@DSC-Group-Srl/ci-cd-admins`. A PR touching them waits for that
  team's review, so flag it in the PR description.
- `app-performance/app.json` keeps its own `idRanges`, distinct from `app/` and `app-test/`.

## 6. Runners, secrets, signing

- All AL-Go jobs run on **self-hosted** runners (`runs-on`/`githubRunner`): DSC's in-house
  servers, Windows + Docker + PowerShell 7+, needed for BC containers. GitHub-hosted runners are
  for .NET/Node web apps and Docker images, and for Template Sync (`ubuntu-latest`). A job stuck in *Queued* means no matching runner is online. That is a
  question for CI/CD admins, not a code problem.
- **AppSource signing**: `CustomJobSignLocal` runs on `[self-hosted, signing]` (the machine with
  the Sectigo eToken), signs every `.app` with `scsigntool`, re-uploads the artifact, and gates
  Deploy and Deliver. If that runner is offline, AppSource CI/CD never reaches deploy.
- Secrets, **by name only**. Never read, print, echo or ask for their values, and don't try to
  enumerate them:
  - `GhTokenWorkflow`: GitHub App credential. Lets Rebuild Test Branch push past the `test`
    ruleset, and authenticates `appDependencyProbingPaths`
  - `TEMPLATE_SYNC_PAT`: Template Sync
  - `<env>_AuthContext` / `AuthContext`: Deploy / Publish To Environment
  - `AppSourceContext`: Publish To AppSource / deliver
  - `SIGNING_TOKEN_PASSWORD` plus vars `SIGNING_TOKEN_CONTAINER|CSP|CERTPATH`: signing
  To check whether one exists, the user runs **Troubleshooting** with `displayNameOfSecrets`.

## 7. Operating it from Claude Code

Read-only and always fine:

```bash
gh run list --limit 10                         # add --branch test / --workflow CICD.yaml
gh run view <run-id>                           # jobs and their status
gh run view <run-id> --log-failed              # only the failing steps' logs
gh pr checks <pr>                              # the PR's Pull Request Build
gh workflow list
```

Dispatching (confirm with the user first, and **always** for production, release, AppSource):

```bash
gh workflow run RebuildTestBranch.yaml --ref main
gh workflow run CICD.yaml --ref test
gh workflow run PublishToEnvironment.yaml --ref main -f appVersion=PR_42 -f environmentName=Customer-Test
gh run watch <run-id>
# Create release / Publish To Environment (production) / Publish To AppSource:
# the full commands with DSC's inputs are in §2 "Releasing to production"
```

These are the same HITL rules as `al_publish`: anything that changes a live tenant, a release
or a Partner Center listing is a human decision. Present the exact command and its inputs, then
wait for a yes.

To find a customer's repos, use the custom properties (`customer`, `customer-reference`,
`business-unit`, `app-type`):
`gh search repos --owner DSC-Group-Srl "props.customer:\"C & C MILANO\""`. The search bar has no
OR across two `props.*` qualifiers, so owner and referenced customer need two queries.

## 8. Reading a failure

| Symptom | Likely cause | Fix |
|---|---|---|
| PR not on `test` after the rebuild, comment "merge conflict" | conflicts with `main` or another open PR | rebase the PR onto `main`. It's retried the next night |
| Rebuild Test Branch fails at push | `GhTokenWorkflow` missing/expired, or its app not on the `test` ruleset bypass list | CI/CD admins |
| `test` rebuilt but the test environment is unchanged | CI/CD doesn't trigger on `test` pushes (§2.3), or no `DeployTo<env>` has `test` in `Branches` | dispatch CI/CD on `test`. Check the settings |
| Test deploy stopped working after a Monday | a merged `[template-sync]` PR removed `environments`/`DeployTo<env>` from `.github/AL-Go-Settings.json` | restore them in `.AL-Go/settings.json` (§4) |
| Deploy step: authentication / environment not found | `<env>_AuthContext` secret missing, or `EnvironmentName` ≠ the BC environment name | user adds the secret. Fix `DeployTo<env>` |
| Build fails: app.json placeholders, `00000000-…` GUID | new repo whose Initialize PR isn't merged, or `<name>`/`<publisher>`/`<affix>` not filled | merge `chore/initialize-template-repo`. Fill app.json and the affix |
| Initialize Template Repository: `startup_failure` | branch protection / Actions permissions blocked the bot on the first push | re-dispatch once Actions may push, or apply its diff by hand |
| Template Sync fails restoring `TEMPLATE.code-workspace` | `.templatesyncignore` still names the old file | point it at `<repo>.code-workspace` (Initialize normally does this) |
| AppSourceCop / PerTenantExtensionCop errors only in CI | CI runs every analyzer of the flavour | fix locally with `al_compile` and all analyzers on. Don't relax the ruleset to get green |
| Dependency app not found | `appDependencyProbingPaths` repo/branch wrong, or no successful build there | build the dependency first. Check `release_status` |
| Job queued forever | no self-hosted runner online (or no `signing` runner for AppSource) | CI/CD admins |
| Fails only on Test Next Minor / Next Major | breaking change in the coming BC version | `skill-migrate`. Fix on a PR into `main` |

Read the failing step's log (`--log-failed`) before proposing a fix. AL compile errors in CI
are fixed in code through the normal flow (`al-developer`, then a PR), never by editing the
workflow.

## Related

- `skill-al-go-devenv`: local container / cloud sandbox from `.AL-Go/localDevEnv.ps1` for the
  test lane
- `skill-test-lane`: running tests locally before the PR. CI's Pull Request Build runs them again
- `/bc-dev:al-pr-prepare`: the PR that starts the lifecycle. `skill-changelog`: release notes
- `bc-dev:al-triage`: the KO loop on a PR
