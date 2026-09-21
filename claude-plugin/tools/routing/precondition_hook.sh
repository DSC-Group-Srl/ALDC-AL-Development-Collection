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

emit "ALDC agent routing -- before touching any AL work (design, code, debug, estimate, audit, or document), launch the matching specialist agent via Task instead of doing it in the main thread; the user will often not name an agent explicitly, so infer intent from the request. Routing table: design/architecture/data-model/integration-strategy -> agent al-architect. Implement/code/debug/fix existing code you already understand -> agent al-developer. Full TDD cycle (plan -> implement -> review -> commit) -> agent al-conductor (never call al-planning-subagent/al-implement-subagent/al-review-subagent directly -- those are al-conductor-internal). Estimate/size/propose a project -> agent al-presales. A bug/regression/incident starting from a SYMPTOM ('this throws', 'this is slow', 'broke after last change') -> agent al-triage first (read-only diagnosis), then hand its fix to al-developer. An independent on-demand quality audit (not part of a TDD loop) -> agent dredd (read-only, advisory verdict). Build a Business Central agent / Agent SDK integration -> agent al-agent-builder. Full end-to-end documentation pass on demand -> agent al-documentation-conductor. New-feature complexity routing: LOW (single phase, no integrations) -> /bc-dev:al-spec-create then al-developer; MEDIUM (2-3 areas, internal integrations) or HIGH (4+ phases, external integrations) -> al-architect first, then /bc-dev:al-spec-create, then al-conductor -- present the complexity assessment and wait for user confirmation before proceeding. For HIGH complexity specifically, also ask the user whether they want to switch this session to Opus before work begins -- do not switch it yourself, just surface the question alongside the complexity assessment. Never skip straight to writing/editing .al files yourself when a specialist agent exists for the intent. Even when the user names al-conductor explicitly, check first whether the request is actually LOW per this table (independent fixes, root cause already known, no open architectural decision) -- al-conductor itself gates on this before Phase 1 and will offer al-developer as the direct-implementation alternative. And once al-conductor is running as a background Task, its own Phase Status Cards land in its transcript, not in front of the user -- check in on it periodically and relay progress yourself rather than going silent until the final completion notification, especially if you told it to skip per-phase checkpoints."
