# PTE: the customer's test environment, end to end

Companion to `SKILL.md` §2. For DSC **PTE** repos only (`.github/AL-Go-Settings.json`
`"type": "PTE"`): AppSource repos have no customer test environment.

What "set up" means, in the order it has to happen:

1. a BC environment in the customer's tenant (they or the consultant create it in the BC admin
   center; DSC names it `<Customer>-Test`),
2. DSC's Entra app registration consented in the customer's tenant and registered in that BC
   environment (§C, manual),
3. a GitHub environment on the repo with the `AUTHCONTEXT` secret (§B, script),
4. `DeployTo<env>` in `.AL-Go/settings.json` so CI/CD on `main` and `test` deploys there (§B
   step 2 and §D),
5. a rebuild of `test` and a green `Deploy to <env>` job (§A).

The script does 3 and 4 and prints 2 as a checklist. Every step that changes GitHub, the repo or
the tenant asks first. **Claude never runs the script itself**: it needs the user's console for
the hidden secret prompt, and pasting the auth context into a chat would leak it. Claude may run
it with `-SkipGitHub -DryRun` to show the settings diff.

## A. Rebuild `test` and follow the deploy

`Rebuild Test Branch` (`RebuildTestBranch.yaml`) is the DSC-custom workflow from SKILL §1. It runs
on `main`, rebuilds `test` = `main` + every open PR into `main`, and force-pushes it with the
`GhTokenWorkflow` app token. A push made with an app token triggers workflows (one made with
`GITHUB_TOKEN` would not), so the push starts **CI/CD on `test`**, whose `Deploy to <env>` job
publishes into every environment whose `DeployTo<env>.Branches` contains `test`.

Dispatching it replaces `test`, so confirm with the user first:

```bash
gh workflow run RebuildTestBranch.yaml --ref main
gh run list --workflow RebuildTestBranch.yaml --limit 1          # take the new run id
gh run watch <rebuild-id> --exit-status                          # ~1-2 min
gh run view <rebuild-id> --log | grep -E "Found .* open PR|Merged PR #|Skipped PR #"
```

The job summary (merged / skipped PRs) is only on the web page; the log lines above carry the
same facts. A skipped PR also gets an `@`-mention comment.

Then the CI/CD run the push started (event `push`, branch `test`, created after the rebuild):

```bash
gh run list --workflow CICD.yaml --branch test --limit 3         # newest first
gh run watch <cicd-id> --exit-status                             # build ~10-15 min, deploy ~3-5 min
gh run view <cicd-id>                                            # jobs + artifacts
gh run view <cicd-id> --log-failed                               # only if it failed
```

**What success looks like** (from `martesana-base`, run 38833943980):

```
✓ Initialization
✓ CheckForUpdates
✓ Build . (Default) / . (Default)
✓ Deploy to Martesana-Test
✓ PostProcess
ARTIFACTS  <repo>-test-Apps-<ver>  <repo>-test-TestApps-<ver>  <repo>-test-TestResults-<ver>  …
```

and in the deploy job's log:

```bash
gh run view --job <deploy-job-id> --log | grep -E "Apps to deploy|^- .*\.app|upgrading|installing|Ignoring environment|Evaluated environment url"
```

- `Apps to deploy` lists the `.app` files, then `<publisher>_<name>_<version>.app - upgrading....`
  (or `installing`) via `Publishing apps using automation API`.
- `Evaluated environment url: https://businesscentral.dynamics.com/<tenant>/<env>` is the
  environment that received it. Give the user that link.
- **Only the app is deployed by default.** The test app is built and tested in the container but
  goes to the environment only with `includeTestAppsInSandboxEnvironment: true` (§D). Neither
  reference repo sets it.

Gotchas seen on the live repos:

- **No open PRs → no CI/CD on `test`.** With nothing to merge, `test` is recreated identical to
  `main`; the push has no changed files and the CI/CD trigger (it has `paths-ignore`) doesn't
  fire. Nothing is lost: the same `DeployTo<env>` also lists `main`, so the last merge into `main`
  already deployed it. To force it: `gh workflow run CICD.yaml --ref test`. (Inferred from
  `martesana-base`: nightly rebuilds green, no CI/CD on `test` since its PRs were merged.)
- **`Deploy to Production` green on a `main` push doesn't mean production got it.** When the
  GitHub environment `Production` exists and `continuousDeployment` isn't set, AL-Go logs
  `Ignoring environment Production, which is a production environment` and skips it. Production
  goes through Publish To Environment (SKILL §2).
- `Deploy to <env>` job **missing or skipped**: no `DeployTo<env>` with this branch in
  `Branches`, the GitHub environment's branch policy doesn't allow the branch, or
  `CICD.yaml` doesn't trigger on `test` (`grep -n "branches:" .github/workflows/CICD.yaml`).

| Deploy log says | Cause | Fix |
|---|---|---|
| device-login instructions / no AuthContext | no `AUTHCONTEXT` on the GitHub environment and no `<env>_AuthContext` repo secret | §B step 1 |
| `AADSTS700016` / `AADSTS7000215` / `AADSTS90002` | wrong client id / expired or wrong client secret / wrong tenant id in the JSON | re-run §B step 1 with the right tenant; a new secret in Royal TS if expired |
| `AADSTS65001` / consent | app not consented in the customer's tenant | §C step 1 |
| `401` / `403` / `Unauthorized` after `Authenticated as app` | app not on the **Microsoft Entra Applications** page of that BC environment, not Enabled, or missing permission sets | §C steps 2-3 |
| `environment … not found` / 404 on the environment URL | `EnvironmentName` ≠ the name in the BC admin center | fix `DeployTo<env>.EnvironmentName` |
| test-app publish rejected | test app `target` / Microsoft test-library dependencies not installable on SaaS | drop `includeTestAppsInSandboxEnvironment` |

## B. Create the environment: `scripts/New-ALGoCustomerEnvironment.ps1`

The user runs it in their own PowerShell 7 window, from the repo's clone, with `gh` logged in as
a repo admin:

```powershell
$s = "<plugin>/skills/skill-al-go-workflows/scripts/New-ALGoCustomerEnvironment.ps1"
pwsh -File $s -BcEnvironmentName Customer-Test -TenantId <customer tenant GUID or domain>
pwsh -File $s -BcEnvironmentName Production -Production            # production: main only, no CD
pwsh -File $s -BcEnvironmentName Customer-Test -SkipGitHub -DryRun # settings diff only, changes nothing
```

`<plugin>` is the installed bc-dev plugin folder (in this repo, `claude-plugin`). Options:
`-GitHubEnvironment` (default = the BC name), `-Repo owner/name`, `-IncludeTestApps`,
`-SkipGitHub`, `-SkipSettings`.

**Step 1: GitHub environment + `AUTHCONTEXT`.**

- It asks for the **auth-context JSON from Royal TS** (folder "DSC GROUP") with a hidden prompt.
  AL-Go accepts either casing, and the script keeps whichever the JSON has:
  `{"tenantId":"…","scopes":"https://api.businesscentral.dynamics.com/","clientId":"…","clientSecret":"…"}`
  or `{"TenantID":"…","ClientID":"…","ClientSecret":"…"}`. (A `refreshToken` variant also works
  but expires after ~90 days; no secret at all = federated credential.)
- It asks for the **customer's tenant id** (GUID or `contoso.onmicrosoft.com`) and replaces the
  tenant in the JSON with it. Everything else (client id, secret) is DSC's and stays.
- It prints the key names, the auth type and the **client id** (not a secret, you need it in §C)
  and never the secret or the JSON.
- After a yes it runs, in this order:

  ```bash
  gh api -X PUT repos/<owner>/<repo>/environments/<env> --input -    # {"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
  gh api -X POST repos/<owner>/<repo>/environments/<env>/deployment-branch-policies -f name=main -f type=branch
  gh api -X POST …/deployment-branch-policies -f name=test -f type=branch     # test environments only
  gh secret set AUTHCONTEXT --env <env> --repo <owner>/<repo>                 # value on stdin, compressed JSON, no newline
  ```

  The secret name is `AUTHCONTEXT` **as an environment secret**, which is what both reference
  repos use (AL-Go also looks for `<env>-AuthContext`, `<env>_AuthContext`, `AuthContext` as
  repo/org secrets, in that order; DSC doesn't use those). If the environment exists, the script
  says so and overwrites the secret only after the yes.

**Step 2: `.AL-Go/settings.json`.** Adds the environment to `environments`, writes
`DeployTo<env>` (§D), keeps any extra keys an existing block has, shows `git diff`, writes after a
yes. Then: a branch, a PR into `main` (`/.AL-Go/` is owned by `@DSC-Group-Srl/ci-cd-admins`, so
the PR waits for that team). It also warns, without touching them, when `CICDPushBranches` in
`.github/AL-Go-Settings.json` or the `CICD.yaml` trigger lack `test`: both are template-owned,
fix them in `al-pte` (SKILL §5).

**Step 3: prints the §C checklist** with the client id and tenant filled in.

## C. In the customer's tenant (manual, HITL)

Claude never does these: they are admin actions in a customer's tenant. Walk the user through
them. Source: Microsoft Learn, *Using service-to-service (S2S) authentication*, task 2
(<https://learn.microsoft.com/dynamics365/business-central/dev-itpro/administration/automation-apis-using-s2s-authentication>).

1. **Consent, once per customer tenant.** DSC's app registration is multi-tenant and already
   carries the **Dynamics 365 Business Central** application permissions `API.ReadWrite.All` and
   `Automation.ReadWrite.All` (one-time setup on DSC's side). A customer admin (Global
   Administrator or Cloud Application Administrator; the Dynamics 365 Administrator role is not
   enough) opens
   `https://login.microsoftonline.com/<customerTenantId>/adminconsent?client_id=<clientId>` and
   accepts. Alternatively the **Grant Consent** action on the card in step 2 (needs a redirect
   URL on the app registration), or the BC admin center's *Authorized Microsoft Entra apps* page.
2. **In every target BC environment** (test *and* production):
   `https://businesscentral.dynamics.com/<tenant>/<environment>` → search **Microsoft Entra
   Applications** → **New**. **Client ID** = the client id from the script; **Description** =
   something that identifies DSC (`DSC Group - AL-Go CI/CD`); **State** = **Enabled**. Enabling
   creates a BC user for the app.
3. **User Permission Sets** on the same card: **D365 FULL ACCESS** and **EXTEN. MGT. - ADMIN**,
   company blank (all companies). (`SUPER` can't be assigned to an application. Microsoft's own
   minimum for automation is **D365 AUTOMATION** + **EXTEN. MGT. - ADMIN**; DSC uses
   D365 FULL ACCESS so the app also works for the rest of the pipeline.)
4. Run CI/CD (§A) and check the deploy job.

## D. The settings pattern (fujitsu-base, martesana-base)

Both repos, on `main` and `test`, as of 2026-10:

`.AL-Go/settings.json` (repo-owned, in `.templatesyncignore`):

```json
"environments": [ "Martesana-Test" ],
"DeployToMartesana-Test": {
  "EnvironmentType": "SaaS",
  "EnvironmentName": "Martesana-Test",
  "Branches": [ "main", "test" ],
  "continuousDeployment": true
}
```

(`fujitsu-base` is the same with `General-Test`.) `.github/AL-Go-Settings.json` is the
template's, untouched: `type: PTE`, `templateUrl`, `runs-on`/`githubRunner: self-hosted`,
`CICDPushBranches: [main, release/*, feature/*, test]`. `CICD.yaml` push trigger:
`branches: [ 'main', 'release/*', 'feature/*', 'test' ]`.

GitHub environments (`gh api repos/DSC-Group-Srl/<repo>/environments`):

| GitHub environment | BC environment | Secret | Deployment branches | Deployed by |
|---|---|---|---|---|
| `<Customer>-Test` (`Martesana-Test`, `General-Test`) | same name | `AUTHCONTEXT` (environment secret) | custom: `main`, `test` | CI/CD on every push to `main` and `test` |
| `Production` | `Production` | `AUTHCONTEXT` (environment secret) | `main` (fujitsu); no policy, any branch (martesana) | Publish To Environment only; no `DeployToProduction`, AL-Go skips production in CI/CD |

No repo-level secrets or variables in either repo: `AUTHCONTEXT` is on each environment, and
`GHTOKENWORKFLOW`, `TEMPLATE_SYNC_PAT`, `APPSOURCECONTEXT`, `SIGNING_TOKEN_PASSWORD` are
organization secrets.

Rules that follow from it:

- GitHub environment name = BC environment name, so `EnvironmentName` is there for clarity; it
  must equal the BC admin center name when they differ.
- The key after `DeployTo` must equal the `environments` entry and the GitHub environment name.
- `Branches` in `DeployTo<env>` and the GitHub environment's branch policy are both honoured;
  keep them the same (`main`, `test`).
- `continuousDeployment: true` on test environments only. For production either leave it out
  (AL-Go ignores production environments in CI/CD) or write `DeployToProduction` with
  `"Branches": ["main"], "continuousDeployment": false` (`-Production` does the latter).
- Optional, test environment only: `"includeTestAppsInSandboxEnvironment": true` also deploys the
  test app and its dependencies (sandbox only; `-IncludeTestApps`). Not used by the reference
  repos and not tried on a DSC repo yet: check the test app's `target` and that its Microsoft
  test-library dependencies install on SaaS before turning it on.
- Never put any of this in `.github/AL-Go-Settings.json`: Template Sync replaces that file every
  Monday (SKILL §5).

Valid keys: <https://aka.ms/algosettings#deployto>. Secrets: AL-Go `Scenarios/secrets.md`
(`AuthContext`) and `Scenarios/RegisterSandboxEnvironment.md`.
