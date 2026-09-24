#!/usr/bin/env bash
# PreToolUse read-guard launcher (matcher: Read|Bash|PowerShell). All logic and its self-test
# live in read_guard.py; this only finds a python interpreter. No python -> allow (fail open).
#
# Fast paths in plain bash so the common case costs no python start-up: a ranged Read, and any
# shell command that is not a bare cat/type/Get-Content, are allowed without spawning python.
set -uo pipefail
[ "${ALDC_READ_GUARD_DISABLE:-}" = "1" ] && exit 0
INPUT="$(cat)"
case "$INPUT" in
  *'"tool_name":"Read"'*|*'"tool_name": "Read"'*)
    case "$INPUT" in *'"offset"'*|*'"limit"'*|*'"pages"'*) exit 0 ;; esac ;;
  *)
    printf '%s' "$INPUT" | grep -qiE '"command"[[:space:]]*:[[:space:]]*"[[:space:]]*(cat|type|get-content|gc)[[:space:]]' || exit 0 ;;
esac
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then
    printf '%s' "$INPUT" | "$c" "$here/read_guard.py"
    exit 0
  fi
done
exit 0
