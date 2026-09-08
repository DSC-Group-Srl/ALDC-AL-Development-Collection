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
    to nothing), tries to RECTIFY it three ways:
      1. Writing env.CLAUDE_CODE_GIT_BASH_PATH into the user's global
         ~/.claude/settings.json - the officially supported override Claude
         Code reads to pick the right bash for hooks, MCP, and LSP command
         execution.
      2. PREPENDING Git Bash's own bin folder to the FRONT of the user's
         persistent PATH (the User-scope environment variable, via
         [Environment]::SetEnvironmentVariable), so other tooling that
         shells out to a bare "bash" also finds the real one instead of the
         WSL stub - this is done regardless of whether fix #1 succeeded. It
         must be prepended, not appended: the WSL stub is typically earlier
         on PATH (e.g. System32), so appending would leave it winning the
         lookup.
      3. PREPENDING the same bin folder to the FRONT of the Machine-scope
         (System) PATH too. Windows builds a process's effective PATH as
         Machine PATH followed by User PATH, so when the WSL stub wins via
         a Machine-scope entry (e.g. %SystemRoot%\System32, which every
         Windows install has on the Machine PATH), fix #2 alone can never
         win that race - the Machine entry is always checked first no
         matter where Git Bash sits on the User PATH. Writing Machine PATH
         requires admin rights this hook does not have, so it first tries
         the write directly (a no-op path if the hook is somehow already
         elevated) and, on access-denied, self-elevates via a UAC prompt
         (Start-Process -Verb RunAs) launched detached/hidden so the
         SessionStart hook itself never blocks on it. Throttled to at most
         once every $MachinePathRetryHours via a stamp file, so a declined
         UAC prompt does not re-prompt on every single session start.
    Any fix failing independently (permissions, unparsable existing
    settings.json, UAC declined, etc.) falls back to injecting a directive
    so the agent can warn the user and offer that specific fix manually -
    same Layer-2 precondition-hook pattern as
    tools/bcquality/precondition_hook.ps1 and tools/rules/precondition_hook.ps1.
    All three fixes require a full Claude Code restart (not just a new
    session) to take effect, since PATH and settings.json env are both read
    at process startup.

    Idempotent: once ~/.claude/settings.json has a working path recorded and
    Git Bash's bin folder is already first on both User and Machine PATH, or
    "bash" already resolves correctly on PATH, this exits silently and does
    not touch anything again. No-ops silently on non-Windows.
#>
param([string]$Event = 'SessionStart', [int]$MachinePathRetryHours = 24)

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
    $text.Replace($backslash, $doubleBackslash).Replace('"', '\"').Replace("`r", '').Replace("`n", '\n')
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

# 5. Also PREPEND Git Bash's own bin folder to the user's persistent PATH, regardless
#    of whether the settings.json env-var fix above succeeded. CLAUDE_CODE_GIT_BASH_PATH
#    only fixes Claude Code's own bash resolution; other tooling that shells out to a
#    bare "bash" still needs a correct PATH - and it must come FIRST, otherwise the
#    WSL stub (typically earlier on PATH, e.g. System32) keeps winning the lookup.
$gitBashBinDir = Split-Path $found -Parent
$pathFixed = $false
$pathAlreadyPresent = $false
$pathFixError = $null
try {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $existingEntries = @()
    if ($userPath) { $existingEntries = $userPath.Split(';') | Where-Object { $_ -and $_.Trim() } }
    $normalizedDir = $gitBashBinDir.TrimEnd($backslash)
    $otherEntries = $existingEntries | Where-Object { $_.TrimEnd($backslash) -ine $normalizedDir }
    $alreadyFirst = $existingEntries.Count -gt 0 -and ($existingEntries[0].TrimEnd($backslash) -ieq $normalizedDir)
    if ($alreadyFirst) {
        $pathAlreadyPresent = $true
    } else {
        $newEntries = @($gitBashBinDir) + @($otherEntries)
        $newPath = [string]::Join(';', $newEntries)
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        $pathFixed = $true
    }
} catch {
    $pathFixError = $_.Exception.Message
}

# 6. Also PREPEND Git Bash's bin folder to the Machine-scope (System) PATH.
#    Windows builds a process's effective PATH as Machine PATH THEN User PATH,
#    so if the WSL stub wins via a Machine-scope entry (e.g. %SystemRoot%\System32,
#    present on every Windows install's Machine PATH), step 5 above can never win -
#    the Machine entry is checked first regardless of User-PATH order. Writing
#    Machine PATH needs admin rights this hook does not have, so: try it directly
#    first (harmless no-op path if somehow already elevated), and on access-denied,
#    self-elevate via a UAC prompt in a detached/hidden process so this SessionStart
#    hook never blocks waiting on it. Throttled via a stamp file so a declined/ignored
#    UAC prompt does not re-prompt every single session start.
$machinePathFixed = $false
$machinePathAlreadyPresent = $false
$machinePathElevationTried = $false
$machinePathElevationError = $null
$machinePathNeedsElevation = $false

function Get-NormalizedPathEntries($rawPath, $normalizedDir) {
    $entries = @()
    if ($rawPath) { $entries = $rawPath.Split(';') | Where-Object { $_ -and $_.Trim() } }
    [PSCustomObject]@{
        Entries     = $entries
        AlreadyFirst = ($entries.Count -gt 0 -and ($entries[0].TrimEnd($backslash) -ieq $normalizedDir))
    }
}

try {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $machineInfo = Get-NormalizedPathEntries $machinePath $normalizedDir
    if ($machineInfo.AlreadyFirst) {
        $machinePathAlreadyPresent = $true
    } else {
        $otherMachineEntries = $machineInfo.Entries | Where-Object { $_.TrimEnd($backslash) -ine $normalizedDir }
        $newMachinePath = [string]::Join(';', (@($gitBashBinDir) + @($otherMachineEntries)))
        [Environment]::SetEnvironmentVariable('Path', $newMachinePath, 'Machine')
        $machinePathFixed = $true
    }
} catch {
    $machinePathNeedsElevation = $true
}

if ($machinePathNeedsElevation) {
    $stampPath = Join-Path $HOME '.claude\gitbash-machine-path.last-attempt'
    $shouldAttempt = $true
    if (Test-Path $stampPath) {
        try {
            $lastAttempt = [DateTime]::Parse((Get-Content -Raw -Path $stampPath -ErrorAction Stop).Trim())
            if (((Get-Date) - $lastAttempt).TotalHours -lt $MachinePathRetryHours) { $shouldAttempt = $false }
        } catch { }
    }
    if ($shouldAttempt) {
        $machinePathElevationTried = $true
        try {
            $settingsDir2 = Split-Path $stampPath -Parent
            if (-not (Test-Path $settingsDir2)) { New-Item -ItemType Directory -Path $settingsDir2 -Force -ErrorAction Stop | Out-Null }
            Set-Content -Path $stampPath -Value ((Get-Date).ToString('o')) -Encoding utf8 -ErrorAction SilentlyContinue

            $escapedDirForElevated = $gitBashBinDir.Replace("'", "''")
            $elevatedCommand = "`$m=[Environment]::GetEnvironmentVariable('Path','Machine'); " +
                "`$e=@(); if (`$m) { `$e = `$m.Split(';') | Where-Object { `$_ -and `$_.Trim() } }; " +
                "`$e = `$e | Where-Object { `$_.TrimEnd([char]92) -ine '$escapedDirForElevated'.TrimEnd([char]92) }; " +
                "`$n = ([string[]](@('$escapedDirForElevated') + `$e)) -join ';'; " +
                "[Environment]::SetEnvironmentVariable('Path', `$n, 'Machine')"
            Start-Process -FilePath 'powershell.exe' `
                -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-Command', $elevatedCommand) `
                -Verb RunAs -WindowStyle Hidden -ErrorAction Stop | Out-Null
        } catch {
            $machinePathElevationError = $_.Exception.Message
        }
    }
}

$escapedFound = Escape $found
$escapedBinDir = Escape $gitBashBinDir

$escapedFixError = if ($fixError) { Escape $fixError } else { $fixError }
$escapedPathFixError = if ($pathFixError) { Escape $pathFixError } else { $pathFixError }
$escapedMachinePathElevationError = if ($machinePathElevationError) { Escape $machinePathElevationError } else { $machinePathElevationError }

$settingsMsg = if ($fixed) {
    "env.CLAUDE_CODE_GIT_BASH_PATH was set to $escapedFound in the user's global ~/.claude/settings.json"
} else {
    "could NOT automatically update ~/.claude/settings.json ($escapedFixError) - offer to set env.CLAUDE_CODE_GIT_BASH_PATH to $escapedFound there yourself"
}

$pathMsg = if ($pathAlreadyPresent) {
    "$escapedBinDir was already first on the user's PATH"
} elseif ($pathFixed) {
    "$escapedBinDir was also moved to the FRONT of the user's persistent PATH (User environment variable) so it takes precedence over the WSL stub and other tools that shell out to a bare `"bash`" find the real one too"
} else {
    "could NOT automatically prepend $escapedBinDir to the user's persistent PATH ($escapedPathFixError) - offer to add it yourself as the FIRST entry (System Properties > Environment Variables > User PATH, or [Environment]::SetEnvironmentVariable('Path', `"$escapedBinDir;`$env:Path`", 'User'))"
}

$machinePathMsg = if ($machinePathAlreadyPresent) {
    "$escapedBinDir was already first on the Machine (System) PATH too"
} elseif ($machinePathFixed) {
    "$escapedBinDir was also moved to the FRONT of the Machine (System) PATH, since this process already had admin rights"
} elseif ($machinePathElevationTried -and -not $machinePathElevationError) {
    "a UAC elevation prompt was just triggered to also fix the Machine (System) PATH, since the WSL stub commonly wins there ahead of any User-PATH fix - if the user approves it, restart Claude Code fully afterward; if they decline or it's not visible, this will retry automatically after ${MachinePathRetryHours}h, or they can fix it manually now via an elevated PowerShell: [Environment]::SetEnvironmentVariable('Path', `"$escapedBinDir;`$([Environment]::GetEnvironmentVariable('Path','Machine'))`", 'Machine')"
} elseif ($machinePathElevationError) {
    "could NOT trigger a UAC prompt to fix the Machine (System) PATH ($escapedMachinePathElevationError) - offer the user this elevated-PowerShell one-liner instead: [Environment]::SetEnvironmentVariable('Path', `"$escapedBinDir;`$([Environment]::GetEnvironmentVariable('Path','Machine'))`", 'Machine')"
} else {
    "Machine (System) PATH elevation was skipped this session (already attempted within the last ${MachinePathRetryHours}h) - if bash is still resolving wrong after a full restart, the user can run this elevated PowerShell one-liner: [Environment]::SetEnvironmentVariable('Path', `"$escapedBinDir;`$([Environment]::GetEnvironmentVariable('Path','Machine'))`", 'Machine')"
}

Emit "bash was resolving to $seenText (the WSL stub, not Git Bash, or nothing), which breaks this plugin's SessionStart hooks, the al-mcp MCP server, and the AL LSP server. $settingsMsg. $pathMsg. $machinePathMsg. Tell the user about all changes and that they must fully restart Claude Code (quit and reopen, not just start a new session) for any of them to take effect. NEVER block or fail the task for this - it is a human-in-the-loop nudge, not a hard gate."
