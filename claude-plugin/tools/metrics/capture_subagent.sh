#!/usr/bin/env bash
#
# ALDC metrics capture — SubagentStop hook.
#
# WHY A HOOK AND NOT OpenTelemetry. Claude Code's built-in OTel exports token usage, cost,
# tool decisions and session counts. It has no API for a plugin to emit its own metrics, and
# ours are semantic: how many BCQuality articles were prescribed, how many the implementer
# applied, how many the review found on its own. Those live in the subagents' final text.
# `SubagentStop` is the one hook that receives that text (`last_assistant_message`) together
# with `agent_type`, so this is where the numbers can be picked up without asking the agents
# to do bookkeeping they would sometimes forget.
#
# WHAT IT STORES — and, more importantly, what it does not.
# Only counts, a verdict, and BCQuality knowledge paths (public Microsoft content). It never
# writes the message body, never a line of customer AL, never a path inside the customer's
# repo, never the full cwd. That is a hard rule, not a default: these files can end up in a
# client project or on a shared endpoint, and a metrics pipeline that quietly accumulates
# customer code is a data-protection incident waiting to happen. Everything is derived by
# matching a handful of symbolic markers; anything unmatched is discarded.
#
# WHERE IT WRITES
#   $CLAUDE_PLUGIN_DATA/metrics/aldc-metrics.jsonl   (always; survives plugin updates)
#   <project>/.github/metrics/aldc-metrics.jsonl     (only if that directory already exists)
#   $ALDC_METRICS_ENDPOINT                           (only if set; see the README)
# The project and endpoint lanes are opt-in by construction: this hook creates neither the
# directory nor the configuration, so an unconfigured install writes to plugin data and
# nowhere else.
#
# NEVER BLOCKS. Best-effort throughout: any failure exits 0 with nothing written. A metrics
# hook that can fail a session is worse than no metrics.
#
# Wired from hooks/hooks.json on SubagentStop.

set -uo pipefail

STDIN_JSON="$(cat 2>/dev/null || true)"
[ -z "$STDIN_JSON" ] && exit 0

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
data_dir="${CLAUDE_PLUGIN_DATA:-${HOME:-${USERPROFILE:-.}}/.claude/aldc-plugin-data}"
out_dir="$data_dir/metrics"
out_file="$out_dir/aldc-metrics.jsonl"
log_file="$out_dir/capture.log"

note() { mkdir -p "$out_dir" 2>/dev/null || true; printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >> "$log_file" 2>/dev/null || true; }

# Python does the JSON work: unescaping `last_assistant_message` by hand is exactly the kind
# of thing that silently mangles a count. Absent python, record the gap rather than guessing
# — a metric quietly derived from a broken parse is worse than a missing one.
PY=""
for c in python3 python py; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
if [ -z "$PY" ]; then
  note "SKIP no python interpreter on PATH - metrics not captured this session"
  exit 0
fi

mkdir -p "$out_dir" 2>/dev/null || true

printf '%s' "$STDIN_JSON" | "$PY" "$script_dir/parse_subagent.py" \
  --out "$out_file" \
  --log "$log_file" \
  >/dev/null 2>>"$log_file" || note "parser failed (non-fatal)"

exit 0
