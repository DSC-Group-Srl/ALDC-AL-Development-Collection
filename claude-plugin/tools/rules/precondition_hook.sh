#!/usr/bin/env bash
#
# ALDC rules-injection precondition hook — detects whether /aldc:al-initialize
# has already copied the always-on rule templates into this project's
# .claude/rules/ directory, and INJECTS a directive into the agent session via
# additionalContext. Same Layer-2 precondition-hook design as
# tools/bcquality/precondition_hook.sh: detection is deterministic here, the
# agent just enacts the injected directive instead of re-deriving the
# "is init done" question per file (and per agent).
#
# Wired from hooks/hooks.json on SessionStart. Emits the Copilot hook output
# contract on stdout, same shape as tools/bcquality/precondition_hook.sh.
set -euo pipefail

EVENT="${1:-SessionStart}"
MARKER=".claude/rules/al-guidelines.md"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-.}"

emit() {
  # $1 must be free of " and \ so this stays valid JSON.
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$1"
}

if [ -f "$MARKER" ]; then
  emit "ALDC rules are INSTALLED at .claude/rules/ (this project has run /aldc:al-initialize). For every code-touching subagent call (implement, review) this session, paste the condensed rules-floor-cheatsheet.md and tool-failure-protocol.md inline into the Task instruction -- read each once per session, not the full 7 domain files (al-guidelines/al-code-style/al-naming-conventions/al-performance/al-error-handling/al-events/al-testing); those stay available on demand for a subagent that needs the rationale/example behind a specific rule. Do not re-run init and do not re-read the same file twice this session."
else
  emit "ALDC rules are NOT installed (no ${MARKER}). Before writing, editing, or reviewing any AL code this session, tell the user that /aldc:al-initialize has not been run for this project and offer to run it now - it copies the 7 always-on rule templates plus rules-floor-cheatsheet.md and tool-failure-protocol.md from ${PLUGIN_ROOT}/rules-templates/ into .claude/rules/ so they persist and stay editable per project. Until the user responds, still apply the baselines yourself by reading rules-floor-cheatsheet.md and tool-failure-protocol.md directly from ${PLUGIN_ROOT}/rules-templates/ (fall back to the full al-*.md domain files, excluding the conditional al-agent-toolkit, only if the cheat sheet is missing) so no AL code is generated ungoverned. NEVER block or fail the task for the missing install - this is a human-in-the-loop nudge, not a hard gate."
fi
