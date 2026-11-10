#!/usr/bin/env bash
#
# ALDC VS Code workspace nudge — SessionStart hook (run by tools/hooks/sessionstart.sh).
#
# Claude Code starts in ONE folder. When it runs inside a VS Code window (integrated terminal
# or the Claude Code extension panel) that has a multi-root workspace open, the user sees and
# talks about several folders — the app, its test app, a sibling repo — while the agent knows
# only its own cwd and answers "that file does not exist". This hook tells it which other
# folders the window has open.
#
# Source of truth: the lock file the Claude Code VS Code extension writes per window,
# ~/.claude/ide/<port>.lock = {"pid":…,"workspaceFolders":[…],"ideName":…}. Picked by
#   1. $CLAUDE_CODE_SSE_PORT (the extension sets it for sessions of that window), else
#   2. only when the environment says VS Code (TERM_PROGRAM=vscode or any VSCODE_* variable):
#      the live lock whose folders contain the session folder (deepest match wins).
# No lock (extension not installed, plain terminal) -> silent: there is nothing reliable to say.
#
# Reported: workspace folders that neither contain the session folder nor sit inside it, each
# tagged with what it is (AL app name from app.json, own git repo). Silent when there are none.
# Pure bash (python may be absent at SessionStart), one line of additionalContext, never blocks.
#
# Kill switch: ALDC_VSCODE_WORKSPACE_DISABLE=1.
# Test overrides: ALDC_IDE_LOCK_DIR (lock directory), ALDC_VSCODE_MAX_FOLDERS (list cap, 12).
set -uo pipefail

EVENT="${1:-SessionStart}"
[ "${ALDC_VSCODE_WORKSPACE_DISABLE:-}" = "1" ] && exit 0

lock_dir="${ALDC_IDE_LOCK_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/ide}"
[ -d "$lock_dir" ] || exit 0
max="${ALDC_VSCODE_MAX_FOLDERS:-12}"

bs=$(printf '\134'); dq=$(printf '\042')

# norm <path> -> comparable form: forward slashes, no trailing slash, lower-case on Windows
# (drive-letter paths are case-insensitive; the lock says d:\x, the shell says /d/x or D:/x).
norm() {
  local p="${1//"$bs"//}"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  case "$p" in [A-Za-z]:*) p="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')" ;; esac
  printf '%s' "$p"
}

if command -v cygpath >/dev/null 2>&1; then cwd_raw="$(cygpath -m "$PWD" 2>/dev/null || pwd)"; else cwd_raw="$PWD"; fi
cwd="$(norm "$cwd_raw")"

# folders_of <lock file> -> fills FOLDERS with the unescaped workspaceFolders strings.
arr_re='"workspaceFolders"[[:space:]]*:[[:space:]]*\[(([[:space:]]*"([^"\\]|\\.)*"[[:space:]]*,?)*)[[:space:]]*\]'
item_re='^[[:space:],]*"(([^"\\]|\\.)*)"(.*)$'
FOLDERS=()
folders_of() {
  FOLDERS=()
  local json rest item
  json="$(tr -d '\r\n' < "$1" 2>/dev/null)" || return 1
  [[ $json =~ $arr_re ]] || return 1
  rest="${BASH_REMATCH[1]}"
  while [[ $rest =~ $item_re ]]; do
    item="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[3]}"
    item="${item//"$bs$bs"/"$bs"}"; item="${item//"$bs/"//}"; item="${item//"$bs$dq"/"$dq"}"
    [ -n "$item" ] && FOLDERS+=("$item")
  done
  [ "${#FOLDERS[@]}" -gt 0 ]
}

# alive <lock file> -> 0 when the IDE process that wrote it still runs (stale locks survive a crash).
alive() {
  local pid
  pid="$(tr -d '\r\n' < "$1" 2>/dev/null | grep -oE '"pid"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$')"
  [ -n "$pid" ] || return 0
  if command -v tasklist >/dev/null 2>&1; then
    MSYS_NO_PATHCONV=1 tasklist /FI "PID eq $pid" /NH 2>/dev/null | grep -qE "[[:space:]]$pid[[:space:]]"
  else
    kill -0 "$pid" 2>/dev/null
  fi
}

# match_len -> length of the deepest folder in FOLDERS that is, or contains, the session folder.
match_len() {
  local f n best=0
  for f in "${FOLDERS[@]}"; do
    n="$(norm "$f")"
    if [ "$cwd" = "$n" ] || [ "${cwd#"$n"/}" != "$cwd" ]; then
      [ "${#n}" -gt "$best" ] && best="${#n}"
    fi
  done
  printf '%s' "$best"
}

lock=""
port="${CLAUDE_CODE_SSE_PORT:-}"
case "$port" in ''|*[!0-9]*) port="" ;; esac
if [ -n "$port" ] && [ -f "$lock_dir/$port.lock" ]; then
  lock="$lock_dir/$port.lock"
else
  in_vscode=0
  [ "${TERM_PROGRAM:-}" = "vscode" ] && in_vscode=1
  [ -n "$(compgen -v VSCODE_ 2>/dev/null | head -1)" ] && in_vscode=1
  [ "$in_vscode" -eq 1 ] || exit 0
  best=0
  for f in "$lock_dir"/*.lock; do
    [ -f "$f" ] || continue
    folders_of "$f" || continue
    m="$(match_len)"
    [ "$m" -gt "$best" ] || continue
    alive "$f" || continue
    best="$m"; lock="$f"
  done
fi
[ -n "$lock" ] || exit 0
folders_of "$lock" || exit 0

ide="$(tr -d '\r\n' < "$lock" | grep -oE '"ideName"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')"
[ -n "$ide" ] || ide="VS Code"

# describe <folder> -> ' (AL app "Name"; own git repo)' or nothing.
describe() {
  local d="$1" tags="" name
  command -v cygpath >/dev/null 2>&1 && d="$(cygpath -u "$1" 2>/dev/null || printf '%s' "$1")"
  if [ ! -d "$d" ]; then printf ' (not on disk)'; return; fi
  if [ -f "$d/app.json" ]; then
    name="$(grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$d/app.json" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')"
    tags="AL app${name:+ $dq$name$dq}"
  fi
  [ -e "$d/.git" ] && tags="${tags:+$tags; }own git repo"
  [ -n "$tags" ] && printf ' (%s)' "$tags"
  return 0
}

inside=0
others=()
for f in "${FOLDERS[@]}"; do
  n="$(norm "$f")"
  # is, or contains, the session folder
  if [ "$cwd" = "$n" ] || [ "${cwd#"$n"/}" != "$cwd" ]; then inside=1; continue; fi
  # already under the session folder
  [ "${n#"$cwd"/}" != "$n" ] && continue
  others+=("$f")
done
count="${#others[@]}"
[ "$count" -gt 0 ] || exit 0

list=""
shown=0
for f in "${others[@]}"; do
  [ "$shown" -ge "$max" ] && break
  list="${list:+$list | }$f$(describe "$f")"
  shown=$((shown + 1))
done
[ "$count" -gt "$shown" ] && list="$list | ... and $((count - shown)) more"

if [ "$inside" -eq 1 ]; then
  lead="this session started in $cwd_raw, but the $ide window it runs in has a multi-root workspace open with $count more folder(s)"
else
  lead="this session started in $cwd_raw, which is not one of the folders of the $ide window it runs in; that window has $count folder(s) open"
fi
msg="ALDC VS Code workspace -- $lead: $list. The user sees and works across all of them. When they mention a file, app, project or repo that is not under the session folder, look in these folders before saying it does not exist or asking where it is, and take them into account for cross-project work (dependencies, test app, docs, a sibling repo). They are outside this session's working directory: read them freely, but each has its own git state, branch and CLAUDE.md, so do not assume this session's apply there; if an edit or command there is blocked by permissions, tell the user to run /add-dir <folder> rather than working around it. This list was read at session start: folders added to the window later are not in it."

msg="${msg//"$bs"/"$bs$bs"}"; msg="${msg//"$dq"/"$bs$dq"}"
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$msg"
