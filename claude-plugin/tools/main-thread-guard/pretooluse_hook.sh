#!/usr/bin/env bash
#
# Structural backstop for the ALDC routing rule: AL source is written by an
# agent (al-developer, al-conductor's implement subagent, ...), never by the
# main thread on its own initiative. The SessionStart routing nudge
# (tools/routing/precondition_hook.sh) is advisory and was ignored in practice
# (issue #62), so this PreToolUse hook denies Write/Edit on any *.al file when
# the call comes from the main thread -- i.e. neither .agent_type nor
# .agent_id is present in the hook input (both are set only for subagents).
#
# The deny reason tells the model exactly what to do instead. If the user has
# explicitly asked for the main thread to write AL itself, set
# ALDC_MAIN_THREAD_GUARD_DISABLE=1 (per machine / per session).
#
# Fast path (8.6): a *truly* trivial main-thread edit is let through so a typo
# fix does not need a subagent round trip. ALL of these must hold, otherwise
# the normal deny applies (fail closed -- any parse doubt means deny):
#   - tool is Edit (never Write), not replace_all, and a session_id is present
#   - the changed text is ONE line on each side (old_string and new_string),
#     trimmed, and each side is exactly one of:
#       * a "//" comment line
#       * a text property line: Caption/ToolTip/Description/AboutTitle/AboutText/
#         InstructionalText/AdditionalSearchTerms = '...';
#       * a Label declaration: Name: Label '...' [, Comment = '...'] [, Locked = x];
#     i.e. human-readable text only, never logic, structure, or identifiers
#   - at most ALDC_FAST_PATH_MAX (default 3) such edits per session
# Kill switch: ALDC_FAST_PATH_DISABLE=1.
#
# Same input/output contract and no-jq field extraction as
# tools/conductor-guard/pretooluse_hook.sh.
set -euo pipefail

if [ "${ALDC_MAIN_THREAD_GUARD_DISABLE:-}" = "1" ]; then
  exit 0
fi

INPUT="$(cat)"

extract_str_field() {
  printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true
}

AGENT_TYPE="$(extract_str_field "$INPUT" "agent_type")"
AGENT_ID="$(extract_str_field "$INPUT" "agent_id")"
TOOL_NAME="$(extract_str_field "$INPUT" "tool_name")"
FILE_PATH="$(extract_str_field "$INPUT" "file_path")"

# Subagent (any kind) -> not our concern; writing AL is their job.
if [ -n "$AGENT_TYPE" ] || [ -n "$AGENT_ID" ]; then
  exit 0
fi

case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

LOWER_PATH="$(printf '%s' "$FILE_PATH" | tr '[:upper:]' '[:lower:]')"
case "$LOWER_PATH" in
  *.al) ;;
  *) exit 0 ;;
esac

# ---- fast path -------------------------------------------------------------
# Value of a JSON string field, escapes kept raw (so \" and \n stay visible).
extract_raw_field() {
  printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" | head -1 \
    | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true
}

trim_line() {
  printf '%s' "$1" | sed -E 's/^(\\t|[[:space:]])+//; s/(\\t|[[:space:]])+$//'
}

TEXT_PROP="^(Caption|ToolTip|Description|AboutTitle|AboutText|InstructionalText|AdditionalSearchTerms) *= *'([^']|'')*';$"
LABEL_DECL="^[A-Za-z_][A-Za-z0-9_]*: *Label +'([^']|'')*'(, *Comment *= *'([^']|'')*')?(, *Locked *= *(true|false))?;$"
COMMENT_LINE="^//"

is_trivial_line() {
  [ -n "$1" ] || return 1
  [ "${#1}" -le 200 ] || return 1
  # any JSON escape (\n, \r, \", \\, \uXXXX ...) -> not a plain single line
  case "$1" in *\\*) return 1 ;; esac
  printf '%s' "$1" | grep -qE "$TEXT_PROP|$LABEL_DECL|$COMMENT_LINE"
}

fast_path_ok() {
  [ "${ALDC_FAST_PATH_DISABLE:-}" = "1" ] && return 1
  [ "$TOOL_NAME" = "Edit" ] || return 1
  printf '%s' "$INPUT" | grep -qE '"replace_all"[[:space:]]*:[[:space:]]*true' && return 1
  local sid old new
  sid="$(extract_str_field "$INPUT" "session_id")"
  [ -n "$sid" ] || return 1
  sid="$(printf '%s' "$sid" | tr -c 'A-Za-z0-9_-' '_')"
  [ -n "$sid" ] || return 1
  old="$(trim_line "$(extract_raw_field "$INPUT" "old_string")")"
  new="$(trim_line "$(extract_raw_field "$INPUT" "new_string")")"
  is_trivial_line "$old" || return 1
  is_trivial_line "$new" || return 1
  [ "$old" != "$new" ] || return 1
  local dir="${TMPDIR:-/tmp}/aldc-main-thread-guard" max="${ALDC_FAST_PATH_MAX:-3}" n=0
  case "$max" in ''|*[!0-9]*) max=3 ;; esac
  mkdir -p "$dir" 2>/dev/null || return 1
  [ -f "$dir/$sid" ] && n="$(cat "$dir/$sid" 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -lt "$max" ] || return 1
  printf '%s' "$((n + 1))" > "$dir/$sid" 2>/dev/null || return 1
  return 0
}

if fast_path_ok; then
  exit 0
fi

JSON_SAFE_PATH="$(printf '%s' "$FILE_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')"

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"ALDC routing: the main thread must not write or edit AL source itself (path: %s). Do not retry this Write/Edit. Instead: (1) tell the user which agent you are delegating to; (2) LOW complexity -> launch bc-dev:al-developer via the Task tool; MEDIUM/HIGH -> /bc-dev:al-spec-create then bc-dev:al-conductor; (3) the requirement doc goes in app/requirements/in-progress/{req}/{req}.spec.md (bc-dev spec template), never an external artifact; (4) the delegated agent must return the BCQuality evidence line and a Knowledge Deviations section, and you must include them in your reply. (5) fast path: only a single-line Edit of a comment, a Caption/ToolTip/Description-style text property, or a Label declaration is allowed in the main thread (max 3 per session); this edit did not qualify. If the user explicitly told you to write AL directly in the main thread, ask them to set ALDC_MAIN_THREAD_GUARD_DISABLE=1."}}\n' "$JSON_SAFE_PATH"
