<#
.SYNOPSIS
    Start AL-Go's .AL-Go/localDevEnv.ps1 (Docker BC container) or cloudDevEnv.ps1 fully
    non-interactively in an elevated window, logging to a file an agent can follow.

.DESCRIPTION
    localDevEnv.ps1 prompts only for values it was not given; passing -containerName, -auth,
    -credential and -licenseFileUrl (and never -fromVSCode) makes it prompt-free. Container
    creation needs an elevated shell, so this launcher re-runs itself with -Verb RunAs: the
    user clicks ONE UAC prompt, everything else is unattended (typically 20-40 min: artifact
    download, container creation, compile + publish of every app and test app).

    The log ends with exactly one marker line:
        ALDC-DEVENV-DONE seconds=<n>
        ALDC-DEVENV-FAILED <message>

    Credentials are for a LOCAL, disposable container. The password comes from -Password,
    else $env:ALDC_DEVENV_PASSWORD, else 'P@ssw0rd123' (SQL inside the container rejects
    trivial passwords). Afterwards run save-onprem-credentials.ps1 so the AL CLI can publish
    and run tests against it without a prompt.
#>
param(
    [Parameter(Mandatory)] [string] $RepoRoot,
    [string] $ContainerName = '',
    [ValidateSet('local', 'cloud')] [string] $Kind = 'local',
    [string] $Username = 'admin',
    [string] $Password = '',
    [string] $Log = ''
)
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$script = Join-Path $RepoRoot ".AL-Go\$($Kind)DevEnv.ps1"
if (-not (Test-Path -LiteralPath $script)) {
    [pscustomobject]@{ ok = $false; error = "no .AL-Go\$($Kind)DevEnv.ps1 in $RepoRoot" } | ConvertTo-Json -Compress; exit 0
}
if (-not $ContainerName) { $ContainerName = ((Split-Path $RepoRoot -Leaf) -replace '[^A-Za-z0-9-]', '').ToLower() + '-test' }
if (-not $Password) { $Password = if ($env:ALDC_DEVENV_PASSWORD) { $env:ALDC_DEVENV_PASSWORD } else { 'P@ssw0rd123' } }
if (-not $Log) { $Log = Join-Path ([IO.Path]::GetTempPath()) "aldc-devenv-$ContainerName.log" }
if ($Kind -eq 'local') {
    $docker = & docker info --format '{{.OSType}}' 2>$null
    if ($LASTEXITCODE -ne 0) { [pscustomobject]@{ ok = $false; error = 'docker is not running' } | ConvertTo-Json -Compress; exit 0 }
    if ($docker -ne 'windows') { [pscustomobject]@{ ok = $false; error = "docker is in '$docker' mode; switch Docker Desktop to Windows containers" } | ConvertTo-Json -Compress; exit 0 }
}

# Single-quoted literals inside the generated runner; escape embedded quotes.
function Q([string] $s) { "'" + $s.Replace("'", "''") + "'" }
$scriptArgs = if ($Kind -eq 'local') {
    "-containerName $(Q $ContainerName) -auth UserPassword -credential `$cred -licenseFileUrl 'none'"
} else {
    "-environmentName $(Q $ContainerName) -reuseExistingEnvironment `$true"
}
# Windows PowerShell 5.1's ConvertFrom-Json rejects JSONC comments, and AL-Go rewrites every
# project's .vscode/launch.json at the end of the run ("Previsto ':' o '}'" / "Invalid object
# passed in"), which aborts it before the test toolkit and test apps are installed. Strip
# comments into a temp copy now; afterwards restore the original when it already had a
# configuration for this container (nothing for the user to review), else keep AL-Go's version
# and leave the original next to it as launch.json.aldc-bak.
$launchFiles = @(Get-ChildItem -LiteralPath $RepoRoot -Directory | ForEach-Object {
        Join-Path $_.FullName '.vscode\launch.json' } | Where-Object { Test-Path -LiteralPath $_ })
$stripped = @()
foreach ($lf in $launchFiles) {
    $raw = [IO.File]::ReadAllText($lf)
    if ($raw -notmatch '(?m)^\s*//|/\*') { continue }
    $clean = [regex]::Replace($raw, '(?s)/\*.*?\*/', '')
    $clean = [regex]::Replace($clean, '(?m)^\s*//.*(\r?\n)?', '')
    $clean = [regex]::Replace($clean, ',(\s*[}\]])', '$1')
    try { $null = $clean | ConvertFrom-Json } catch { continue }   # could not clean safely: leave it
    $hasOwn = $raw -match [regex]::Escape("//$ContainerName/")
    Copy-Item -LiteralPath $lf -Destination "$lf.aldc-bak" -Force
    [IO.File]::WriteAllText($lf, $clean)
    $stripped += [pscustomobject]@{ file = $lf; restore = $hasOwn }
}
$restoreLines = ($stripped | ForEach-Object {
        if ($_.restore) { "  Move-Item -LiteralPath $(Q "$($_.file).aldc-bak") -Destination $(Q $_.file) -Force" }
    }) -join "`n"

# AL-Go's pipeline also rewrites tracked repo files as a side effect (seen: AppSourceCop.json
# regenerated from settings.json, dropping keys like supportedCountries). Snapshot what is
# already dirty; afterwards restore every tracked file the run changed that was clean before.
# Launch.json files whose AL-Go version is kept on purpose are excluded.
$dirtyBefore = @(git -C $RepoRoot diff --name-only 2>$null)
$keep = @($stripped | Where-Object { -not $_.restore } | ForEach-Object {
        [IO.Path]::GetRelativePath($RepoRoot, $_.file).Replace('\', '/') })
$gitRestore = @"
  `$before = @($((@($dirtyBefore) + @($keep) | ForEach-Object { Q $_ }) -join ', '))
  foreach (`$f in @(git -C $(Q $RepoRoot) diff --name-only)) {
    if (`$before -notcontains `$f) { git -C $(Q $RepoRoot) checkout -- `$f; Add-Content -LiteralPath $(Q $Log) "ALDC-DEVENV-RESTORED `$f" }
  }
"@

$runner = Join-Path ([IO.Path]::GetTempPath()) "aldc-devenv-$ContainerName.ps1"
@"
# Windows PowerShell 5.1 started from pwsh inherits PowerShell 7's PSModulePath and then fails
# loading BcContainerHelper ("TypeData ... already present"). Reset it to 5.1's own paths.
`$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath','Machine') + ';' + [Environment]::GetFolderPath('MyDocuments') + '\WindowsPowerShell\Modules;' + `$env:ProgramFiles + '\WindowsPowerShell\Modules'
Start-Transcript -Path $(Q $Log) -Force | Out-Null
try {
  Set-Location -LiteralPath $(Q $RepoRoot)
  `$cred = New-Object PSCredential $(Q $Username), (ConvertTo-SecureString $(Q $Password) -AsPlainText -Force)
  `$sw = [Diagnostics.Stopwatch]::StartNew()
  & $(Q $script) $scriptArgs
  `$secs = [int]`$sw.Elapsed.TotalSeconds
} catch { `$failure = `$_.Exception.Message }
finally {
  Stop-Transcript | Out-Null
$restoreLines
$gitRestore
  Remove-Item -LiteralPath $(Q $runner) -ErrorAction SilentlyContinue
  # AL-Go's script catches its own errors and only prints "Error: ..." - read the transcript
  # instead of trusting that it returned.
  if (-not `$failure) {
    `$hit = Select-String -LiteralPath $(Q $Log) -Pattern '^Error: (.+)' | Select-Object -Last 1
    if (`$hit) { `$failure = `$hit.Matches[0].Groups[1].Value }
  }
  if (`$failure) { Add-Content -LiteralPath $(Q $Log) "ALDC-DEVENV-FAILED `$failure" }
  else { Add-Content -LiteralPath $(Q $Log) "ALDC-DEVENV-DONE seconds=`$secs" }
}
"@ | Set-Content -LiteralPath $runner -Encoding UTF8

$verb = if ($Kind -eq 'local') { @{ Verb = 'RunAs' } } else { @{} }
# Windows PowerShell 5.1, not pwsh: BcContainerHelper's Hyper-V probe (Get-WindowsOptionalFeature,
# DISM) fails under PowerShell 7 with "interface not registered" on current Windows builds.
try {
    $p = Start-Process powershell.exe -PassThru -WindowStyle Minimized @verb -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$runner`""
}
catch {
    # UAC declined or timed out: nothing ran - put every stripped launch.json back now.
    foreach ($s in $stripped) { Move-Item -LiteralPath "$($s.file).aldc-bak" -Destination $s.file -Force }
    Remove-Item -LiteralPath $runner -ErrorAction SilentlyContinue
    [pscustomobject]@{ ok = $false; error = "elevation was declined or failed: $($_.Exception.Message)"; launchJsonRestored = $true } | ConvertTo-Json -Compress
    exit 0
}
[pscustomobject]@{ ok = $true; pid = $p.Id; log = $Log; container = $ContainerName; kind = $Kind; username = $Username
    launchJsonCommentsStripped = @($stripped | ForEach-Object { [pscustomobject]@{ file = $_.file; restoredAfterRun = $_.restore } }) } | ConvertTo-Json -Compress -Depth 4
