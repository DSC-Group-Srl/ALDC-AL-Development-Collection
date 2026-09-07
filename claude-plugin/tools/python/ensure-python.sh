#!/usr/bin/env bash
#
# Python bootstrap hook — ensures a python interpreter (python3, python, or the
# Windows `py` launcher) is on PATH, so tools/metrics/*.sh (heartbeat, subagent
# capture, /bc-dev:al-metrics reporting) have something to run their .py scripts
# with. BCQuality itself (tools/bcquality/precondition_hook.sh) has no python
# dependency — this is purely about the metrics/telemetry pipeline. Those
# scripts already silent-degrade (skip with a note) when no interpreter is
# found — this hook exists to make that skip rare instead of the default, by
# installing python where it can, and to give the human a clear, specific
# nudge where it can't.
#
# Wired from hooks/hooks.json on SessionStart. Emits the Copilot hook output
# contract on stdout, same shape as tools/al-cli/ensure-al-tool.sh and
# tools/nodejs/ensure-npx.sh.
set -euo pipefail

EVENT="${1:-SessionStart}"

emit() {
  # $1 must be free of " and \ so this stays valid JSON.
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$1"
}

for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then
    exit 0
  fi
done

# No interpreter at all - try to install one via whatever non-interactive
# package manager is already on this machine. Deliberately skip anything that
# could hang on a prompt (no sudo without -n, no piping a remote installer
# script into bash).
install_msg=""
if command -v winget >/dev/null 2>&1; then
  if winget install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements >/dev/null 2>&1; then
    install_msg="installed via 'winget install Python.Python.3.12'"
  fi
elif command -v brew >/dev/null 2>&1; then
  if brew install python3 >/dev/null 2>&1; then
    install_msg="installed via 'brew install python3'"
  fi
elif command -v apt-get >/dev/null 2>&1; then
  if sudo -n apt-get update >/dev/null 2>&1 && sudo -n apt-get install -y python3 >/dev/null 2>&1; then
    install_msg="installed via 'apt-get install -y python3'"
  fi
fi

if [ -n "$install_msg" ]; then
  emit "Python was missing entirely and has been $install_msg. The ALDC metrics pipeline (heartbeat, SubagentStop capture, /bc-dev:al-metrics) falls back to a degraded no-op without it - restart this session so the refreshed PATH takes effect."
else
  emit "No python interpreter (python3/python/py) is on PATH and it could not be auto-installed (no winget/brew found, or apt requires passwordless sudo which is not configured here). This is non-fatal - everything under tools/metrics/ (heartbeat, SubagentStop capture, /bc-dev:al-metrics) already silently skips its python-backed work without it - but tell the user metrics and the version heartbeat are not being recorded until Python 3 is installed from https://python.org or their platform's package manager."
fi
