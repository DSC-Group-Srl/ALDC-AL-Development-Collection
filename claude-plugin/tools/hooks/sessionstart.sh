#!/usr/bin/env bash
#
# ALDC SessionStart dispatcher — one bash process instead of eight (issue #77).
#
# On Windows every hook is a separate `cmd /c bash <script>`, and Claude Code starts the hooks
# of one event in parallel. Eight concurrent Git Bash (MSYS2) start-ups intermittently die
# before the script runs (`fatal error - add_item (...) failed, errno 1`) and the harness
# silently skips that hook. Here the eight scripts run as background jobs of THIS live MSYS
# process, which does not hit the cold-start race, and still run concurrently.
#
# Each script keeps its own timeout (the values it had in hooks.json). Its stdout goes to its
# own temp file; afterwards every hookSpecificOutput.additionalContext found there is merged,
# in the order below, into ONE payload joined by blank lines. The merge is pure bash: each
# script already JSON-escapes its own text (see emit() in tools/al-cli/ensure-alcops.sh for
# why — Windows paths), so the escaped string is lifted verbatim, never unescaped and
# re-escaped. No python needed: ensure-python.sh is one of the scripts and python may be
# absent. A script that prints nothing, prints non-JSON, crashes or times out contributes
# nothing; the others are unaffected. Never blocks the session: always exits 0.
#
# tools/environment/git-bash-check.ps1 stays its own PowerShell hook: it is the one that
# diagnoses a broken bash, so it must not depend on bash.
#
# Self-test: tools/hooks/test_dispatchers.sh. Overrides for the test only:
#   ALDC_SESSIONSTART_SCRIPTS  newline-separated "<timeout_s> <path> [args...]" lines
#                              replacing the built-in list (paths relative to tools/ or absolute)
#   ALDC_SESSIONSTART_NO_TIMEOUT=1  ignore `timeout` and use the sleep/kill watchdog fallback

set -uo pipefail

EVENT="${1:-SessionStart}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || echo .)"

# hooks.json gives this dispatcher 120 s, the longest single script's budget. A script is capped
# a little below that so the merge always gets to print before the harness kills us.
CAP=115

default_scripts="15 bcquality/precondition_hook.sh $EVENT
60 al-cli/ensure-al-tool.sh $EVENT
30 al-cli/ensure-alcops.sh $EVENT
120 nodejs/ensure-npx.sh $EVENT
60 python/ensure-python.sh $EVENT
15 rules/precondition_hook.sh $EVENT
15 routing/precondition_hook.sh $EVENT
10 metrics/heartbeat.sh"
scripts="${ALDC_SESSIONSTART_SCRIPTS:-$default_scripts}"

tmp="$(mktemp -d 2>/dev/null || { d="${TMPDIR:-/tmp}/aldc-ss-$$"; mkdir -p "$d" && echo "$d"; })"
trap 'rm -rf "$tmp" 2>/dev/null' EXIT

# The hook input (session_id, cwd, source) — none of today's scripts read it, but each gets
# its own copy on stdin as it did when it was a hook of its own.
cat > "$tmp/stdin" 2>/dev/null || : > "$tmp/stdin"

have_timeout=0
[ "${ALDC_SESSIONSTART_NO_TIMEOUT:-}" = "1" ] || { command -v timeout >/dev/null 2>&1 && have_timeout=1; }

pids=()
outs=()
watchdogs=()
i=0
while IFS= read -r line; do
  [ -n "${line// /}" ] || continue
  # shellcheck disable=SC2206 — word-splitting is the point: "<timeout> <path> [args]"
  parts=($line)
  t="${parts[0]}"
  path="${parts[1]:-}"
  args=("${parts[@]:2}")
  case "$t" in ''|*[!0-9]*) t=15 ;; esac
  [ "$t" -gt "$CAP" ] && t=$CAP
  case "$path" in /*|[A-Za-z]:*) ;; *) path="$root/$path" ;; esac
  [ -f "$path" ] || continue
  out="$tmp/out.$i"
  if [ "$have_timeout" -eq 1 ]; then
    timeout -k 2 "$t" bash "$path" "${args[@]}" <"$tmp/stdin" >"$out" &
    pids+=("$!")
    watchdogs+=("")
  else
    bash "$path" "${args[@]}" <"$tmp/stdin" >"$out" &
    pid=$!
    pids+=("$pid")
    ( sleep "$t"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    watchdogs+=("$!")
  fi
  outs+=("$out")
  i=$((i + 1))
done <<<"$scripts"

for k in "${!pids[@]}"; do
  wait "${pids[$k]}" 2>/dev/null
  [ -n "${watchdogs[$k]}" ] && kill "${watchdogs[$k]}" 2>/dev/null
done

# Lift each already-escaped additionalContext string: "...": then a JSON string body of
# non-quote/non-backslash chars or backslash escapes. Bracket expressions take \ literally.
re='"additionalContext"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
merged=""
for out in "${outs[@]}"; do
  [ -s "$out" ] || continue
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"
    if [[ $l =~ $re ]]; then
      ctx="${BASH_REMATCH[1]}"
      [ -n "$ctx" ] || continue
      if [ -z "$merged" ]; then merged="$ctx"; else merged="$merged\\n\\n$ctx"; fi
    fi
  done <"$out"
done

if [ -n "$merged" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$merged"
fi
exit 0
