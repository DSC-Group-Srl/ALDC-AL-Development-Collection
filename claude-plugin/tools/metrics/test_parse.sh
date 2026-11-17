#!/usr/bin/env bash
# Runs the metrics parser's self-test. Exits non-zero on any failed assertion, including the
# two privacy assertions (no customer path, no message body in the emitted record).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../python/find-python.sh" 2>/dev/null || aldc_python() { echo python3 python py; }
cd "$(dirname "${BASH_SOURCE[0]}")"
for c in $(aldc_python); do command -v "$c" >/dev/null 2>&1 && exec "$c" parse_subagent.py --self-test; done
echo "no python interpreter on PATH" >&2
exit 2
