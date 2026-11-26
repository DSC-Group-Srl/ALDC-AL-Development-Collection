$ErrorActionPreference = 'Stop'
$MinNodeMajor = 20

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$nodePath = if ($node) { $node.Source } else { $null }
if (-not $nodePath) {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
        $(if ($env:NVM_SYMLINK) { Join-Path $env:NVM_SYMLINK 'node.exe' }),
        (Join-Path $env:LOCALAPPDATA 'Volta\bin\node.exe')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { $nodePath = $candidate; break }
    }
}
if (-not $nodePath) {
    [Console]::Error.WriteLine("al-lint: Node.js not found (PATH, Program Files, nvm, volta). Install Node.js >= $MinNodeMajor; the SessionStart hook tools/nodejs/ensure-npx.ps1 tries to. The static pass did not run.")
    exit 1
}

$nodeVersion = (& $nodePath --version 2>$null)
if (-not ($nodeVersion -match '^v(\d+)') -or [int]$Matches[1] -lt $MinNodeMajor) {
    [Console]::Error.WriteLine("al-lint: Node.js $nodeVersion at $nodePath is below v$MinNodeMajor. The static pass did not run.")
    exit 1
}

& $nodePath (Join-Path $PSScriptRoot 'dsc-al-lint.mjs') @args
exit $LASTEXITCODE
