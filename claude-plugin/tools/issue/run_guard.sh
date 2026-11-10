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
# A launch of al-conductor (bare or bc-dev:al-conductor) passes when EITHER
#   - the brief says so:        `BC Issue: 4821`  or  `BC Issue: none`   (markdown bold allowed), or
#   - the spec of the checked-out branch says so: a header line `**BC Issue:** 4821|none` in an
#     in-progress spec whose `**Branch:**` is this branch.
# Otherwise it is denied once with what to do: ask the user (AskUserQuestion), record the answer,
# launch again. "No Issue" is a valid answer, so nothing is ever blocked for good.
#
# Every other subagent, and anything outside an AL workspace, passes untouched.
# Contract: decision JSON on stdout, exit 0; allowed -> prints nothing. Pure bash.
# Kill switch: ALDC_ISSUE_RUN_GUARD_DISABLE=1. Self-test: tools/hooks/test_dispatchers.sh.

set -uo pipefail
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

# 1. The brief names the Issue (or says there is none).
if printf '%s' "$INPUT" | grep -qiE 'BC Issue:?(\*\*)?:?[[:space:]]*`?([1-9][0-9]{0,9}|none)([^0-9A-Za-z]|$)'; then
  exit 0
fi

# 2. The spec of the checked-out branch names it.
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
  "ALDC Issue: a conductor run starts only after the user has said which Business Central Issue it belongs to, and nobody has asked yet. Now work out the likely Issue first with bc-dev:skill-bc-issue -- the repository's customer property plus the open Issues assigned to this developer (tools/issue/whoami.sh gives the company e-mail of the gh account, List_Employees maps it to the employee) -- then PROPOSE it with AskUserQuestion: 'Is this the Business Central Issue for this work?' with your best match first, up to two other candidates, 'No Issue for this work', and the free-text answer for another number. Never link without the user's yes; an Issue with no estimate is normal. If the businesscentral connection is not signed in, ask for the number directly with the same 'No Issue' option. Then record the answer where the scripts read it: the spec header line '**BC Issue:** <number> (<reference>)' or '**BC Issue:** none' (when the requirement has a spec), and 'BC Issue: <number|none>' in the brief you pass to al-conductor. Launch al-conductor again after that. Do not guess a number and do not write 'none' without asking."
