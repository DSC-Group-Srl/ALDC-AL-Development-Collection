#!/usr/bin/env bash
set -euo pipefail

MIN_NODE_MAJOR=20
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_node() {
  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi
  local candidate
  for candidate in \
    "${ProgramW6432:-/c/Program Files}/nodejs/node.exe" \
    "/c/Program Files/nodejs/node.exe" \
    "${NVM_SYMLINK:-/nonexistent}/node.exe" \
    "$HOME/.volta/bin/node" \
    /usr/local/bin/node \
    /opt/homebrew/bin/node
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

NODE_BIN="$(resolve_node)" || {
  echo "al-lint: Node.js not found (PATH, Program Files, nvm, volta). Install Node.js >= $MIN_NODE_MAJOR; the SessionStart hook tools/nodejs/ensure-npx.sh tries to. The static pass did not run." >&2
  exit 1
}

node_version="$("$NODE_BIN" --version 2>/dev/null || true)"
node_major="${node_version#v}"
node_major="${node_major%%.*}"
if ! [[ "$node_major" =~ ^[0-9]+$ ]] || [ "$node_major" -lt "$MIN_NODE_MAJOR" ]; then
  echo "al-lint: Node.js ${node_version:-of unknown version} at $NODE_BIN is below v$MIN_NODE_MAJOR. The static pass did not run." >&2
  exit 1
fi

exec "$NODE_BIN" "$here/dsc-al-lint.mjs" "$@"
