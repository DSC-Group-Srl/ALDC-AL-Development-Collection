<#
.SYNOPSIS
    Store UserPassword credentials for an on-prem / Docker BC server where the AL CLI reads them,
    so `al publishapp` / `al runtests` authenticate without a prompt.

.DESCRIPTION
    The AL CLI (altool) never asks for a UserPassword credential: it reads a per-user, data-
    protected `UserPasswordCache.dat` next to its own executable
    (Microsoft.Dynamics.Nav.Deployment -> OnPremiseHttpClientFactory.TryGetSavedCredentials),
    keyed by "<server lower-cased>_<instance lower-cased>". VS Code's AL extension keeps its own
    copy under its extension folder, so logging in from VS Code does not help the CLI.

    This script writes ONE entry through the same library the CLI uses (so the encryption and
    the key format are exactly what it expects), into every installed altool version. Existing
    entries for other servers are preserved and never printed.

    Intended for local, disposable test containers (e.g. created by AL-Go's
    .AL-Go/localDevEnv.ps1). Never use it for a shared or production server's credentials.

.EXAMPLE
    ./save-onprem-credentials.ps1 -Server http://dyna-arx-test/BC/ -ServerInstance BC -Username admin -Password 'P@ssw0rd123'
#>
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $ServerInstance,
    [Parameter(Mandatory)] [string] $Username,
    [Parameter(Mandatory)] [string] $Password
)
$ErrorActionPreference = 'Stop'

$store = Join-Path $env:USERPROFILE '.dotnet\tools\.store\microsoft.dynamics.businesscentral.development.tools'
$dlls = Get-ChildItem $store -Recurse -Filter Microsoft.Dynamics.Nav.Deployment.dll -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.DirectoryName 'altool.dll') }
if (-not $dlls) { Write-Output '{"ok":false,"error":"AL CLI (altool) not found under ~/.dotnet/tools"}'; exit 0 }

$written = 0
foreach ($dll in $dlls) {
    # Each altool version gets its own process so its own copy of the assembly is loaded.
    $script = {
        param([string] $dllPath, [string] $server, [string] $instance, [string] $user, [string] $pwd)
        $a = [Reflection.Assembly]::LoadFrom($dllPath)
        $np = [Reflection.BindingFlags]'NonPublic,Instance'
        $storageType = $a.GetType('Microsoft.Dynamics.Nav.Deployment.Authentication.UserProtectedFileStorage')
        $credType = $a.GetType('Microsoft.Dynamics.Nav.Deployment.Authentication.UsernamePassword')
        $factory = $a.GetType('Microsoft.Dynamics.Nav.Deployment.Http.OnPremiseHttpClientFactory')
        $logger = [Activator]::CreateInstance($a.GetType('Microsoft.Dynamics.Nav.Deployment.VoidLogger'))
        [string] $file = [IO.Path]::Combine([IO.Path]::GetDirectoryName($dllPath), 'UserPasswordCache.dat')
        $storage = $storageType.GetConstructors($np)[0].Invoke(@($logger, $file))
        $dictType = [Collections.Generic.Dictionary`2].MakeGenericType([string], $credType)
        $dict = $null
        if ($storage.Exists()) {
            try { $dict = $storageType.GetMethod('Read', [Type[]]@()).MakeGenericMethod($dictType).Invoke($storage, @()) } catch { $dict = $null }
        }
        if (-not $dict) { $dict = [Activator]::CreateInstance($dictType) }
        $key = $factory.GetMethod('CreateCredentialsKey', [Reflection.BindingFlags]'NonPublic,Static').Invoke($null, @($server, $instance))
        $dict[$key] = [Activator]::CreateInstance($credType, @($user, $pwd))
        [void] $storageType.GetMethod('Write', [Type[]]@([object])).Invoke($storage, @($dict))
        $key
    }
    $key = & pwsh -NoProfile -Command $script -args $dll.FullName, $Server, $ServerInstance, $Username, $Password
    if ($LASTEXITCODE -eq 0 -and $key) { $written++ }
}
[pscustomobject]@{ ok = ($written -gt 0); versions = $written; key = "$(@($key)[-1])".Trim() } | ConvertTo-Json -Compress
