<#
.SYNOPSIS
    Node.js/npx bootstrap hook (PowerShell) — Windows-native equivalent of
    ensure-npx.sh.

.DESCRIPTION
    Ensures `npx` (bundled with Node.js) is installed and meets the
    nab-al-tools MCP server's minimum Node >= 20 requirement, so
    .mcp.json's "nab-al-tools" server
    (npx -y @nabsolutions/nab-al-tools-mcp@next) has something to run.
    Emits the Copilot hook output contract on stdout, same shape as
    tools/al-cli/ensure-al-tool.ps1.
#>
param([string]$Event = 'SessionStart')

$ErrorActionPreference = 'Continue'
$MinNodeMajor = 20

function Emit($text) {
    # $text must be free of " and \ so this stays valid JSON.
    Write-Output ('{"hookSpecificOutput":{"hookEventName":"' + $Event + '","additionalContext":"' + $text + '"}}')
}

if (Get-Command npx -ErrorAction SilentlyContinue) {
    $nodeVersion = (& node --version 2>$null)
    if ($nodeVersion -match '^v(\d+)') {
        $nodeMajor = [int]$Matches[1]
        if ($nodeMajor -lt $MinNodeMajor) {
            Emit "npx is installed but Node.js is $nodeVersion, below the v$MinNodeMajor the nab-al-tools MCP server (.mcp.json) requires. Left untouched in case a version manager (nvm-windows/fnm/volta) manages it - tell the user to upgrade Node.js to >= $MinNodeMajor, then restart the session."
        }
    }
    exit 0
}

if (Get-Command node -ErrorAction SilentlyContinue) {
    # A Node.js binary exists but npx does not - this is a broken/partial
    # install (commonly a version manager like nvm-windows/fnm whose active
    # version was installed without npm bundled). Do NOT auto-install a
    # second, competing Node.js here: that would silently create a PATH
    # conflict with whatever the user's version manager is doing. Report it
    # and let the human fix the version manager's install instead.
    $nodeVersion = (& node --version 2>$null)
    Emit "node ($nodeVersion) is on PATH but npx is not - looks like a broken or partial Node.js install (common with version managers like nvm-windows/fnm whose active version was installed without npm bundled). Left untouched rather than auto-installing a second, competing Node.js. The nab-al-tools MCP server (.mcp.json) will not start until npm/npx is restored for this Node install (e.g. reinstall/repair the active version via your version manager) - tell the user."
    exit 0
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
    & winget install --id OpenJS.NodeJS.LTS -e --silent --accept-package-agreements --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) {
        Emit "npx was missing and Node.js was just installed via 'winget install OpenJS.NodeJS.LTS'. The nab-al-tools MCP server (.mcp.json) needs it - restart this session so the refreshed PATH takes effect."
        exit 0
    }
}

Emit "npx (the 'npx' command, bundled with Node.js >= $MinNodeMajor) is not installed and could not be auto-installed (winget install failed or is unavailable). The nab-al-tools MCP server (.mcp.json) will not start until Node.js >= $MinNodeMajor is installed from https://nodejs.org or winget."
