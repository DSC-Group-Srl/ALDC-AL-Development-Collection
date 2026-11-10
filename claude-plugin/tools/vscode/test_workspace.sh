#!/usr/bin/env bash
# Self-test for tools/vscode/workspace_hook.sh. Fake lock directory and fake folders only;
# exits non-zero on any failure. Needs python or node only to VALIDATE the JSON.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/workspace_hook.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; FAIL=1; }
check() { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1 :: ${2:0:500}"; fi; }
lacks() { if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1 :: ${2:0:500}"; else ok "$1"; fi; }
empty() { if [ -z "$2" ]; then ok "$1"; else bad "$1 :: ${2:0:300}"; fi; }

# native <posix path> -> the form VS Code writes into the lock (d:\x on Windows), JSON-escaped.
native() {
  local p="$1"
  command -v cygpath >/dev/null 2>&1 && p="$(cygpath -w "$1")"
  printf '%s' "${p//\\/\\\\}"
}
# lock <port> <pid> <folder>... -> writes $LOCKS/<port>.lock
lock() {
  local port="$1" pid="$2" list="" f; shift 2
  for f in "$@"; do list="${list:+$list,}\"$(native "$f")\""; done
  printf '{"pid":%s,"workspaceFolders":[%s],"ideName":"Visual Studio Code","transport":"ws","authToken":"secret-token"}' \
    "$pid" "$list" > "$LOCKS/$port.lock"
}
valid_json() {
  if command -v python >/dev/null 2>&1; then printf '%s' "$1" | python -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
  elif command -v node >/dev/null 2>&1; then printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>JSON.parse(s))' 2>/dev/null
  else return 0; fi
}

LOCKS="$T/ide"; mkdir -p "$LOCKS"
W="$T/My Repos/prod [x]"
mkdir -p "$W/app" "$W/app-test" "$W/docs" "$T/sibling/.git" "$T/elsewhere"
printf '{\n  "id": "x",\n  "name": "Prod Tests",\n  "publisher": "DSC"\n}\n' > "$W/app-test/app.json"
export ALDC_IDE_LOCK_DIR="$LOCKS"
unset ALDC_VSCODE_WORKSPACE_DISABLE ALDC_VSCODE_MAX_FOLDERS CLAUDE_CODE_SSE_PORT
# The fallback path only runs when the environment says VS Code; start from a clean slate.
for v in $(compgen -v VSCODE_); do unset "$v"; done
unset TERM_PROGRAM
LIVE=$$   # a pid that certainly runs; on Git Bash it is an MSYS pid tasklist does not know,
          # so the fallback cases use a real Windows pid when one is available.
if command -v tasklist >/dev/null 2>&1; then
  LIVE="$(MSYS_NO_PATHCONV=1 tasklist /NH 2>/dev/null | awk '$2 ~ /^[0-9]+$/ && $2 > 100 {print $2; exit}')"
fi

lock 1111 "$LIVE" "$W/app" "$W/app-test" "$W/docs" "$W" "$T/sibling"

cd "$W/app"
o="$(CLAUDE_CODE_SSE_PORT=1111 bash "$HOOK")"
check "port: lists the test app with its name" "$o" 'AL app \"Prod Tests\"'
check "port: lists the sibling repo" "$o" 'own git repo'
check "port: counts the other folders" "$o" '3 more folder(s)'
check "port: spaces and brackets survive" "$o" 'prod [x]'
lacks "port: no auth token leaks" "$o" 'secret-token'
if valid_json "$o"; then ok "port: valid JSON"; else bad "port: invalid JSON :: ${o:0:300}"; fi
[ "$(printf '%s\n' "$o" | wc -l)" -eq 1 ] && ok "port: one line" || bad "port: more than one line"

cd "$W"
o="$(CLAUDE_CODE_SSE_PORT=1111 bash "$HOOK")"
check "root: only folders outside the session folder" "$o" '1 more folder(s)'
lacks "root: nested folders are not repeated" "$o" 'Prod Tests'

cd "$T/elsewhere"
o="$(CLAUDE_CODE_SSE_PORT=1111 bash "$HOOK")"
check "outside: says the session folder is not in the window" "$o" 'not one of the folders'
check "outside: lists every folder" "$o" '5 folder(s) open'

cd "$W/app"
o="$(CLAUDE_CODE_SSE_PORT=1111 ALDC_VSCODE_MAX_FOLDERS=1 bash "$HOOK")"
check "cap: the rest is counted" "$o" 'and 2 more'
o="$(CLAUDE_CODE_SSE_PORT=1111 ALDC_VSCODE_WORKSPACE_DISABLE=1 bash "$HOOK")"; empty "kill switch" "$o"
o="$(bash "$HOOK")"; empty "no port, not in VS Code: silent" "$o"
o="$(TERM_PROGRAM=vscode bash "$HOOK")"
check "fallback: lock found by session folder" "$o" '3 more folder(s)'
o="$(VSCODE_PID=1 bash "$HOOK")"
check "fallback: any VSCODE_ variable counts" "$o" '3 more folder(s)'

# Two windows contain the folder: the deepest match wins; a dead window is skipped.
lock 2222 "$LIVE" "$T" "$T/elsewhere"
o="$(TERM_PROGRAM=vscode bash "$HOOK")"
check "fallback: deepest match wins" "$o" '3 more folder(s)'
lock 1111 999999999 "$W/app" "$W/app-test"
o="$(TERM_PROGRAM=vscode bash "$HOOK")"
lacks "fallback: stale lock skipped" "$o" 'Prod Tests'
o="$(CLAUDE_CODE_SSE_PORT=7777 TERM_PROGRAM=vscode bash "$HOOK")"
lacks "port without a lock file falls back" "$o" 'Prod Tests'

# Single-folder window, garbage lock, missing directory: silent.
rm -f "$LOCKS"/*.lock; lock 3333 "$LIVE" "$W/app"
o="$(CLAUDE_CODE_SSE_PORT=3333 bash "$HOOK")"; empty "single-folder window: silent" "$o"
printf 'not json' > "$LOCKS/4444.lock"
o="$(CLAUDE_CODE_SSE_PORT=4444 bash "$HOOK")"; empty "garbage lock: silent" "$o"
o="$(ALDC_IDE_LOCK_DIR="$T/nope" CLAUDE_CODE_SSE_PORT=3333 bash "$HOOK")"; empty "no lock directory: silent" "$o"

exit $FAIL
