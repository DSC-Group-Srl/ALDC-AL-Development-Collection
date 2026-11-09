#!/usr/bin/env bash
#
# ALDC CLAUDE.md freshness nudge — SessionStart hook (run by tools/hooks/sessionstart.sh).
#
# The project CLAUDE.md loads into every session and subagent. It grows by accretion (session
# diaries, one-off fixes, notes that contradict the plugin) and nobody prunes it. This hook
# suggests /bc-dev:al-memory-create (prune and recreate) when, in an AL workspace:
#   - the last refresh (the stamp line `<!-- aldc-refreshed: YYYY-MM-DD -->` the command writes)
#     is older than ALDC_CLAUDEMD_MAX_AGE_DAYS (default 30), or there is no stamp, AND
#     CLAUDE.md changed since then (git log), or
#   - CLAUDE.md is over ALDC_CLAUDEMD_MAX_LINES (default 150) lines.
# One line of additionalContext, never blocking, silent when nothing applies.
# Kill switch: ALDC_CLAUDEMD_NUDGE_DISABLE=1.
set -uo pipefail

EVENT="${1:-SessionStart}"
[ "${ALDC_CLAUDEMD_NUDGE_DISABLE:-}" = "1" ] && exit 0
[ -f CLAUDE.md ] || exit 0
if [ ! -f "app.json" ] && ! find . -maxdepth 2 -iname "app.json" -print -quit 2>/dev/null | grep -q .; then
  exit 0
fi

max_age="${ALDC_CLAUDEMD_MAX_AGE_DAYS:-30}"
max_lines="${ALDC_CLAUDEMD_MAX_LINES:-150}"
lines="$(wc -l < CLAUDE.md | tr -d ' ')"

stamp="$(grep -oE 'aldc-refreshed: [0-9]{4}-[0-9]{2}-[0-9]{2}' CLAUDE.md | head -1 | awk '{print $2}')"
today_s="$(date +%s)"
reason=""
if [ -z "$stamp" ]; then
  reason="it has never been pruned by the plugin"
else
  stamp_s="$(date -d "$stamp" +%s 2>/dev/null || echo "$today_s")"
  age=$(( (today_s - stamp_s) / 86400 ))
  if [ "$age" -ge "$max_age" ]; then
    changed="$(git log --since="$stamp" --format=%h -- CLAUDE.md 2>/dev/null | head -1)"
    [ -n "$changed" ] && reason="last pruned $age days ago and edited since"
  fi
fi
if [ "${lines:-0}" -gt "$max_lines" ]; then
  reason="${reason:+$reason; }it is $lines lines (over $max_lines)"
fi
[ -n "$reason" ] || exit 0

msg="ALDC CLAUDE.md -- the project CLAUDE.md loads into every session and subagent, and $reason. Mention once, in one line at the end of your first reply, that /bc-dev:al-memory-create prunes and recreates it (shows the result before writing). Do not run it unasked, and do not add to CLAUDE.md in the meantime: decisions go to app/requirements/memory.md."

bs=$(printf '\134'); dq=$(printf '\042')
msg="${msg//"$bs"/"$bs$bs"}"; msg="${msg//"$dq"/"$bs$dq"}"
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$msg"
