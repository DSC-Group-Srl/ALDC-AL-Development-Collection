#!/usr/bin/env bash
# Thin launcher for report.py — finds a python interpreter and passes the flags through.
# Invoked by /aldc:al-metrics so the command does not have to know which python is present.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then
    exec "$c" "$here/report.py" --project-dir "${CLAUDE_PROJECT_DIR:-$PWD}" "$@"
  fi
done
echo "No python interpreter on PATH — metrics reporting needs python3." >&2
echo "The capture hook has the same requirement; see metrics/capture.log." >&2
exit 2
