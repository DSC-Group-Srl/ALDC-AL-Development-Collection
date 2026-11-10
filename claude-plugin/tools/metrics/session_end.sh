#!/usr/bin/env bash
# ALDC metrics — SessionEnd hook. Hands the payload to session_end.py, which sums the main
# transcript plus every subagent transcript into one AldcSession event (tokens, wall-clock,
# human turns, tokens per changed AL line). Silent and best-effort: never blocks, never fails.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
PY=""
for c in python3 python py; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
[ -z "$PY" ] && exit 0
# Detached on purpose. When the user exits, Claude Code gives SessionEnd hooks very little time
# and then kills them; summing a long session's transcripts (the ones with a conductor run are
# the longest) takes longer than that. Up to 8.x this ran in the foreground: the telemetry had
# an AldcSession for most /clear events and for almost no real exit, so 18 of 24 finished
# developments had no session total. The payload is parked in a temp file and the worker
# outlives this hook; it removes the file when done.
tmp="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/aldc-session-end-$$")"
cat > "$tmp" 2>/dev/null || { rm -f "$tmp"; exit 0; }
( nohup bash -c '"$0" "$1" < "$2" >/dev/null 2>&1; rm -f "$2"' "$PY" "$here/session_end.py" "$tmp" \
    >/dev/null 2>&1 & ) >/dev/null 2>&1
exit 0
