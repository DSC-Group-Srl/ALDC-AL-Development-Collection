#!/usr/bin/env bash
#
# AL CLI bootstrap hook — ensures the `al` command (ALTool, from the
# Microsoft.Dynamics.BusinessCentral.Development.Tools NuGet package) is
# actually installed, so al-launch.sh (invoked by the plugin's al-mcp MCP
# server in .mcp.json and the AL LSP server in .lsp.json) has something to
# find. This hook only checks/installs the tool — it does not resolve PATH
# for Claude Code, since Claude Code's own resolver silently drops `al` when
# it lives under $HOME (see al-launch.sh for the workaround).
#
# Wired from hooks/hooks.json on SessionStart. Emits the Copilot hook output
# contract on stdout, same shape as tools/bcquality/precondition_hook.sh.
set -euo pipefail

EVENT="${1:-SessionStart}"

emit() {
  # $1 must be free of " and \ so this stays valid JSON.
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$1"
}

if command -v al >/dev/null 2>&1; then
  exit 0
fi

if ! command -v dotnet >/dev/null 2>&1; then
  emit "The AL CLI ('al' command) is not installed and .NET is not on PATH, so it cannot be auto-installed. al-mcp (.mcp.json) and the AL LSP server (.lsp.json) will not start. Install the .NET 8+ SDK, then run: dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools"
  exit 0
fi

if dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools >/dev/null 2>&1; then
  emit "The AL CLI was missing and has been installed via 'dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools'. If al-mcp or the AL LSP server did not start this session, restart it so the refreshed PATH takes effect."
else
  emit "The AL CLI ('al' command) is not installed and automatic install via 'dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools' failed. Run that command manually (check that the NuGet.org source is configured) — al-mcp and the AL LSP server will not start until it succeeds."
fi
