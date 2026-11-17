#!/usr/bin/env bash
#
# PreToolUse guard on Task/Agent: a conductor run does not start until someone has said which
# Business Central Issue it belongs to. Routed here by tools/hooks/pretooluse.sh.
#
# Why: a run is the unit DSC's estimation model learns from (planned size, measured minutes,
# tokens), and it is only usable when it carries the Issue it was planned and billed on. Up to
# bc-dev 8.19 none of 72 recorded runs did. The session-start hook links a session when the spec
# already names the Issue; this guard covers the other case — the run is about to start and
# nobody was asked.
#
# A launch of al-conductor (bare or bc-dev:al-conductor) passes when
#   - the spec of the checked-out branch says so: a header line `**BC Issue:** 4821|none` in an
#     in-progress spec whose `**Branch:**` is this branch, or
#   - the session already holds the answer (tools/metrics/emit.py AldcIssue issueNo=<n|none>,
#     run by skill-bc-issue after the user's answer), or
#   - the brief names a NUMBER (`BC Issue: 4821`): the guard links the session to it itself
#     (AldcIssue source=brief), because up to 9.4 a number written only in the brief was never
#     recorded and the run's telemetry carried no Issue.
# A brief that only says `BC Issue: none` no longer passes on its own: on 9.x most runs started
# that way with no Issue and no trace of anyone being asked. "No Issue" stays a valid answer -
# it just has to be recorded (AldcIssue issueNo=none source=user), which also tells the
# estimation queries "asked, none" apart from "never asked" (issueState on AldcRunStart).
# Otherwise it is denied once with what to do. Nothing is ever blocked for good.
# Without python (the metrics scripts are python) the old brief rule applies: number or none.
#
# Every other subagent, and anything outside an AL workspace, passes untouched.
# Contract: decision JSON on stdout, exit 0; allowed -> prints nothing. Pure bash.
# Kill switch: ALDC_ISSUE_RUN_GUARD_DISABLE=1. Self-test: tools/hooks/test_dispatchers.sh.

set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../python/find-python.sh" 2>/dev/null || aldc_python() { echo python3 python py; }
[ "${ALDC_ISSUE_RUN_GUARD_DISABLE:-}" = "1" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"

sub="$(printf '%s' "$INPUT" | grep -oE '"subagent_type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
  | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)"
case "$sub" in
  al-conductor|bc-dev:al-conductor) ;;
  *) exit 0 ;;
esac

# AL workspace only (app.json at the root or one level down).
if [ ! -f "app.json" ] && ! find . -maxdepth 2 -iname "app.json" -print -quit 2>/dev/null | grep -q .; then
  exit 0
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
PY=""
# Only an interpreter that runs: on Windows `python3` is often the Microsoft Store stub, which
# exists on PATH and fails every call - the link would then be lost without a word.
for c in $(aldc_python); do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
sid="$(printf '%s' "$INPUT" | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
  | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' | tr -cd 'A-Za-z0-9_-')"
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
brief_no="$(printf '%s' "$INPUT" | grep -oiE 'BC Issue:?(\*\*)?:?[[:space:]]*`?[1-9][0-9]{0,9}([^0-9A-Za-z]|$)' | head -1 \
  | grep -oE '[1-9][0-9]{0,9}' | head -1)"
brief_none=""
printf '%s' "$INPUT" | grep -qiE 'BC Issue:?(\*\*)?:?[[:space:]]*`?none([^0-9A-Za-z]|$)' && brief_none=1

# 1. No python or no session id: the metrics side cannot record anything, keep the brief rule.
if [ -z "$PY" ] || [ -z "$sid" ]; then
  { [ -n "$brief_no" ] || [ -n "$brief_none" ]; } && exit 0
fi

# 2. The session already holds the user's answer (a number or none).
if [ -n "$sid" ]; then
  live="${ALDC_LIVE_DIR:-$HOME/.claude/aldc-plugin-data/live}"
  ans="$(head -c 32 "$live/$sid.issue" 2>/dev/null | tr -d '\r\n ' | tr '[:upper:]' '[:lower:]')"
  case "$ans" in
    none) exit 0 ;;
    ""|*[!0-9]*) ;;
    *) exit 0 ;;
  esac
fi

# 3. The brief names a number: record it for the session, then let the run start.
if [ -n "$brief_no" ]; then
  [ -n "$PY" ] && [ -n "$sid" ] && "$PY" "$here/../metrics/emit.py" AldcIssue "issueNo=$brief_no" \
    source=brief --session "$sid" >/dev/null 2>&1
  exit 0
fi

# 4. The spec of the checked-out branch names it.
branch="$(git branch --show-current 2>/dev/null || true)"
if [ -n "$branch" ]; then
  while IFS= read -r spec; do
    [ -f "$spec" ] || continue
    head="$(head -c 8000 "$spec" 2>/dev/null | tr -d '\r')"
    printf '%s\n' "$head" | grep -qF "**Branch:** \`$branch\`" || continue
    if printf '%s\n' "$head" | grep -qiE '^\*\*BC Issue:\*\*[[:space:]]*([1-9][0-9]{0,9}|none)([^0-9A-Za-z]|$)'; then
      exit 0
    fi
  done < <(find . -maxdepth 5 -path '*/requirements/in-progress/*' -name '*.spec.md' 2>/dev/null)
fi

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
  "ALDC Issue: a conductor run starts only after the user has said which Business Central Issue it belongs to, and nobody has asked yet. Now work out the likely Issue first with bc-dev:skill-bc-issue -- the repository's customer property plus the open Issues assigned to this developer (tools/issue/whoami.sh gives the company e-mail of the gh account, List_Employees maps it to the employee) -- then PROPOSE it with AskUserQuestion: 'Is this the Business Central Issue for this work?' with your best match first, up to two other candidates, 'No Issue for this work', and the free-text answer for another number. Never link without the user's yes; an Issue with no estimate is normal. If the businesscentral connection is not signed in, ask for the number directly with the same 'No Issue' option. Then record the answer where the scripts read it: the spec header line '**BC Issue:** <number> (<reference>)' or '**BC Issue:** none' (when the requirement has a spec), and 'BC Issue: <number|none>' in the brief you pass to al-conductor. When the answer is 'No Issue', also record it: python <bc-dev plugin>/tools/metrics/emit.py AldcIssue issueNo=none source=user (a brief that only says 'BC Issue: none' is not enough). Launch al-conductor again after that. Do not guess a number and do not write 'none' without asking."
