<#
.SYNOPSIS
    Git Bash resolution self-healer (PowerShell, Windows-only) for the
    WSL-bash-stub problem.

.DESCRIPTION
    This plugin's SessionStart hooks, the al-mcp MCP server (.mcp.json), and
    the AL LSP server (.lsp.json) all invoke the bare executable "bash" to run
    their launcher scripts. On many Windows machines, "bash" resolves to the
    WSL stub at C:\Windows\System32\bash.exe (which errors out if no WSL
    distro is installed) instead of Git for Windows' real bash.exe, because
    Claude Code falls back to a plain PATH lookup for "bash" whenever its own
    Git Bash auto-detection doesn't succeed.

    This hook is deliberately PowerShell-only and never calls "bash" itself,
    so it is immune to the exact bug it's diagnosing. It locates a real Git
    Bash on this machine and, if bash currently resolves to the WSL stub (or
    to nothing), tries to RECTIFY it automatically by writing
    env.CLAUDE_CODE_GIT_BASH_PATH into the user's global ~/.claude/settings.json
    - the officially supported override Claude Code reads to pick the right
    bash for hooks, MCP, and LSP command execution. Only if that write fails
    (permissions, unparsable existing file, etc.) does it fall back to
    injecting a directive so the agent can warn the user and offer the fix
    manually - same Layer-2 precondition-hook pattern as
    tools/bcquality/precondition_hook.ps1 and tools/rules/precondition_hook.ps1.

    Idempotent: once ~/.claude/settings.json has a working path recorded, or
    "bash" already resolves correctly on PATH, this exits silently and does
    not touch the file again. No-ops silently on non-Windows.
#>
param([string]$Event = 'SessionStart')

if (Test-Path variable:IsWindows) {
    if (-not $IsWindows) { exit 0 }
} elseif ($env:OS -ne 'Windows_NT') {
    exit 0
}

$ErrorActionPreference = 'Continue'

$backslash = [string][char]92
$doubleBackslash = $backslash + $backslash

function Emit($text) {
    # $text must be free of " and \ (already escaped by caller) so this stays valid JSON.
    Write-Output ('{"hookSpecificOutput":{"hookEventName":"' + $Event + '","additionalContext":"' + $text + '"}}')
}

function Escape($text) {
    $text.Replace($backslash, $doubleBackslash)
}

$settingsPath = Join-Path $HOME '.claude\settings.json'

# 1. Already configured on disk with a path that still exists? Nothing to do -
#    whether or not this particular process picked it up yet is not our concern.
$configuredPath = $null
$settings = $null
$settingsParsed = $true
if (Test-Path $settingsPath) {
    try {
        $raw = Get-Content -Raw -Path $settingsPath -ErrorAction Stop
        if ($raw -and $raw.Trim()) {
            $settings = $raw | ConvertFrom-Json -ErrorAction Stop
        }
    } catch {
        $settingsParsed = $false
    }
}
if ($settings -and ($settings.PSObject.Properties.Name -contains 'env') -and $settings.env) {
    if ($settings.env.PSObject.Properties.Name -contains 'CLAUDE_CODE_GIT_BASH_PATH') {
        $configuredPath = $settings.env.CLAUDE_CODE_GIT_BASH_PATH
    }
}
if ($configuredPath -and (Test-Path $configuredPath)) { exit 0 }

# 2. bash already resolves correctly via plain PATH? Nothing to do.
$resolved = (Get-Command bash.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$isStub = $resolved -and ($resolved -like '*\System32\*')
if ($resolved -and -not $isStub) { exit 0 }

$seenText = if ($resolved) { Escape $resolved } else { 'nothing on PATH' }

# 3. Broken (or missing) - look for a real Git Bash to rectify with.
$candidates = New-Object System.Collections.Generic.List[string]
if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Git\bin\bash.exe')) }
if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe')) }
if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe')) }
if ($env:LocalAppData) { $candidates.Add((Join-Path $env:LocalAppData 'Programs\Git\bin\bash.exe')) }

$gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($gitCmd) {
    $gitCmdDir = Split-Path $gitCmd.Source -Parent
    $gitRoot = Split-Path $gitCmdDir -Parent
    $candidates.Add((Join-Path $gitRoot 'bin\bash.exe'))
}

$found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $found) {
    Emit "bash currently resolves to $seenText (looks like the WSL stub, not Git Bash), which breaks this plugin's SessionStart hooks, the al-mcp MCP server, and the AL LSP server. No Git for Windows install was found in common locations either, so this could not be auto-fixed. Tell the user their AL plugin hooks/MCP/LSP may fail until they install Git for Windows or locate their existing bash.exe (usually under the Git install dir's bin folder) and set it as env.CLAUDE_CODE_GIT_BASH_PATH in ~/.claude/settings.json. NEVER block or fail the task for this - it is a human-in-the-loop nudge, not a hard gate."
    exit 0
}

# 4. Try to rectify automatically: merge env.CLAUDE_CODE_GIT_BASH_PATH into the
#    global settings.json without disturbing anything else in it.
$fixed = $false
$fixError = $null
if (-not $settingsParsed) {
    $fixError = 'existing ~/.claude/settings.json could not be parsed as JSON'
} else {
    try {
        if (-not $settings) { $settings = [PSCustomObject]@{} }

        if (-not ($settings.PSObject.Properties.Name -contains 'env') -or $null -eq $settings.env -or $settings.env -isnot [System.Management.Automation.PSCustomObject]) {
            if ($settings.PSObject.Properties.Name -contains 'env') {
                $settings.env = [PSCustomObject]@{}
            } else {
                $settings | Add-Member -MemberType NoteProperty -Name 'env' -Value ([PSCustomObject]@{})
            }
        }
        if ($settings.env.PSObject.Properties.Name -contains 'CLAUDE_CODE_GIT_BASH_PATH') {
            $settings.env.CLAUDE_CODE_GIT_BASH_PATH = $found
        } else {
            $settings.env | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_GIT_BASH_PATH' -Value $found
        }

        $json = $settings | ConvertTo-Json -Depth 50
        $settingsDir = Split-Path $settingsPath -Parent
        if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force -ErrorAction Stop | Out-Null }
        Set-Content -Path $settingsPath -Value $json -Encoding utf8 -ErrorAction Stop
        $fixed = $true
    } catch {
        $fixError = $_.Exception.Message
    }
}

$escapedFound = Escape $found

if ($fixed) {
    Emit "bash was resolving to $seenText (the WSL stub, not Git Bash), which breaks this plugin's SessionStart hooks, the al-mcp MCP server, and the AL LSP server. This has been auto-fixed: env.CLAUDE_CODE_GIT_BASH_PATH was set to $escapedFound in the user's global ~/.claude/settings.json. Tell the user this was corrected automatically and that a new Claude Code session is needed for it to take effect. NEVER block or fail the task for this - it is a human-in-the-loop nudge, not a hard gate."
} else {
    Emit "bash currently resolves to $seenText (the WSL stub, not Git Bash), which breaks this plugin's SessionStart hooks, the al-mcp MCP server, and the AL LSP server. Found a working Git Bash at $escapedFound but could not automatically update ~/.claude/settings.json ($fixError). Tell the user and offer to set env.CLAUDE_CODE_GIT_BASH_PATH to $escapedFound there themselves. NEVER block or fail the task for this - it is a human-in-the-loop nudge, not a hard gate."
}
