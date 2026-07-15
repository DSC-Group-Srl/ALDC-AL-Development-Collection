<#
.SYNOPSIS
    AL CLI bootstrap hook (PowerShell) — Windows-native equivalent of
    ensure-al-tool.sh.

.DESCRIPTION
    Ensures the `al` command (ALTool, from the
    Microsoft.Dynamics.BusinessCentral.Development.Tools NuGet package) is
    actually installed, so al-launch.sh (invoked by the plugin's al-mcp MCP
    server in .mcp.json and the AL LSP server in .lsp.json) has something to
    find. This hook only checks/installs the tool — it does not resolve PATH
    for Claude Code, since Claude Code's own resolver silently drops `al`
    when it lives under $HOME (see al-launch.sh for the workaround). Emits
    the Copilot hook output contract on stdout.
#>
param([string]$Event = 'SessionStart')

$ErrorActionPreference = 'Continue'

function Emit($text) {
    # $text must be free of " and \ so this stays valid JSON.
    Write-Output ('{"hookSpecificOutput":{"hookEventName":"' + $Event + '","additionalContext":"' + $text + '"}}')
}

if (Get-Command al -ErrorAction SilentlyContinue) {
    exit 0
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Emit "The AL CLI ('al' command) is not installed and .NET is not on PATH, so it cannot be auto-installed. al-mcp (.mcp.json) and the AL LSP server (.lsp.json) will not start. Install the .NET 8+ SDK, then run: dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools"
    exit 0
}

& dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools *> $null
if ($LASTEXITCODE -eq 0) {
    Emit "The AL CLI was missing and has been installed via 'dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools'. If al-mcp or the AL LSP server did not start this session, restart it so the refreshed PATH takes effect."
} else {
    Emit "The AL CLI ('al' command) is not installed and automatic install via 'dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools' failed. Run that command manually (check that the NuGet.org source is configured) - al-mcp and the AL LSP server will not start until it succeeds."
}
