#!/usr/bin/env bash
#
# ALDC PreToolUse dispatcher — the ONLY PreToolUse entry in hooks/hooks.json (no matcher, so
# it runs on every tool call).
#
# Why one process (issue #77): on Windows every hook is a separate `cmd /c bash <script>`, and
# Claude Code starts the hooks of one event in parallel. Concurrent Git Bash (MSYS2) start-ups
# intermittently die before the script runs (`fatal error - add_item (...) failed, errno 1`),
# and the harness then silently skips that hook — guards included. Before this dispatcher a
# Write|Edit call started 3 bash processes and a Read|Bash|PowerShell call 2. Now every tool
# call starts exactly one; the scripts below are children of a live MSYS process.
#
# What it does:
#   1. reads stdin once;
#   2. runs tools/metrics/alive.sh in the background (never blocks, never prints);
#   3. routes by tool_name and feeds the same stdin to the guards:
#        Read|Bash|PowerShell -> tools/read-guard/pretooluse_hook.sh
#        Write|Edit           -> tools/conductor-guard/pretooluse_hook.sh,
#                                then tools/main-thread-guard/pretooluse_hook.sh
#      any other tool         -> exit 0, silent.
#
# Contract kept from the guards themselves: a decision is JSON on stdout with exit 0
# (hookSpecificOutput.permissionDecision). The first guard that emits a deny wins and later
# guards are not run (main-thread-guard's fast-path counter must not tick for a call that is
# denied anyway). A guard that exits 2 is a blocking error in Claude Code's contract: its
# stderr already went to ours, and we exit 2 too. A guard that crashes with any other code
# is treated as "no decision" (the harness used to log that as a non-blocking error).
# Guard stderr is passed through unchanged.
#
# Each guard keeps its own kill switch (ALDC_READ_GUARD_DISABLE, ALDC_MAIN_THREAD_GUARD_DISABLE,
# ALDC_METRICS_ALIVE_DISABLE). Self-test: tools/hooks/test_dispatchers.sh.

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || echo .)"

# 1. Liveness heartbeat — fully detached, output discarded. `( cmd & )` reparents the child so
# the dispatcher does not wait for it.
if [ -f "$root/metrics/alive.sh" ]; then
  ( printf '%s' "$INPUT" | bash "$root/metrics/alive.sh" >/dev/null 2>&1 & ) >/dev/null 2>&1
fi

tool="$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
  | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)"

case "$tool" in
  Read|Bash|PowerShell) guards=("read-guard/pretooluse_hook.sh") ;;
  Write|Edit)           guards=("conductor-guard/pretooluse_hook.sh" "main-thread-guard/pretooluse_hook.sh") ;;
  *)                    exit 0 ;;
esac

first_output=""
for g in "${guards[@]}"; do
  script="$root/$g"
  [ -f "$script" ] || continue
  out="$(printf '%s' "$INPUT" | bash "$script")"
  rc=$?
  if [ "$rc" -eq 2 ]; then
    # Blocking error: the guard's stderr is already on ours; anything it printed on stdout
    # is ignored by Claude Code for exit 2, same as before.
    exit 2
  fi
  [ "$rc" -eq 0 ] || continue
  [ -n "$out" ] || continue
  if printf '%s' "$out" | grep -qE '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    printf '%s\n' "$out"
    exit 0
  fi
  [ -z "$first_output" ] && first_output="$out"
done

# No deny: pass on the first non-deny decision a guard made (none of today's guards emit one,
# but an "ask" or "allow" must not be swallowed if one ever does). Otherwise silent.
[ -n "$first_output" ] && printf '%s\n' "$first_output"
exit 0
