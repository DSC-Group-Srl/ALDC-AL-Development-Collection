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
# Wired from hooks/hooks.json on SessionStart. Emits the hookSpecificOutput
# additionalContext contract on stdout, same shape as tools/bcquality/precondition_hook.sh.
set -euo pipefail

EVENT="${1:-SessionStart}"
MARKER=".claude/rules/rules-floor-cheatsheet.md"
OLD_LAYOUT=".claude/rules/al-guidelines.md"   # pre-8.0: domain files auto-loaded from .claude/rules/
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

# Only inject into AL workspaces (same app.json guard as tools/routing/precondition_hook.sh):
# the install/refresh work below still runs, it just stays silent in Blazor/NAV/other
# sessions, which would otherwise pay for AL-only context they cannot use.
if [ ! -f "app.json" ] && ! find . -maxdepth 2 -iname "app.json" -print -quit 2>/dev/null | grep -q .; then
  emit() { :; }
fi

if [ -f "$OLD_LAYOUT" ]; then
  emit "ALDC rules are installed in the pre-8.0 layout: the full domain files (~90 KB) sit in .claude/rules/ and auto-load into every session and subagent. Tell the user once and offer to re-run /bc-dev:al-initialize, which moves them to .claude/aldc-rules/ (on-demand) and keeps only the floor (cheat sheet, compiler-authority, tool-failure, agent-contract) auto-loaded. Proceed normally meanwhile."
elif [ -f "$MARKER" ]; then
  emit "ALDC rules are INSTALLED: .claude/rules/ (cheat sheet, compiler-authority, tool-failure, agent-contract) auto-loads in this session and in every subagent once an AL file or app.json is read -- do not paste those files into Task prompts. Full domain rules (al-*.md) are on-demand in .claude/aldc-rules/."
else
  emit "ALDC rules are NOT installed (no ${MARKER}). Before writing, editing or reviewing AL, tell the user /bc-dev:al-initialize has not run here and offer to run it. Until then read rules-floor-cheatsheet.md, compiler-authority-protocol.md, tool-failure-protocol.md and agent-contract.md from ${PLUGIN_ROOT}/rules-templates/ yourself and paste them into every code-touching Task (al-conductor does this). NEVER block the task for the missing install."
fi
