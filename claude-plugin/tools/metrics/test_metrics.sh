#!/usr/bin/env bash
# Runs every self-test in tools/metrics/: the marker parser, the Application Insights
# envelope builder (incl. connection-string resolution and the disable switch), and the
# heartbeat event shape. Exits non-zero if any assertion fails — including the privacy
# assertions (no customer path, no message body ever reaches an emitted record or envelope).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

PY=""
for c in python3 python py; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
if [ -z "$PY" ]; then
  echo "no python interpreter on PATH" >&2
  exit 2
fi

status=0
for mod in parse_subagent appinsights heartbeat; do
  echo "=== $mod ==="
  "$PY" "$mod.py" --self-test || status=1
  echo
done
exit "$status"
