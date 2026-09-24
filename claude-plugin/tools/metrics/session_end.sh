#!/usr/bin/env bash
# ALDC metrics — SessionEnd hook. Hands the payload to session_end.py, which sums the main
# transcript plus every subagent transcript into one AldcSession event (tokens, wall-clock,
# human turns, tokens per changed AL line). Silent and best-effort: never blocks, never fails.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
PY=""
for c in python3 python py; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
[ -z "$PY" ] && exit 0
cat 2>/dev/null | "$PY" "$here/session_end.py" >/dev/null 2>&1 || true
exit 0
