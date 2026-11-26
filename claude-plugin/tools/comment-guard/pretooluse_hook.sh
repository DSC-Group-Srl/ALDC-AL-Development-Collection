#!/usr/bin/env bash
#
# DSC comment guard -- PreToolUse, routed by tools/hooks/pretooluse.sh for Write|Edit.
# Denies an edit that adds a comment other than a documentation comment to code
# (.al, .cs, .razor, .cshtml, .js, .ts, .css, .sql, C/AL .txt/.cal). The rules and their
# exceptions live in comment_guard.py; self-test: python tools/comment-guard/test_comment_guard.py
# Kill switch: DSC_COMMENT_GUARD_DISABLE=1. No python on PATH -> silent.
set -uo pipefail
[ "${DSC_COMMENT_GUARD_DISABLE:-}" = "1" ] && exit 0
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../python/find-python.sh" 2>/dev/null || aldc_python() { echo python3 python py; }
for c in $(aldc_python); do
  command -v "$c" >/dev/null 2>&1 || continue
  exec "$c" "$here/comment_guard.py" hook
done
exit 0
