#!/usr/bin/env bash
#
# al-launch.sh — resolves the AL CLI binary and execs it, forwarding all args.
#
# Why this exists: Claude Code's spawner does its own PATH resolution for a
# bare "command" value (e.g. "al") and silently drops the match when the
# resolved path lives under the user's home directory — which is exactly
# where the AL CLI normally lives (`dotnet tool install --global` puts it in
# ~/.dotnet/tools, and the VS Code AL extension puts it under
# ~/.vscode/extensions/ms-dynamics-smb.al-*/bin/). Same root cause reported
# for git and cmd (anthropic/claude-code#50320, #67821).
#
# The fix is to never let Claude Code resolve "al" itself. .mcp.json and
# .lsp.json instead spawn `bash al-launch.sh <original args>` — "bash" is
# the thing Claude Code resolves, and it lives outside $HOME (e.g.
# /usr/bin/bash or Git for Windows' bin), so it isn't filtered. The actual
# `al` lookup below happens inside this already-running bash process, which
# has no such filter.
set -euo pipefail

resolve_al() {
  if command -v al >/dev/null 2>&1; then
    command -v al
    return 0
  fi

  local candidate
  for candidate in \
    "$HOME/.dotnet/tools/al" \
    "$HOME/.dotnet/tools/al.exe" \
    "$HOME"/.vscode/extensions/ms-dynamics-smb.al-*/bin/linux/al \
    "$HOME"/.vscode/extensions/ms-dynamics-smb.al-*/bin/darwin/al \
    "$HOME"/.vscode/extensions/ms-dynamics-smb.al-*/bin/win32/al.exe
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

AL_BIN="$(resolve_al)" || {
  echo "al-launch.sh: could not find the 'al' CLI (checked PATH, ~/.dotnet/tools, and the VS Code AL extension's bin/). Install it with: dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools" >&2
  exit 1
}

exec "$AL_BIN" "$@"
