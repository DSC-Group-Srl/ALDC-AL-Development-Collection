<#
.SYNOPSIS
    ALDC rules-injection precondition hook (PowerShell) — Windows-native
    equivalent of precondition_hook.sh.

.DESCRIPTION
    Detects whether /aldc:al-initialize has already copied the always-on rule
    templates into this project's .claude/rules/ directory, and INJECTS a
    directive into the agent session via additionalContext. Same Layer-2
    precondition-hook design as tools/bcquality/precondition_hook.ps1.
    Emits the Copilot hook output contract on stdout. Messages avoid " and \
    so plain interpolation is valid JSON.

    NOTE (Preview): verify event-key casing / config props against your
    VS Code Copilot hook version.
#>
param([string]$Event = 'SessionStart')

$ErrorActionPreference = 'Continue'
$marker = '.claude/rules/al-guidelines.md'
$pluginRoot = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else { '.' }

function Emit($text) {
    # $text must be free of " and \ (kept that way below) so this stays valid JSON.
    Write-Output ('{"hookSpecificOutput":{"hookEventName":"' + $Event + '","additionalContext":"' + $text + '"}}')
}

if (Test-Path $marker) {
    Emit "ALDC rules are INSTALLED at .claude/rules/ (this project has run /aldc:al-initialize). Read the 7 always-on rule files from there once per session and pass them inline to every code-touching subagent (implement, review); do not re-run init and do not re-read the same rule file twice this session."
}
else {
    Emit "ALDC rules are NOT installed (no $marker). Before writing, editing, or reviewing any AL code this session, tell the user that /aldc:al-initialize has not been run for this project and offer to run it now - it copies the 7 always-on rule templates from $pluginRoot/rules-templates/ into .claude/rules/ so they persist and stay editable per project. Until the user responds, still apply the baselines yourself by reading them directly from $pluginRoot/rules-templates/al-*.md (excluding the conditional al-agent-toolkit) so no AL code is generated ungoverned. NEVER block or fail the task for the missing install - this is a human-in-the-loop nudge, not a hard gate."
}
