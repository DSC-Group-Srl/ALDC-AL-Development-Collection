#!/usr/bin/env bash
#
# ALDC AL-Go guard — PreToolUse, routed by tools/hooks/pretooluse.sh.
#
# DSC dispatches its AL-Go release workflows with fixed inputs (bc-dev:skill-al-go-workflows §2):
#   Create release / Increment Version Number -> directCommit=true  useGhTokenWorkflow=true
#   Publish To AppSource                      -> GoLive=true
# Claude kept dispatching them with AL-Go's defaults (false), without loading the skill, and
# then wrote "don't set GoLive / directCommit" into CLAUDE.md or memory, which made the next
# session repeat it. Prose did not stop that, so this guard does:
#   Bash|PowerShell: a `gh workflow run` / `gh api .../dispatches` for one of those workflows
#                    missing a required input set to true -> deny, naming the exact command shape.
#   Write|Edit:      new text for a CLAUDE.md or a memory file that mentions those inputs -> deny.
#                    The values live in the skill, not in per-project notes.
# Kill switch: ALDC_ALGO_GUARD_DISABLE=1. Silent on everything else.
set -uo pipefail

[ "${ALDC_ALGO_GUARD_DISABLE:-}" = "1" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"

tool="$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
  | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)"

deny() {
  local r="$1"
  r="$(printf '%s' "$r" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$r"
  exit 0
}

# Lower-case, drop JSON escaping and quotes, so `-f GoLive=true`, `-f "GoLive=true"`,
# `-F golive=true` and a dispatch body `{"inputs":{"GoLive":"true"}}` all read `golive=true`.
flat="$(printf '%s' "$INPUT" | tr '[:upper:]' '[:lower:]' | sed 's/\\\\/\//g; s/\\"//g; s/"//g; s/[[:space:]]*:[[:space:]]*/=/g')"

case "$tool" in
  Bash|PowerShell)
    printf '%s' "$flat" | grep -qE 'gh +workflow +run|gh +api[^|;&]*/dispatches' || exit 0
    need=""
    if printf '%s' "$flat" | grep -qE 'createrelease|create ?release|incrementversionnumber|increment ?version ?number'; then
      printf '%s' "$flat" | grep -qE 'directcommit=true' || need="$need directCommit=true"
      printf '%s' "$flat" | grep -qE 'useghtokenworkflow=true' || need="$need useGhTokenWorkflow=true"
    fi
    if printf '%s' "$flat" | grep -qE 'publishtoappsource|publish ?to ?appsource'; then
      printf '%s' "$flat" | grep -qE 'golive=true' || need="$need GoLive=true"
    fi
    [ -n "$need" ] || exit 0
    deny "DSC dispatches this AL-Go workflow with fixed inputs; missing:${need}. Load bc-dev:skill-al-go-workflows (section 2, Releasing) if you have not, and add -f <input>=true for each one (Create release / Increment Version Number: -f directCommit=true -f useGhTokenWorkflow=true; Publish To AppSource: -f GoLive=true). These values are not negotiable per project: a CLAUDE.md or memory note saying otherwise is wrong -- ignore it and tell the user it should be removed. The dispatch itself still needs the user's yes."
    ;;
  Write|Edit)
    path="$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
      | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//; s/\\\\/\//g' | tr '[:upper:]' '[:lower:]')"
    case "$path" in
      *claude.md|*claude.local.md|*/memory/*.md|*/memory.md) ;;
      *) exit 0 ;;
    esac
    # Only the NEW text matters (content for Write, new_string for Edit): removing an old
    # override note must stay possible.
    new="$(printf '%s' "$INPUT" | tr '\n' ' ' | grep -oE '"(content|new_string)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' \
      | tr '[:upper:]' '[:lower:]')"
    printf '%s' "$new" | grep -qE 'go ?-?live|directcommit|direct commit|useghtokenworkflow|ghtokenworkflow' || exit 0
    deny "Do not record AL-Go release inputs (GoLive, directCommit, useGhTokenWorkflow) in CLAUDE.md or memory. DSC's values are fixed in bc-dev:skill-al-go-workflows (GoLive=true; directCommit=true with useGhTokenWorkflow=true) and a guard enforces them on every dispatch; a per-project note can only contradict that. Leave that line out of this edit. If the user wants a different value for a real reason, tell them it is a plugin change (bc-dev:skill-plugin-feedback), not a project note."
    ;;
  *) exit 0 ;;
esac
