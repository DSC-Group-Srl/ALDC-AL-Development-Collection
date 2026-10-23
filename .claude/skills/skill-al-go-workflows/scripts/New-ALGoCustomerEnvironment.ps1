#Requires -Version 7.0
<#
.SYNOPSIS
    Wire a customer's Business Central environment into a DSC PTE repo's AL-Go CI/CD.

.DESCRIPTION
    Three steps, each confirmed before it changes anything:

      1. GitHub: creates (or updates) the GitHub environment <GitHubEnvironment> on the repo,
         restricts its deployment branches (main + test for a test environment, main only for
         production) and sets the environment secret AUTHCONTEXT. The secret is the AL-Go
         auth-context JSON you keep in Royal TS ("DSC GROUP" folder), with its tenant id
         replaced by the customer's. It is read with a hidden prompt, sent to gh on stdin
         (never on the command line) and never printed.
      2. Settings: adds the environment to "environments" and writes DeployTo<GitHubEnvironment>
         in .AL-Go/settings.json (the repo-owned file; .github/AL-Go-Settings.json is replaced
         by Template Sync every Monday). Shows the diff and writes only after a yes. The change
         still has to reach main through a PR.
      3. Checklist: prints the manual steps in the customer's BC environment (Microsoft Entra
         Applications page, permission sets, consent) with the client id filled in.

    Needs: PowerShell 7, gh logged in with admin rights on the repo (gh auth status), git.
    Run it in your own terminal: the secret prompt needs a real console.

.PARAMETER RepoPath
    Local clone of the PTE repo. Default: current directory.

.PARAMETER Repo
    owner/name on GitHub. Default: read from the clone with gh repo view.

.PARAMETER BcEnvironmentName
    The environment name as it appears in the BC admin center (e.g. Martesana-Test, Production).

.PARAMETER GitHubEnvironment
    The GitHub environment name. Default: same as BcEnvironmentName (the DSC convention).

.PARAMETER TenantId
    The customer's Microsoft Entra tenant id (GUID) or primary domain (contoso.onmicrosoft.com).

.PARAMETER Production
    The environment is the customer's production: deployment branches = main only,
    continuousDeployment = false, no DeployTo test-app deploy. Default: a test environment
    (branches main + test, continuousDeployment = true).

.PARAMETER IncludeTestApps
    Test environment only: also deploy the test app (includeTestAppsInSandboxEnvironment).
    Off by default, as in fujitsu-base / martesana-base. Read pte-test-environment.md first.

.PARAMETER SkipGitHub
    Skip step 1 (environment + secret). E.g. only patch settings.

.PARAMETER SkipSettings
    Skip step 2 (.AL-Go/settings.json).

.PARAMETER DryRun
    Show what would be done (plan + settings diff) and change nothing. Does not ask for the secret.

.EXAMPLE
    pwsh -File New-ALGoCustomerEnvironment.ps1 -BcEnvironmentName Martesana-Test -TenantId 80af198e-...

.EXAMPLE
    pwsh -File New-ALGoCustomerEnvironment.ps1 -BcEnvironmentName Production -Production -SkipSettings

.EXAMPLE
    pwsh -File New-ALGoCustomerEnvironment.ps1 -BcEnvironmentName Customer-Test -TenantId contoso.onmicrosoft.com -DryRun
#>
[CmdletBinding()]
param(
    [string] $RepoPath = (Get-Location).Path,
    [string] $Repo,
    [string] $BcEnvironmentName,
    [string] $GitHubEnvironment,
    [string] $TenantId,
    [switch] $Production,
    [switch] $IncludeTestApps,
    [switch] $SkipGitHub,
    [switch] $SkipSettings,
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string] $Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }
function Write-Note([string] $Text) { Write-Host "   $Text" }
function Write-Warn([string] $Text) { Write-Host "   ! $Text" -ForegroundColor Yellow }

function Confirm-Step([string] $Question) {
    if ($DryRun) { Write-Note "(dry run: not asking '$Question')"; return $false }
    $answer = Read-Host "$Question [y/N]"
    return $answer -match '^(y|yes|s|si|sì)$'
}

function Read-Required([string] $Prompt, [string] $Current) {
    if ($Current) { return $Current }
    do { $value = (Read-Host $Prompt).Trim() } while (-not $value)
    return $value
}

function Invoke-Gh {
    # Runs gh with $args as-is, throws with its stderr on failure. Never used for anything that carries the secret.
    $out = & gh @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "gh $($args -join ' ') failed: $out" }
    return $out
}

function Set-GhSecretFromStdin {
    # Pipes the value to `gh secret set` through stdin without a trailing newline,
    # so it never appears in the process list, the console or the transcript.
    param([string] $Name, [string] $Environment, [string] $RepoSlug, [string] $Value)
    $psi = [System.Diagnostics.ProcessStartInfo]::new('gh')
    foreach ($a in @('secret', 'set', $Name, '--env', $Environment, '--repo', $RepoSlug)) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($Value)
    $p.StandardInput.Close()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "gh secret set $Name --env $Environment failed: $stderr" }
    if ($stdout) { Write-Note $stdout.Trim() }
}

function Get-JsonProperty($Object, [string] $Name) {
    # Case-insensitive lookup: AL-Go accepts both tenantId/clientId/clientSecret and TenantID/ClientID/ClientSecret.
    return $Object.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
}

# ---------------------------------------------------------------- context
Write-Step 'Context'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'gh (GitHub CLI) not found on PATH.' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git not found on PATH.' }
$null = & gh auth status 2>&1
if ($LASTEXITCODE -ne 0) { throw 'gh is not logged in. Run: gh auth login' }

$repoRoot = (& git -C $RepoPath rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) { throw "$RepoPath is not inside a git repository." }
$repoRoot = (Resolve-Path $repoRoot).Path
if (-not $Repo) {
    Push-Location $repoRoot
    try { $Repo = (Invoke-Gh repo view --json nameWithOwner --jq .nameWithOwner).Trim() } finally { Pop-Location }
}

$repoSettingsPath = Join-Path $repoRoot '.github/AL-Go-Settings.json'
if (Test-Path $repoSettingsPath) {
    $type = (Get-Content $repoSettingsPath -Raw | ConvertFrom-Json).type
    if ($type -ne 'PTE') { Write-Warn "'.github/AL-Go-Settings.json' type is '$type', not PTE. This script is for PTE repos (AppSource repos have no customer test environment)." }
}

$BcEnvironmentName = Read-Required 'BC environment name (as in the BC admin center, e.g. Customer-Test)' $BcEnvironmentName
if (-not $GitHubEnvironment) { $GitHubEnvironment = $BcEnvironmentName }
if ($GitHubEnvironment -match '[^A-Za-z0-9\-_.]') { Write-Warn "GitHub environment name '$GitHubEnvironment' has characters outside A-Z a-z 0-9 - _ . ; AL-Go secret lookups may not match." }
$branches = if ($Production) { @('main') } else { @('main', 'test') }
$continuous = -not $Production

Write-Note "Repo:               $Repo   ($repoRoot)"
Write-Note "GitHub environment: $GitHubEnvironment"
Write-Note "BC environment:     $BcEnvironmentName"
Write-Note "Kind:               $(if ($Production) { 'production (main only, no continuous deployment)' } else { 'test (main + test, continuous deployment)' })"

# ---------------------------------------------------------------- step 1: GitHub environment + AUTHCONTEXT
$clientId = $null
if (-not $SkipGitHub) {
    Write-Step "Step 1 - GitHub environment '$GitHubEnvironment' and its AUTHCONTEXT secret"

    $existing = $null
    $null = & gh api "repos/$Repo/environments/$GitHubEnvironment" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $existing = $true
        $secretNames = @(& gh api "repos/$Repo/environments/$GitHubEnvironment/secrets" --jq '.secrets[].name' 2>$null)
        Write-Warn "The environment already exists (secrets: $(if ($secretNames) { $secretNames -join ', ' } else { 'none' })). Continuing updates its branch policy and OVERWRITES AUTHCONTEXT."
    }

    if ($DryRun) {
        Write-Note "(dry run) would PUT repos/$Repo/environments/$GitHubEnvironment with custom branch policies: $($branches -join ', ')"
        Write-Note "(dry run) would set environment secret AUTHCONTEXT on '$GitHubEnvironment'"
    }
    else {
        Write-Host ''
        Write-Host 'Paste the AL-Go auth-context JSON from Royal TS (input is hidden), then Enter:'
        $secure = Read-Host -AsSecureString
        $raw = (ConvertFrom-SecureString -SecureString $secure -AsPlainText).Trim()
        try { $auth = $raw | ConvertFrom-Json } catch { throw 'That is not valid JSON. Nothing was changed. (The JSON is not printed on purpose.)' }
        $raw = $null

        $tenantProp = Get-JsonProperty $auth 'tenantId'
        $clientProp = Get-JsonProperty $auth 'clientId'
        $secretProp = Get-JsonProperty $auth 'clientSecret'
        $refreshProp = Get-JsonProperty $auth 'refreshToken'
        if (-not $clientProp -or -not $clientProp.Value) { throw 'The JSON has no clientId / ClientID. Nothing was changed.' }
        $clientId = [string] $clientProp.Value
        $authKind = if ($secretProp) { 'client secret (S2S)' } elseif ($refreshProp) { 'refresh token (expires after ~90 days)' } else { 'federated credential (no secret in the JSON)' }
        Write-Note "Keys found: $(($auth.PSObject.Properties.Name) -join ', ')   [values not shown]"
        Write-Note "Auth type:  $authKind"
        Write-Note "Client id:  $clientId   (not a secret; you need it in step 3)"

        $TenantId = Read-Required "Customer's tenant id (GUID or domain, e.g. contoso.onmicrosoft.com)" $TenantId
        if ($TenantId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -and $TenantId -notmatch '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$') {
            throw "'$TenantId' is neither a GUID nor a domain. Nothing was changed."
        }
        if ($tenantProp) { $tenantProp.Value = $TenantId }
        else { $auth | Add-Member -NotePropertyName 'tenantId' -NotePropertyValue $TenantId }
        $authJson = $auth | ConvertTo-Json -Compress -Depth 5     # AL-Go wants compressed JSON, no newline
        $auth = $null

        Write-Host ''
        Write-Note "About to: create/update GitHub environment '$GitHubEnvironment' on $Repo (deployment branches: $($branches -join ', '))"
        Write-Note "          set its AUTHCONTEXT secret (tenant $TenantId, client $clientId)"
        if (-not (Confirm-Step 'Proceed with the GitHub changes?')) {
            $authJson = $null
            Write-Warn 'Skipped. GitHub was not changed.'
        }
        else {
            $body = @{ deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true } } | ConvertTo-Json -Compress
            $null = $body | gh api -X PUT "repos/$Repo/environments/$GitHubEnvironment" --input - 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Creating the environment failed (repo admin rights needed). GitHub was not changed beyond this point." }
            Write-Note "Environment '$GitHubEnvironment' ready."

            $policies = @(& gh api "repos/$Repo/environments/$GitHubEnvironment/deployment-branch-policies" --jq '.branch_policies[].name' 2>$null)
            foreach ($b in $branches) {
                if ($policies -contains $b) { Write-Note "Branch policy '$b' already there."; continue }
                $null = Invoke-Gh api -X POST "repos/$Repo/environments/$GitHubEnvironment/deployment-branch-policies" -f "name=$b" -f 'type=branch'
                Write-Note "Branch policy '$b' added."
            }
            foreach ($p in $policies) {
                if ($branches -notcontains $p) { Write-Warn "Extra branch policy '$p' left in place. Remove it by hand if it should not deploy here." }
            }

            Set-GhSecretFromStdin -Name 'AUTHCONTEXT' -Environment $GitHubEnvironment -RepoSlug $Repo -Value $authJson
            $authJson = $null
            Write-Note 'AUTHCONTEXT set.'
        }
    }
}

# ---------------------------------------------------------------- step 2: .AL-Go/settings.json
if (-not $SkipSettings) {
    Write-Step "Step 2 - DeployTo$GitHubEnvironment in .AL-Go/settings.json"
    $settingsPath = Join-Path $repoRoot '.AL-Go/settings.json'
    if (-not (Test-Path $settingsPath)) { throw "$settingsPath not found." }
    $currentText = Get-Content $settingsPath -Raw
    $settings = $currentText | ConvertFrom-Json

    $envs = @()
    if ($settings.PSObject.Properties['environments']) { $envs = @($settings.environments) }
    if ($envs -notcontains $GitHubEnvironment) { $envs += $GitHubEnvironment }
    if ($settings.PSObject.Properties['environments']) { $settings.environments = $envs }
    else { $settings | Add-Member -NotePropertyName 'environments' -NotePropertyValue $envs }

    $deploy = [ordered]@{
        EnvironmentType      = 'SaaS'
        EnvironmentName      = $BcEnvironmentName
        Branches             = $branches
        continuousDeployment = $continuous
    }
    if ($IncludeTestApps -and -not $Production) { $deploy['includeTestAppsInSandboxEnvironment'] = $true }
    $key = "DeployTo$GitHubEnvironment"
    $existingKey = $settings.PSObject.Properties | Where-Object { $_.Name -ieq $key } | Select-Object -First 1
    if ($existingKey) {
        # Keep any extra keys the repo already set (Scope, SyncMode, excludeAppIds, ...).
        $merged = [ordered]@{}
        foreach ($pp in $existingKey.Value.PSObject.Properties) { $merged[$pp.Name] = $pp.Value }
        foreach ($k in $deploy.Keys) { $merged[$k] = $deploy[$k] }
        $settings.($existingKey.Name) = [pscustomobject] $merged
    }
    else {
        $settings | Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject] $deploy)
    }

    $eol = if ($currentText -match "`r`n") { "`r`n" } else { "`n" }   # keep the file's line endings
    $newText = ((($settings | ConvertTo-Json -Depth 20) -replace "`r?`n", $eol) + $eol)
    if (($newText -replace "`r`n", "`n").TrimEnd() -eq ($currentText -replace "`r`n", "`n").TrimEnd()) {
        Write-Note 'Already up to date. Nothing to change.'
    }
    else {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "algo-settings-$([guid]::NewGuid()).json"
        [System.IO.File]::WriteAllText($tmp, $newText, [System.Text.UTF8Encoding]::new($false))
        & git -c core.autocrlf=false -c core.safecrlf=false --no-pager diff --no-index --ignore-cr-at-eol --color=always -- $settingsPath $tmp 2>$null
        Remove-Item $tmp -ErrorAction SilentlyContinue
        if (Confirm-Step "Write this to .AL-Go/settings.json?") {
            [System.IO.File]::WriteAllText($settingsPath, $newText, [System.Text.UTF8Encoding]::new($false))
            Write-Note 'Written. Commit it on a branch and open a PR into main (main blocks direct pushes;'
            Write-Note '/.AL-Go/ is owned by @DSC-Group-Srl/ci-cd-admins, so the PR waits for that team).'
        }
        else { Write-Warn 'Not written.' }
    }

    # Checks only: these files are template-owned, a local fix would be overwritten by Template Sync.
    if (-not $Production) {
        if (Test-Path $repoSettingsPath) {
            $push = @((Get-Content $repoSettingsPath -Raw | ConvertFrom-Json).PSObject.Properties | Where-Object Name -eq 'CICDPushBranches' | ForEach-Object { $_.Value })
            if ($push -notcontains 'test') { Write-Warn ".github/AL-Go-Settings.json CICDPushBranches has no 'test'. Sync the repo from the al-pte template (Template Sync), don't edit it here." }
        }
        $cicd = Join-Path $repoRoot '.github/workflows/CICD.yaml'
        if ((Test-Path $cicd) -and -not (Select-String -Path $cicd -Pattern "branches:.*'test'" -Quiet)) {
            Write-Warn "CICD.yaml push trigger has no 'test': pushes to test won't deploy. Fix it in the al-pte template; meanwhile dispatch: gh workflow run CICD.yaml --ref test"
        }
    }
}

# ---------------------------------------------------------------- step 3: manual checklist in BC
Write-Step "Step 3 - In the customer's BC environment '$BcEnvironmentName' (manual, you do it)"
$cid = if ($clientId) { $clientId } else { '<clientId from the Royal TS JSON>' }
$tid = if ($TenantId) { $TenantId } else { '<customer tenant id>' }
Write-Note "1. Consent (once per customer tenant, a customer admin with Cloud Application Administrator or Global Admin):"
Write-Note "   https://login.microsoftonline.com/$tid/adminconsent?client_id=$cid"
Write-Note "2. Open https://businesscentral.dynamics.com/$tid/$BcEnvironmentName , search 'Microsoft Entra Applications', New:"
Write-Note "   Client ID = $cid ; Description = 'DSC Group - AL-Go CI/CD' ; State = Enabled"
Write-Note "3. User Permission Sets on the card: D365 FULL ACCESS and EXTEN. MGT. - ADMIN (company blank = all companies)"
Write-Note "4. Repeat 2-3 in every BC environment AL-Go deploys to (test AND production)."
Write-Note "Then follow the first deploy: see pte-test-environment.md, 'Rebuild test and follow the deploy'."
