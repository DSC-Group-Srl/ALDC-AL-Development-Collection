#!/usr/bin/env bash
#
# ALDC metrics — plugin version heartbeat.
#
# Sends a lightweight "AldcHeartbeat" event to Application Insights whenever this machine's
# bc-dev version changes (an upgrade, reported immediately) or otherwise at most once every
# $ALDC_METRICS_HEARTBEAT_INTERVAL_HOURS (default 24h, so a machine that never upgrades still
# shows up as alive on its current version). This is the answer to "what version do people
# actually have" — the four quality metrics need a review to run before they say anything,
# but everyone updates the plugin before everyone runs a review, so version rollout needs its
# own signal that fires on SessionStart, not on SubagentStop.
#
# NEVER BLOCKS: best-effort throughout, always exits 0. Sends nothing when no connection
# string is configured (env var or the shipped tools/metrics/appinsights.connection default)
# or python is unavailable — same silent-degrade discipline as the BCQuality hook.
#
# Wired from hooks/hooks.json on SessionStart, alongside the BCQuality and rules hooks.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
plugin_root="$(cd "$script_dir/../.." 2>/dev/null && pwd || echo .)"
manifest="$plugin_root/.claude-plugin/plugin.json"
data_dir="${CLAUDE_PLUGIN_DATA:-${HOME:-${USERPROFILE:-.}}/.claude/aldc-plugin-data}/metrics"
time_stamp="$data_dir/.heartbeat-last"
version_stamp="$data_dir/.heartbeat-version"
interval_h="${ALDC_METRICS_HEARTBEAT_INTERVAL_HOURS:-24}"

[ -f "$manifest" ] || exit 0

mkdir -p "$data_dir" 2>/dev/null || true

# Plain grep/sed, no jq dependency — same convention as bcquality.pin's parser.
current_version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest" | head -1 | sed -E 's/.*"([^"]+)"[[:space:]]*$/\1/')
[ -z "$current_version" ] && exit 0

previous_version=$(cat "$version_stamp" 2>/dev/null || echo "")
now=$(date +%s 2>/dev/null || echo 0)
last=$(cat "$time_stamp" 2>/dev/null || echo 0)
age_h=$(( (now - last) / 3600 ))

# Due either because the version changed (report the upgrade now, don't wait for the next
# window) or because the periodic interval elapsed (confirm this machine is still alive on
# its current version).
if [ "$current_version" = "$previous_version" ] && [ "$age_h" -lt "$interval_h" ]; then
  exit 0
fi

for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then
    "$c" "$script_dir/heartbeat.py" \
      --version "$current_version" \
      --previous-version "$previous_version" \
      >/dev/null 2>>"$data_dir/capture.log"
    break
  fi
done

printf '%s' "$current_version" > "$version_stamp" 2>/dev/null || true
date +%s > "$time_stamp" 2>/dev/null || true
exit 0
