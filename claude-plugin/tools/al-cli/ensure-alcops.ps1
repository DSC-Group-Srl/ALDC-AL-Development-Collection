<#
.SYNOPSIS
    ALCops bootstrap hook (PowerShell) — Windows-native equivalent of
    ensure-alcops.sh.

.DESCRIPTION
    Ensures the ALCops analyzer DLLs (the successor to
    BusinessCentral.LinterCop, see
    https://alcops.dev/docs/lintercop-migration/) are present wherever
    `${analyzerFolder}` in a project's `.vscode/settings.json` resolves, so
    `al.codeAnalyzers` entries like `${analyzerFolder}ALCops.LinterCop.dll`
    actually resolve.

    `${analyzerFolder}` is not just a VS Code-editor concept: al-mcp
    (.mcp.json) and the AL LSP server (.lsp.json) are both launched via
    al-launch.sh, which runs the SAME Microsoft.Dynamics.Nav.CodeAnalysis
    engine the VS Code AL extension embeds — headless, with no VS Code UI
    ever open to trigger the ALCops VS Code extension's own "download on
    first use". Relying solely on that extension would silently leave
    al-mcp/LSP running old/no analyzers. So this hook downloads the
    ALCops.Analyzers NuGet package directly and copies the DLLs into every
    analyzer folder found on the machine — the AL Language VS Code
    extension's `bin/Analyzers` directory(ies), the one place both the
    editor and al-mcp/LSP are known to read `${analyzerFolder}`-prefixed
    entries from (confirmed by finding the old BusinessCentral.LinterCop.dll
    living there).

    Also installs the ALCops VS Code extension (Arthurvdv.alcops) when the
    `code` CLI is available, so interactive editing gets ALCops' own
    update-tracking/notification UX on top of the DLLs this hook places.

    Idempotent and cheap on repeat runs: skips the network entirely once
    ALCops.LinterCop.dll is already present in every discovered analyzer
    folder. Emits the Copilot hook output contract on stdout.
#>
param([string]$Event = 'SessionStart')

$ErrorActionPreference = 'Continue'
$ExtensionId = 'Arthurvdv.alcops'
$Package = 'alcops.analyzers'
$Dlls = @(
    'ALCops.ApplicationCop.dll', 'ALCops.Common.dll', 'ALCops.DocumentationCop.dll',
    'ALCops.FormattingCop.dll', 'ALCops.LinterCop.dll', 'ALCops.PlatformCop.dll',
    'ALCops.TestAutomationCop.dll'
)

function Emit($text) {
    # $text must be free of " and \ so this stays valid JSON.
    Write-Output ('{"hookSpecificOutput":{"hookEventName":"' + $Event + '","additionalContext":"' + $text + '"}}')
}

# --- Part 1: VS Code extension, for the interactive editing experience ---
if (Get-Command code -ErrorAction SilentlyContinue) {
    $installedExtensions = & code --list-extensions 2>$null
    if (-not ($installedExtensions -match "^$([regex]::Escape($ExtensionId))$")) {
        & code --install-extension $ExtensionId *> $null
    }
}

# --- Part 2: the DLLs themselves, for al-mcp/LSP (and as a fallback for the
# editor, so headless environments don't depend on the extension activating) ---
$targetDirs = @(Get-ChildItem -Path "$HOME\.vscode\extensions" -Filter 'ms-dynamics-smb.al-*' -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'bin\Analyzers' } |
    Where-Object { Test-Path $_ })

if ($targetDirs.Count -eq 0) {
    # No AL Language VS Code extension installed at all — nothing to seed
    # yet; it will be installed by its own onboarding, and this hook will
    # catch up next session.
    exit 0
}

$needsDownload = $targetDirs | Where-Object { -not (Test-Path (Join-Path $_ 'ALCops.LinterCop.dll')) }
if (-not $needsDownload) {
    exit 0
}

# Emit() forbids backslashes (must stay valid JSON) — Windows paths use them.
$dirsList = ($targetDirs -join ', ') -replace '\\', '/'

try {
    $indexJson = Invoke-RestMethod -Uri "https://api.nuget.org/v3-flatcontainer/$Package/index.json" -TimeoutSec 15
    $version = ($indexJson.versions | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Select-Object -Last 1)
} catch {
    $version = $null
}

if (-not $version) {
    Emit "Could not reach NuGet.org to fetch the latest ALCops.Analyzers version, so the ALCops.*.dll analyzers referenced in .vscode/settings.json are still missing from $dirsList. Retry once network access is available, or install manually per https://alcops.dev/docs/downloading-analyzers/."
    exit 0
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $workDir | Out-Null
try {
    $nupkgPath = Join-Path $workDir 'alcops.nupkg'
    try {
        Invoke-WebRequest -Uri "https://api.nuget.org/v3-flatcontainer/$Package/$version/$Package.$version.nupkg" -OutFile $nupkgPath -TimeoutSec 30
    } catch {
        Emit "Downloading ALCops.Analyzers $version from NuGet.org failed, so the ALCops.*.dll analyzers are still missing from $dirsList. Retry next session, or install manually per https://alcops.dev/docs/downloading-analyzers/."
        exit 0
    }

    $extractDir = Join-Path $workDir 'extracted'
    try {
        Expand-Archive -Path $nupkgPath -DestinationPath $extractDir -Force
    } catch {
        Emit "Extracting the ALCops.Analyzers $version package failed, so the ALCops.*.dll analyzers are still missing from $dirsList. Retry next session, or install manually per https://alcops.dev/docs/downloading-analyzers/."
        exit 0
    }

    $sourceDir = Join-Path $extractDir 'lib\net8.0'
    foreach ($dir in $targetDirs) {
        foreach ($dll in $Dlls) {
            $src = Join-Path $sourceDir $dll
            if (Test-Path $src) {
                Copy-Item -Path $src -Destination (Join-Path $dir $dll) -Force
            }
        }
    }

    Emit "The ALCops.*.dll analyzers (v$version, successor to BusinessCentral.LinterCop) were missing and have been installed into: $dirsList. Reload any open AL project so al-mcp/the AL LSP server and the editor pick them up."
} finally {
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
