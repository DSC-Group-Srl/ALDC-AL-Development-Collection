#!/usr/bin/env bash
#
# ALDC rules-injection precondition hook — detects whether /bc-dev:al-initialize
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
  # JSON-escape the message: backslashes, double quotes, CR/LF/TAB.
  # Windows paths interpolated into the text (CLAUDE_PLUGIN_ROOT, analyzer
  # folders) are why this cannot be a bare printf -- a C:\Users\... path
  # emits an invalid \U escape and the harness rejects the whole payload.
  # The backslash and quote literals are built with printf octal escapes so
  # this function contains no raw backslash that an editor or generator can
  # silently halve -- that halving is exactly how the original bug survived.
  local esc bs dq
  bs=$(printf '\134')   # backslash
  dq=$(printf '\042')   # double quote
  esc="$1"
  # NOTE: BOTH pattern and replacement MUST be quoted -- an unquoted $bs is
  # read as the pattern escape character (matches nothing), and an unquoted
  # replacement collapses $bs$bs back to a single backslash.
  esc="${esc//"$bs"/"$bs$bs"}"
  esc="${esc//"$dq"/"$bs$dq"}"
  esc="${esc//$'\r'/}"
  esc="${esc//$'\n'/${bs}n}"
  esc="${esc//$'\t'/${bs}t}"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$esc"
}

if [ -f "$MARKER" ]; then
  emit "ALDC rules are INSTALLED at .claude/rules/ (this project has run /bc-dev:al-initialize). For every code-touching subagent call (implement, review) this session, paste the condensed rules-floor-cheatsheet.md and tool-failure-protocol.md inline into the Task instruction -- read each once per session, not the full 7 domain files (al-guidelines/al-code-style/al-naming-conventions/al-performance/al-error-handling/al-events/al-testing); those stay available on demand for a subagent that needs the rationale/example behind a specific rule. Do not re-run init and do not re-read the same file twice this session."
else
  emit "ALDC rules are NOT installed (no ${MARKER}). Before writing, editing, or reviewing any AL code this session, tell the user that /bc-dev:al-initialize has not been run for this project and offer to run it now - it copies the 7 always-on rule templates plus rules-floor-cheatsheet.md and tool-failure-protocol.md from ${PLUGIN_ROOT}/rules-templates/ into .claude/rules/ so they persist and stay editable per project. Until the user responds, still apply the baselines yourself by reading rules-floor-cheatsheet.md and tool-failure-protocol.md directly from ${PLUGIN_ROOT}/rules-templates/ (fall back to the full al-*.md domain files, excluding the conditional al-agent-toolkit, only if the cheat sheet is missing) so no AL code is generated ungoverned. NEVER block or fail the task for the missing install - this is a human-in-the-loop nudge, not a hard gate."
fi
