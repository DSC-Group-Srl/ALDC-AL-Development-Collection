#!/usr/bin/env bash
#
# PreToolUse guard for the DSC Business Central MCP server (server name `businesscentral` in
# .mcp.json, so its tools arrive as mcp__plugin_bc-dev_businesscentral__<toolName>). Routed
# here by tools/hooks/pretooluse.sh; never a hooks.json entry of its own.
#
# Why it exists: the connection points at DSC's own PRODUCTION Business Central (company
# DSC GROUP SRL, configuration OPERATIONS) with the developer's own permissions, and that
# configuration also exposes write actions (Create_/Modify_ on Issues and Tasks, the timesheet
# insert API). bc-dev uses it to LOOK THINGS UP - which Issue a piece of work belongs to, what
# similar work was estimated at and what it took - never to change the company's books. A
# prompt-level "read only" does not survive a long session, so it is enforced here:
#
#   bc_actions_search / bc_actions_describe / list_companies / list_environments -> allowed
#   bc_actions_invoke with an ActionName starting with List_                      -> allowed
#   bc_actions_invoke with any other ActionName (Create_, Modify_, Delete_, bound and unbound
#   actions) or without a readable ActionName                                    -> denied
#   any other tool of the server                                                 -> denied
#
# Writing timesheet lines is dsc-timesheet's job, on its own connection; creating Issues and
# Tasks is a human step in Business Central.
#
# Contract: decision JSON on stdout, exit 0; an allowed call prints nothing. Pure bash.
# Kill switch: ALDC_BC_GUARD_DISABLE=1. Self-test: tools/hooks/test_dispatchers.sh.

set -uo pipefail
[ "${ALDC_BC_GUARD_DISABLE:-}" = "1" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"

field() {
  printf '%s' "$INPUT" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true
}

full="$(field tool_name)"
case "$full" in
  mcp__plugin_bc-dev_businesscentral__*) ;;
  *) exit 0 ;;
esac
name="${full#mcp__plugin_bc-dev_businesscentral__}"

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
}

case "$name" in
  bc_actions_search|bc_actions_describe|list_companies|list_environments|authenticate|complete_authentication)
    exit 0 ;;
  bc_actions_invoke)
    action="$(field ActionName | tr -cd 'A-Za-z0-9_')"
    case "$action" in
      List_*) exit 0 ;;
    esac
    deny "bc-guard: bc-dev reads DSC's Business Central, it never writes to it. The action '${action:-unknown}' is not a List_ action, so it is blocked. This connection is DSC's production company: Issues, Tasks and timesheet lines are created by a person in Business Central, or by the dsc-timesheet plugin for timesheet lines. Tell the user what you would have written and let them do it. Do not retry."
    exit 0 ;;
  *)
    deny "bc-guard: the tool '$(printf '%s' "$name" | tr -cd 'A-Za-z0-9_')' is not one bc-dev uses on DSC's Business Central. Allowed: bc_actions_search, bc_actions_describe, and bc_actions_invoke with a List_ action. Do not retry."
    exit 0 ;;
esac
