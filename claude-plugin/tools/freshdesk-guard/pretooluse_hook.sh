#!/usr/bin/env bash
#
# PreToolUse guard for the Freshdesk MCP server (server name `freshdesk` in .mcp.json, so its
# tools arrive as mcp__plugin_bc-dev_freshdesk__<toolName>). Routed here by
# tools/hooks/pretooluse.sh; never a hooks.json entry of its own.
#
# Why it exists: DSC is on Freshdesk's Growth plan, which allows 1,200 successful MCP tool
# calls PER YEAR for the whole company. A prompt-level "be frugal" does not survive a long
# session, so the budget is enforced here, structurally:
#
#   1. Allowlist. Only fetchTicket, fetchTicketConversations, fetchSolutionArticle and
#      createTicketNote may run. Everything else is denied: replyTicket (emails the customer),
#      every list/search/autocomplete tool (one call can burn budget for nothing), bulk
#      updates, and every create/update other than createTicketNote (customer-facing state).
#   2. createTicketNote -> "ask" (a human confirms every note, also in auto/bypass modes when
#      the harness honors it), and "deny" when tool_input sets private to false: notes from
#      an agent are always private, never visible to the customer.
#   3. Per-session budget: at most ALDC_FRESHDESK_SESSION_LIMIT (default 4) calls per
#      session_id. Only calls that pass the allowlist count; the call over the limit is denied
#      and does not count. Counter files live in ALDC_FRESHDESK_DIR (default
#      ~/.claude/aldc-plugin-data/freshdesk/, next to the live/ snapshots) and are swept after
#      ~7 days. A call that is approved here but then fails at Freshdesk still counted: the
#      guard cannot see the outcome, and over-counting is the safe side of a yearly quota.
#   4. Metrics: one AldcHook event per call (hook=freshdesk-guard, decision, tool, calls),
#      sent by tools/metrics/emit.py fully detached. Never a ticket id, text or tool_input:
#      `tool` is the allowlisted name or "other".
#
# Contract: decision JSON on stdout, exit 0. An allowed read prints nothing (the normal
# permission flow applies). Pure bash, no jq/python on the decision path.
# Kill switch: ALDC_FRESHDESK_GUARD_DISABLE=1. Metrics off: ALDC_FRESHDESK_GUARD_NO_METRICS=1.
# Self-test: tools/hooks/test_dispatchers.sh.

set -uo pipefail
[ "${ALDC_FRESHDESK_GUARD_DISABLE:-}" = "1" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"

field() {
  printf '%s' "$INPUT" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true
}

full="$(field tool_name)"
case "$full" in
  mcp__plugin_bc-dev_freshdesk__*) ;;
  *) exit 0 ;;
esac
name="${full#mcp__plugin_bc-dev_freshdesk__}"
name="$(printf '%s' "$name" | tr -cd 'A-Za-z0-9_')"

sid="$(field session_id | tr -cd 'A-Za-z0-9_-')"
[ -n "$sid" ] || sid="no-session"

limit="${ALDC_FRESHDESK_SESSION_LIMIT:-4}"
case "$limit" in ''|*[!0-9]*) limit=4 ;; esac
dir="${ALDC_FRESHDESK_DIR:-${HOME:-${USERPROFILE:-.}}/.claude/aldc-plugin-data/freshdesk}"
counter="$dir/session-$sid"

ALLOWED="fetchTicket, fetchTicketConversations, fetchSolutionArticle, createTicketNote (private, human-confirmed)"

metric() { # $1 decision, $2 calls
  [ "${ALDC_FRESHDESK_GUARD_NO_METRICS:-}" = "1" ] && return 0
  [ -f "$here/../metrics/emit.py" ] || return 0
  local tool_tok=other c
  case "$name" in
    fetchTicket|fetchTicketConversations|fetchSolutionArticle|createTicketNote|replyTicket) tool_tok="$name" ;;
  esac
  for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1; then
      ( nohup "$c" "$here/../metrics/emit.py" AldcHook hook=freshdesk-guard "decision=$1" \
          "tool=$tool_tok" "calls=$2" --session "$sid" >/dev/null 2>&1 & ) >/dev/null 2>&1
      break
    fi
  done
  return 0
}

decide() { # $1 decision (deny|ask|allow), $2 reason
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
}

read_count() {
  local n=0
  [ -f "$counter" ] && n="$(cat "$counter" 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# --- 1. allowlist ---------------------------------------------------------------------------
case "$name" in
  fetchTicket|fetchTicketConversations|fetchSolutionArticle|createTicketNote) ;;
  *)
    why="it is not on the allowlist"
    case "$name" in
      replyTicket) why="it emails the customer, which an agent never does" ;;
      *[Ll]ist*|*[Ss]earch*|*[Aa]utocomplete*|*[Ff]ilter*) why="list/search tools burn the budget without a known target" ;;
      *[Bb]ulk*) why="bulk updates change many tickets at once" ;;
      *[Cc]reate*|*[Uu]pdate*|*[Dd]elete*|*[Mm]erge*|*[Ff]orward*) why="it changes customer-facing data" ;;
    esac
    metric deny "$(read_count)"
    decide deny "freshdesk-guard: $name is blocked because $why. DSC has 1,200 Freshdesk tool calls per year for the whole company, and anything the customer can see stays a human action. Allowed: $ALLOWED. Ask the user for the ticket number instead of searching, and draft any customer reply in chat for a human to send. Do not retry."
    exit 0
    ;;
esac

# --- 2. createTicketNote must be private ----------------------------------------------------
note_extra=""
if [ "$name" = createTicketNote ]; then
  if printf '%s' "$INPUT" | grep -qE '"private"[[:space:]]*:[[:space:]]*("false"|false)'; then
    metric deny "$(read_count)"
    decide deny "freshdesk-guard: createTicketNote with private set to false is blocked - a public note is visible to the customer. Retry with private true. Notes from an agent are always private."
    exit 0
  fi
  printf '%s' "$INPUT" | grep -qE '"private"[[:space:]]*:[[:space:]]*("true"|true)' \
    || note_extra=" The note must be private: set private to true."
fi

# --- 3. per-session budget (mkdir lock: parallel calls of one session must not both pass) ---
mkdir -p "$dir" 2>/dev/null || true
lock="$dir/.lock-$sid"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  mkdir "$lock" 2>/dev/null && break
  sleep 0.1
done
n="$(read_count)"
if [ "$n" -ge "$limit" ]; then
  rmdir "$lock" 2>/dev/null || true
  metric deny "$n"
  decide deny "freshdesk-guard: Freshdesk budget for this session is used up ($n of $limit calls; the company has 1,200 per year). Work with what you already fetched, or tell the user what else you would need so they can decide. Per-session limit: ALDC_FRESHDESK_SESSION_LIMIT."
  exit 0
fi
n=$((n + 1))
printf '%s' "$n" > "$counter" 2>/dev/null || true
rmdir "$lock" 2>/dev/null || true

# Opportunistic sweep on a session's first call: counters and stale locks older than ~7 days.
if [ "$n" -eq 1 ]; then
  ( find "$dir" -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} + >/dev/null 2>&1 & ) >/dev/null 2>&1
fi

if [ "$name" = createTicketNote ]; then
  metric ask "$n"
  decide ask "freshdesk-guard: writes a PRIVATE internal note on a customer ticket (Freshdesk call $n of $limit for this session). Confirm the content before it is posted.$note_extra"
  exit 0
fi
metric allow "$n"
exit 0
