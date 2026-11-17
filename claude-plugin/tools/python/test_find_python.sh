#!/usr/bin/env bash
# Self-test for find-python.sh: a stub python3 earlier on PATH (the Windows Store alias) must
# not be picked, the working one is cached, and the cache is dropped when its name disappears.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/find-python.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; FAIL=1; }

mkdir -p "$T/stub" "$T/real"
printf '#!/bin/sh\necho "Python was not found" >&2\nexit 9\n' > "$T/stub/python3"
printf '#!/bin/sh\nexit 0\n' > "$T/real/python"
chmod +x "$T/stub/python3" "$T/real/python"
export ALDC_PYTHON_CACHE="$T/cache/python.cmd"

got="$(PATH="$T/stub:$T/real:/usr/bin:/bin" aldc_python)"
[ "$got" = python ] && ok "the stub python3 is skipped, the working python is picked" || bad "picked '$got'"
[ "$(cat "$ALDC_PYTHON_CACHE" 2>/dev/null)" = python ] && ok "the choice is cached" || bad "not cached"

printf '#!/bin/sh\nexit 0\n' > "$T/stub/python3"   # would now work, but the cache wins: no re-check
got="$(PATH="$T/stub:$T/real:/usr/bin:/bin" aldc_python)"
[ "$got" = python ] && ok "a cached choice is reused without starting python again" || bad "cache ignored: '$got'"

rm "$T/real/python"
got="$(PATH="$T/stub:$T/real:/usr/bin:/bin" aldc_python)"
[ "$got" = python3 ] && ok "a cached name gone from PATH is checked again" || bad "stale cache: '$got'"

printf 'rm -rf /\n' > "$ALDC_PYTHON_CACHE"
got="$(PATH="$T/stub:/usr/bin:/bin" aldc_python)"
[ "$got" = python3 ] && ok "a tampered cache is ignored" || bad "tampered cache: '$got'"

rm -f "$T/stub/python3" "$ALDC_PYTHON_CACHE"
got="$(PATH="$T/stub:$T/real" aldc_python)"
[ -z "$got" ] && ok "no python at all: prints nothing" || bad "expected nothing, got '$got'"

[ "$FAIL" = 0 ] && echo "ALL PASSED" || echo "SOME FAILED"
exit "$FAIL"
