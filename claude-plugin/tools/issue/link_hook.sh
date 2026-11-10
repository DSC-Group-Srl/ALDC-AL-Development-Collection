#!/usr/bin/env bash
#
# ALDC Business Central Issue link — SessionStart hook (run by tools/hooks/sessionstart.sh).
#
# DSC plans and bills every activity as an Issue in its own Business Central, and telemetry is
# only useful to the estimation model when a session's tokens and minutes land on that Issue.
# Before this hook the link depended on the model remembering one line of a long routing
# paragraph: 0 of 42 planned runs and almost no al-developer session carried an Issue.
#
# The spec header already records it (`**BC Issue:** <entryNo>`, written once by
# /bc-dev:al-spec-create) next to the branch it is built on (`**Branch:**`). So at session start:
#   - the in-progress spec of the checked-out branch names an Issue -> the session is linked by
#     the script itself (tools/metrics/emit.py AldcIssue --from-branch) and the agent is told,
#     in one line, that there is nothing to do;
#   - the spec says `none` -> silent;
#   - there is a spec without the line, or work is on a feature branch with no spec -> one line
#     asking to resolve the Issue with skill-bc-issue before delegating;
#   - on main/test/master, outside git, or outside an AL workspace -> silent.
# Needs python (the metrics scripts are python); none on PATH -> silent. Never blocks.
#
# Kill switch: ALDC_ISSUE_LINK_DISABLE=1.
set -uo pipefail

EVENT="${1:-SessionStart}"
[ "${ALDC_ISSUE_LINK_DISABLE:-}" = "1" ] && exit 0
if [ ! -f "app.json" ] && ! find . -maxdepth 2 -iname "app.json" -print -quit 2>/dev/null | grep -q .; then
  exit 0
fi

INPUT="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$INPUT" | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
  | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' | tr -cd 'A-Za-z0-9_-')"
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
[ -n "$sid" ] || exit 0

branch="$(git branch --show-current 2>/dev/null || true)"
[ -n "$branch" ] || exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
PY=""
for c in python3 python py; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
[ -n "$PY" ] || exit 0

status="$("$PY" "$here/../metrics/emit.py" AldcIssue --from-branch --session "$sid" 2>/dev/null \
  | grep -oE '^issue=[a-z0-9]+' | head -1)"
status="${status#issue=}"

case "$status" in
  none|"") exit 0 ;;
  nospec)
    case "$branch" in main|master|test|develop) exit 0 ;; esac
    msg="ALDC Issue -- no Business Central Issue is linked to this session: branch $branch has no requirement spec yet. Before delegating any work on it, work out the likely Issue first with bc-dev:skill-bc-issue -- the repository's customer property plus the open Issues assigned to this developer (tools/issue/whoami.sh gives the company e-mail of the gh account, List_Employees maps it to the employee) -- then PROPOSE it with AskUserQuestion: 'Is this the Business Central Issue for this work?' with your best match first, up to two other candidates, 'No Issue for this work', and the free-text answer for another number. Never link without the user's yes; an Issue with no estimate is normal; after the answer run the skill's emit.py AldcIssue line. Do it once, when the work is clear, not as a blocker." ;;
  missing)
    msg="ALDC Issue -- the requirement spec of branch $branch has no '**BC Issue:**' line, so this session's effort is not tied to any Business Central Issue. Once, when the work is clear: work out the likely Issue first with bc-dev:skill-bc-issue -- the repository's customer property plus the open Issues assigned to this developer (tools/issue/whoami.sh gives the company e-mail of the gh account, List_Employees maps it to the employee) -- then PROPOSE it with AskUserQuestion: 'Is this the Business Central Issue for this work?' with your best match first, up to two other candidates, 'No Issue for this work', and the free-text answer for another number. Never link without the user's yes; an Issue with no estimate is normal; then add the line to the spec header ('none' when there is no Issue) and run the skill's emit.py AldcIssue line. Not a blocker." ;;
  *[!0-9]*) exit 0 ;;
  *)
    msg="ALDC Issue -- this session is linked to Business Central Issue $status, read from the spec of branch $branch. Telemetry already carries it: do not ask the user for it again and do not emit it again. Put 'BC Issue: $status' in delegation briefs." ;;
esac

bs=$(printf '\134'); dq=$(printf '\042')
msg="${msg//"$bs"/"$bs$bs"}"; msg="${msg//"$dq"/"$bs$dq"}"
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$msg"
