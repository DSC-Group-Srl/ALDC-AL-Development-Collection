#!/usr/bin/env bash
#
# ALDC agent-routing nudge — SessionStart hook. This plugin ships specialized
# agents (al-architect, al-developer, al-conductor, al-presales, al-triage,
# dredd, al-documentation-conductor, al-agent-builder) but the main thread
# will happily start editing AL itself unless told otherwise -- there is no
# structural gate like tools/conductor-guard/pretooluse_hook.sh for the main
# session, only convention in CLAUDE.md, which competes with the immediate
# pull of "just do the task". This hook re-injects the routing table and the
# ordered agentic loop every session so the main thread reaches for Task
# before Read/Write/Edit on AL work, even when the user did not @-mention an
# agent by name.
#
# Same Layer-2 precondition-hook design and output contract as
# tools/rules/precondition_hook.sh / tools/bcquality/precondition_hook.sh --
# SessionStart, additionalContext via hookSpecificOutput, never blocking.
set -euo pipefail

EVENT="${1:-SessionStart}"

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

# Guard: only nudge in an AL/Business Central workspace. This plugin (bc-dev,
# marketed as "aldc") can be enabled alongside other-language plugins
# (blazor-dev, nav-dev, ...) on the same machine, so a SessionStart hook that
# fires unconditionally would inject AL-agent routing advice into unrelated
# Blazor/.NET or NAV C/AL sessions too. app.json may sit at the repo root or
# be nested one level down in a multi-project workspace (app/, app-test/,
# app-performance/) -- check both before giving up.
if [ ! -f "app.json" ] && ! find . -maxdepth 2 -iname "app.json" -print -quit 2>/dev/null | grep -q .; then
  exit 0
fi

emit "ALDC routing -- for AL work, launch the matching agent via Task instead of working in the main thread (infer intent; users rarely name one): design/data model/integration -> al-architect. Implement/fix code you understand -> al-developer. Planned multi-step feature -> al-conductor (its planning/implement/review subagents are internal -- never call them directly). Symptom-first bug ('throws', 'slow', 'broke') -> al-triage, then al-developer. Independent audit -> dredd. Estimate -> al-presales. BC agent / Agent SDK -> al-agent-builder. Full docs pass -> al-documentation-conductor. Complexity: LOW (one area, cause known) -> al-developer (spec optional); MEDIUM (2-3 areas) -> /bc-dev:al-spec-create -> al-conductor; HIGH (4+ areas or external integrations) -> al-architect -> /bc-dev:al-spec-create -> al-conductor. Present the assessment and wait for confirmation; for HIGH also ask whether to switch to Opus (never switch yourself). While al-conductor runs as a background Task, check on it and relay 'wave N/M' progress to the user unprompted."
