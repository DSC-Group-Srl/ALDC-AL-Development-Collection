#!/usr/bin/env bash
#
# Structural backstop for al-conductor's "orchestrator only" rule (see the
# top-of-file banner in claude-plugin/agents/al-conductor.md): a prompt-level
# instruction can drift under long context, so this PreToolUse hook denies
# Write/Edit on any *.al file when the active agent is al-conductor, forcing
# the conductor to delegate AL edits to al-implement-subagent instead of
# writing/editing code itself. Every other agent (al-developer,
# al-implement-subagent, ...) is unaffected — writing AL is their actual job.
#
# Wired from hooks/hooks.json on PreToolUse (matcher: Write|Edit). Reads the
# hook input JSON from stdin — fields used: .agent_type, .tool_name,
# .tool_input.file_path. No jq dependency (none of this plugin's other hooks
# require one) — field extraction is a tested grep/sed pattern; safe here
# because none of these three values ever contain a literal `"`.
#
# Deny is expressed via the hookSpecificOutput/permissionDecision contract —
# the same JSON-on-stdout convention already used by this harness's
# SessionStart hooks (tools/rules/precondition_hook.sh, tools/bcquality/precondition_hook.sh).
set -euo pipefail

INPUT="$(cat)"

extract_str_field() {
  # $1 = JSON text, $2 = top-level-or-nested key name (matched anywhere in the text).
  # `|| true` is required: under `set -e -o pipefail`, a field that's simply
  # absent (e.g. agent_type when the hook fires in the main session, not a
  # subagent) makes grep exit 1 with no match — without the fallback, that
  # would abort the whole script instead of yielding an empty ("allow") value.
  printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true
}

AGENT_TYPE="$(extract_str_field "$INPUT" "agent_type")"
TOOL_NAME="$(extract_str_field "$INPUT" "tool_name")"
FILE_PATH="$(extract_str_field "$INPUT" "file_path")"

if [ "$AGENT_TYPE" != "al-conductor" ]; then
  exit 0
fi

case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

# Match *.al case-insensitively, anywhere in the path — not just src/**.
LOWER_PATH="$(printf '%s' "$FILE_PATH" | tr '[:upper:]' '[:lower:]')"
case "$LOWER_PATH" in
  *.al) ;;
  *) exit 0 ;;
esac

# Escape backslashes/quotes ourselves before re-embedding FILE_PATH in our own
# JSON output — don't assume the extracted text is (or isn't) already
# JSON-escaped; escaping it here guarantees valid output JSON either way.
JSON_SAFE_PATH="$(printf '%s' "$FILE_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')"

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"al-conductor is an orchestrator and must not write or edit AL source itself (path: %s). Delegate this change to al-implement-subagent via the Task tool instead."}}\n' "$JSON_SAFE_PATH"
