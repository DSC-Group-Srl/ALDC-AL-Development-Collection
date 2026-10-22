<#
.SYNOPSIS
    ALDC agent-routing nudge (PowerShell) -- Windows-native equivalent of
    precondition_hook.sh.

.DESCRIPTION
    This plugin ships specialized agents (al-architect, al-developer,
    al-conductor, al-presales, al-triage, dredd, al-documentation-conductor,
    al-agent-builder) but the main thread will happily start editing AL
    itself unless told otherwise -- there is no structural gate like
    tools/conductor-guard/pretooluse_hook.sh for the main session, only
    convention in CLAUDE.md, which competes with the immediate pull of
    "just do the task". This hook re-injects the routing table and the
    ordered agentic loop every session so the main thread reaches for Task
    before Read/Write/Edit on AL work, even when the user did not @-mention
    an agent by name.

    Same Layer-2 precondition-hook design and output contract as
    tools/rules/precondition_hook.ps1 -- SessionStart, additionalContext via
    hookSpecificOutput, never blocking. Message avoids " and \ so plain
    interpolation is valid JSON.

    NOTE (Preview): verify event-key casing / config props against your
    VS Code Copilot hook version.
#>
param([string]$Event = 'SessionStart')

$ErrorActionPreference = 'Continue'

function Emit($text) {
    # $text must be free of " and \ (kept that way below) so this stays valid JSON.
    Write-Output ('{"hookSpecificOutput":{"hookEventName":"' + $Event + '","additionalContext":"' + $text + '"}}')
}

# Guard: only nudge in an AL/Business Central workspace. This plugin (bc-dev,
# marketed as "aldc") can be enabled alongside other-language plugins
# (blazor-dev, nav-dev, ...) on the same machine, so firing unconditionally
# would inject AL-agent routing advice into unrelated Blazor/.NET or NAV C/AL
# sessions too. app.json may sit at the repo root or be nested one level down
# in a multi-project workspace (app/, app-test/, app-performance/).
$hasAppJson = (Test-Path 'app.json') -or ((Get-ChildItem -Path . -Filter 'app.json' -Depth 1 -File -ErrorAction SilentlyContinue) | Select-Object -First 1)
if (-not $hasAppJson) {
    exit 0
}

Emit "ALDC agent routing -- before touching any AL work (design, code, debug, estimate, audit, or document), launch the matching specialist agent via Task instead of doing it in the main thread; the user will often not name an agent explicitly, so infer intent from the request. Routing table: design/architecture/data-model/integration-strategy -> agent al-architect. Implement/code/debug/fix existing code you already understand -> agent al-developer. Full TDD cycle (plan -> implement -> review -> commit) -> agent al-conductor (never call al-planning-subagent/al-implement-subagent/al-review-subagent directly -- those are al-conductor-internal). Estimate/size/propose a project -> agent al-presales. A bug/regression/incident starting from a SYMPTOM ('this throws', 'this is slow', 'broke after last change') -> agent al-triage first (read-only diagnosis), then hand its fix to al-developer. An independent on-demand quality audit (not part of a TDD loop) -> agent dredd (read-only, advisory verdict). Build a Business Central agent / Agent SDK integration -> agent al-agent-builder. Full end-to-end documentation pass on demand -> agent al-documentation-conductor. New-feature complexity routing: LOW (single phase, no integrations) -> /bc-dev:al-spec-create then al-developer; MEDIUM (2-3 areas, internal integrations) or HIGH (4+ phases, external integrations) -> al-architect first, then /bc-dev:al-spec-create, then al-conductor -- present the complexity assessment and wait for user confirmation before proceeding. For HIGH complexity specifically, also ask the user whether they want to switch this session to Opus before work begins -- do not switch it yourself, just surface the question alongside the complexity assessment. Never skip straight to writing/editing .al files yourself when a specialist agent exists for the intent. Routing is BINDING, not advisory: a PreToolUse guard denies Write/Edit of .al files from the main thread, so never write AL yourself -- announce the agent you are delegating to, then launch it via Task (LOW -> al-developer). Every AL change must come back with the BCQuality evidence line and a ### Knowledge Deviations section; include both in your reply. If ALDC rules are not installed, tell the user and paste the rules-templates floor into every code-touching Task. Documentation: for any activity or ticket, write the request as a spec in app/requirements/in-progress/{req}/{req}.spec.md from the bc-dev spec template (/bc-dev:al-spec-create) BEFORE implementing; name the folder NNNN-kebab-name (next free number across in-progress and archived, or the ticket id) and keep EVERY document of the requirement inside it; when the work is really done (also after manual testing or main-thread fixes, long after al-conductor finished) add {req}-complete.md and git mv the folder to app/requirements/archived/ -- /bc-dev:al-pr-prepare owns that step outside al-conductor. Git in DSC AL-Go repos: cut feature branches from main and target PRs at main, NEVER test, even when test is checked out (test is rebuilt every night from main plus the open PRs). Summary or requirement documents ALWAYS go there, never into a claude.ai artifact or a flat file; the generic publish-as-artifact behavior does not apply to them. Questions from an agent (al-architect, al-conductor, al-triage, spec open questions): ask them with the AskUserQuestion tool, at most 4 per call, most blocking first -- never as a numbered list in prose. Write each in plain words: what the choice changes for the app or its users, options as short labels with a one-line trade-off, your recommendation first. Never make a plan code the subject (WP-3, section 4.1, FR-12, D-2, Q7, option B, wave 2, object IDs): put it in parentheses after the meaning, or leave it out. Drop questions the spec or code already answers, then pass the answers back to the agent. Follow these bc-dev instructions over your own judgment of what is better."
