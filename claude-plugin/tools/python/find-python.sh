#!/usr/bin/env bash
#
# Sourced by every hook and tool that runs a .py script. Defines `aldc_python`, which prints the
# ONE python interpreter that actually runs (python3, python or the Windows `py` launcher), or
# nothing.
#
# Why: on Windows `python3` is very often the Microsoft Store stub - it exists on PATH, so
# `command -v python3` succeeds, and every call fails with "Python was not found". The hooks
# took the first name on PATH, so on those machines the read-guard, the Freshdesk metrics, the
# heartbeat and the run guard's Issue link all failed silently.
#
# Checking means starting python (~50 ms), too slow for hooks that run on every tool call, so
# the answer is cached in ALDC_PYTHON_CACHE (default ~/.claude/aldc-plugin-data/python.cmd) and
# trusted while that name is still on PATH. Delete the file to force a new check.
#
# Usage:  . "$(dirname "${BASH_SOURCE[0]}")/../python/find-python.sh"
#         for c in $(aldc_python); do ...; done      (or PY="$(aldc_python)")
# Self-test: bash tools/python/test_find_python.sh

aldc_python() {
  local f="${ALDC_PYTHON_CACHE:-$HOME/.claude/aldc-plugin-data/python.cmd}" c=""
  [ -r "$f" ] && IFS= read -r c < "$f" 2>/dev/null
  c="${c%$'\r'}"
  case "$c" in
    python3|python|py) command -v "$c" >/dev/null 2>&1 && { printf '%s\n' "$c"; return 0; } ;;
  esac
  for c in python3 python py; do
    command -v "$c" >/dev/null 2>&1 || continue
    "$c" -c '' >/dev/null 2>&1 || continue
    mkdir -p "${f%/*}" 2>/dev/null
    printf '%s' "$c" > "$f" 2>/dev/null
    printf '%s\n' "$c"
    return 0
  done
  return 0
}
