#!/usr/bin/env bash
#
# Node.js/npx bootstrap hook — ensures `npx` (bundled with Node.js) is
# installed and meets the nab-al-tools MCP server's minimum Node >= 20
# requirement, so .mcp.json's "nab-al-tools" server
# (npx -y @nabsolutions/nab-al-tools-mcp@next) has something to run.
#
# Wired from hooks/hooks.json on SessionStart. Emits the Copilot hook output
# contract on stdout, same shape as tools/al-cli/ensure-al-tool.sh.
set -euo pipefail

EVENT="${1:-SessionStart}"
MIN_NODE_MAJOR=20

emit() {
  # $1 must be free of " and \ so this stays valid JSON.
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$1"
}

if command -v npx >/dev/null 2>&1; then
  node_version="$(node --version 2>/dev/null || true)"
  node_major="${node_version#v}"
  node_major="${node_major%%.*}"
  if [[ "$node_major" =~ ^[0-9]+$ ]] && [ "$node_major" -lt "$MIN_NODE_MAJOR" ]; then
    emit "npx is installed but Node.js is $node_version, below the v$MIN_NODE_MAJOR the nab-al-tools MCP server (.mcp.json) requires. Left untouched in case a version manager (nvm/fnm/volta) manages it - tell the user to upgrade Node.js to >= $MIN_NODE_MAJOR, then restart the session."
  fi
  exit 0
fi

if command -v node >/dev/null 2>&1; then
  # A Node.js binary exists but npx does not - this is a broken/partial
  # install (commonly a version manager like nvm/fnm/nvm-windows whose
  # active version was installed without npm bundled). Do NOT auto-install a
  # second, competing Node.js here: that would silently create a PATH
  # conflict with whatever the user's version manager is doing. Report it
  # and let the human fix the version manager's install instead.
  node_version="$(node --version 2>/dev/null || true)"
  emit "node ($node_version) is on PATH but npx is not - looks like a broken or partial Node.js install (common with version managers like nvm/fnm/nvm-windows whose active version was installed without npm bundled). Left untouched rather than auto-installing a second, competing Node.js. The nab-al-tools MCP server (.mcp.json) will not start until npm/npx is restored for this Node install (e.g. reinstall/repair the active version via your version manager) - tell the user."
  exit 0
fi

# No Node.js at all - try to install Node.js LTS (which bundles npx) via
# whatever non-interactive package manager is already on this machine.
# Deliberately skip anything that could hang on a prompt (no sudo without
# -n, no piping a remote installer script into bash).
install_msg=""
if command -v winget >/dev/null 2>&1; then
  if winget install --id OpenJS.NodeJS.LTS -e --silent --accept-package-agreements --accept-source-agreements >/dev/null 2>&1; then
    install_msg="installed via 'winget install OpenJS.NodeJS.LTS'"
  fi
elif command -v brew >/dev/null 2>&1; then
  if brew install node >/dev/null 2>&1; then
    install_msg="installed via 'brew install node'"
  fi
elif command -v apt-get >/dev/null 2>&1; then
  if sudo -n apt-get update >/dev/null 2>&1 && sudo -n apt-get install -y nodejs npm >/dev/null 2>&1; then
    install_msg="installed via 'apt-get install -y nodejs npm'"
  fi
fi

if [ -n "$install_msg" ]; then
  emit "Node.js/npx was missing entirely and Node.js was just $install_msg. The nab-al-tools MCP server (.mcp.json) needs it - restart this session so the refreshed PATH takes effect."
else
  emit "Node.js/npx (npx is bundled with Node.js >= $MIN_NODE_MAJOR) is not installed and could not be auto-installed (no winget/brew found, and apt requires passwordless sudo which is not configured here). The nab-al-tools MCP server (.mcp.json) will not start until Node.js >= $MIN_NODE_MAJOR is installed from https://nodejs.org or your platform's package manager."
fi
