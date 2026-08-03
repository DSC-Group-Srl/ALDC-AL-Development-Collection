<#
.SYNOPSIS
    BCQuality precondition hook (PowerShell) — Windows-native equivalent of
    precondition_hook.sh.

.DESCRIPTION
    Detects whether the shared BCQuality knowledge base is present, auto-installs
    it on first use, and keeps it refreshed in the background. INJECTS a directive
    into the agent session via additionalContext.

    USER-SCOPE, NOT PROJECT-SCOPE. The clone lives ONCE at ~/.claude/bcquality
    (override: $env:BCQUALITY_HOME) and is shared by every AL project on this
    machine — no more "../bcquality" sibling folder cluttering each project.
    First run clones it in the background (this session still runs the native
    A-G checklist, since the clone isn't ready yet); later runs fetch a fresh
    copy in the background at most once every
    $env:BCQUALITY_UPDATE_INTERVAL_HOURS (default 12h). The background job never
    blocks or fails the session, even fully offline.

    A project's aldc.yaml (if present) can still override home/entryPoint/url/
    ref/pinnedCommit for advanced/pinned use, but is no longer required.

    Emits the Copilot hook output contract on stdout. Messages avoid " and \ so
    plain interpolation is valid JSON.
#>
param([string]$Event = 'SessionStart')

$ErrorActionPreference = 'Continue'
$aldc = 'aldc.yaml'

$url = 'https://github.com/microsoft/BCQuality.git'
$ref = 'main'
$pin = ''
$entry = 'skills/entry.md'
# NOTE: $HOME is a PowerShell built-in read-only variable — our own path lives
# in $bcqHome, never reuse the name "home" for an assignable variable here.
$defaultHome = Join-Path $HOME '.claude/bcquality'

if (Test-Path $aldc) {
    $h = (Select-String -Path $aldc -Pattern '^\s*home:\s*"?([^"#]+)"?' -AllMatches | Select-Object -First 1).Matches.Groups[1].Value
    $e = (Select-String -Path $aldc -Pattern '^\s*entryPoint:\s*"?([^"#]+)"?' -AllMatches | Select-Object -First 1).Matches.Groups[1].Value
    $u = (Select-String -Path $aldc -Pattern '^\s*url:\s*"?([^"#]+)"?' -AllMatches | Select-Object -First 1).Matches.Groups[1].Value
    $r = (Select-String -Path $aldc -Pattern '^\s*ref:\s*"?([^"#]+)"?' -AllMatches | Select-Object -First 1).Matches.Groups[1].Value
    $p = (Select-String -Path $aldc -Pattern '^\s*pinnedCommit:\s*"?([^"#]*)"?' -AllMatches | Select-Object -First 1).Matches.Groups[1].Value
    if ($h) { $defaultHome = $h.Trim() }
    if ($e) { $entry = $e.Trim() }
    if ($u) { $url = $u.Trim() }
    if ($r) { $ref = $r.Trim() }
    if ($p) { $pin = $p.Trim() }
}

$bcqHome = if ($env:BCQUALITY_HOME) { $env:BCQUALITY_HOME } else { $defaultHome }
$entrypath = Join-Path $bcqHome $entry
$target = if ($pin) { $pin } else { $ref }
$intervalH = if ($env:BCQUALITY_UPDATE_INTERVAL_HOURS) { [int]$env:BCQUALITY_UPDATE_INTERVAL_HOURS } else { 12 }
$lockdir = "$bcqHome.lock"
$stamp = "$bcqHome.last-check"
$logfile = "$bcqHome.log"
$errfile = "$bcqHome.log.err"
$syncscript = "$bcqHome.sync.ps1"

function Emit($text) {
    # $text must be free of " and \ (kept that way below) so this stays valid JSON.
    Write-Output ('{"hookSpecificOutput":{"hookEventName":"' + $Event + '","additionalContext":"' + $text + '"}}')
}

function Acquire-Lock {
    try { New-Item -ItemType Directory -Path $lockdir -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

# Writes a standalone sync script (paths baked in) and launches it as a genuinely
# separate, hidden process via Start-Process — it outlives this hook process
# regardless of whether the hook's own host exits right after emitting output.
function Spawn-BackgroundSync {
    $body = @"
`$ErrorActionPreference = 'Continue'
try {
    [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() | Out-File -FilePath '$stamp' -Encoding ascii -Force
    if (-not (Test-Path '$bcqHome')) { New-Item -ItemType Directory -Path '$bcqHome' -Force | Out-Null }
    if (-not (Test-Path (Join-Path '$bcqHome' '.git'))) {
        git init --quiet '$bcqHome'
        git -C '$bcqHome' remote add origin '$url'
    }
    # Windows/NTFS: BCQuality's nested knowledge paths can exceed MAX_PATH (260)
    # under a deep user profile; without this, checkout silently drops files.
    git -C '$bcqHome' config core.longpaths true
    git -C '$bcqHome' fetch --quiet --depth 1 origin '$target'
    if (`$LASTEXITCODE -ne 0) {
        git -C '$bcqHome' fetch --quiet --depth 1 origin '$ref'
    }
    git -C '$bcqHome' checkout --quiet --detach FETCH_HEAD
}
finally {
    Remove-Item -Path '$lockdir' -Recurse -Force -ErrorAction SilentlyContinue
}
"@
    Set-Content -Path $syncscript -Value $body -Encoding utf8
    Start-Process -FilePath 'powershell' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $syncscript) `
        -WindowStyle Hidden -RedirectStandardOutput $logfile -RedirectStandardError $errfile | Out-Null
}

if (Test-Path $entrypath) {
    $sha = (git -C $bcqHome rev-parse --short HEAD 2>$null)
    if (-not $sha) { $sha = 'unknown' }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $last = 0
    if (Test-Path $stamp) { $last = [int64](Get-Content $stamp -Raw -ErrorAction SilentlyContinue) }
    $ageH = [math]::Floor(($now - $last) / 3600)
    if ($ageH -ge $intervalH -and (Acquire-Lock)) {
        Spawn-BackgroundSync
        Emit "BCQuality is PRESENT at $bcqHome (SHA $sha, one shared user-scope cache reused by every project). A background refresh just started (last synced ${ageH}h ago); this session still uses SHA $sha unaffected. Treat it as the citation source of truth for review/audit: read $entry and follow its entry then read then do dispatch; record the SHA in your report."
    }
    else {
        Emit "BCQuality is PRESENT at $bcqHome (SHA $sha, one shared user-scope cache reused by every project, last synced ${ageH}h ago). Treat it as the citation source of truth for review/audit: read $entry and follow its entry then read then do dispatch; record the SHA in your report."
    }
}
else {
    $gitAvailable = [bool](Get-Command git -ErrorAction SilentlyContinue)
    if ($gitAvailable -and (Acquire-Lock)) {
        Spawn-BackgroundSync
        Emit "BCQuality is not installed yet. A one-time background install just started at $bcqHome - a shared, user-scope cache reused by every project on this machine, not a per-project clone. It will not be ready this session. Apply the BCQuality precondition: set bcquality.outcome to not-applicable, skip the BCQuality consultation, and review natively via the FULL A-G checklist (reactivate B Naming via al-naming-conventions, D Performance via al-performance plus skill-performance, E Error-handling via al-error-handling, and the commit-in-subscriber part of A via al-events; permissions via skill-permissions). Cap confidence at medium; secrets and security have no native check. NEVER block or fail the review for the missing layer. It should be ready on your next session."
    }
    else {
        Emit "BCQuality is ABSENT (no $entrypath) and could not be auto-installed right now - git is missing, or an install/refresh from another session is already in flight. Apply the BCQuality precondition: set bcquality.outcome to not-applicable, skip the BCQuality consultation, and review natively via the FULL A-G checklist (reactivate B Naming via al-naming-conventions, D Performance via al-performance plus skill-performance, E Error-handling via al-error-handling, and the commit-in-subscriber part of A via al-events; permissions via skill-permissions). Cap confidence at medium; secrets and security have no native check. NEVER block or fail the review for the missing layer. This is the pre-BCQuality ALDC review, not a stub."
    }
}
