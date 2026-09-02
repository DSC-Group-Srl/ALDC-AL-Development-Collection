#!/usr/bin/env bash
#
# ALCops bootstrap hook — ensures the ALCops analyzer DLLs (the successor to
# BusinessCentral.LinterCop, see https://alcops.dev/docs/lintercop-migration/)
# are present wherever `${analyzerFolder}` in a project's `.vscode/settings.json`
# resolves, so `al.codeAnalyzers` entries like
# `${analyzerFolder}ALCops.LinterCop.dll` actually resolve.
#
# `${analyzerFolder}` is not just a VS Code-editor concept: al-mcp (.mcp.json)
# and the AL LSP server (.lsp.json) are both launched via al-launch.sh, which
# runs the SAME Microsoft.Dynamics.Nav.CodeAnalysis engine the VS Code AL
# extension embeds — headless, with no VS Code UI ever open to trigger the
# ALCops VS Code extension's own "download on first use". Relying solely on
# that extension would silently leave al-mcp/LSP running old/no analyzers.
# So this hook downloads the ALCops.Analyzers NuGet package directly and
# copies the DLLs into every analyzer folder found on the machine — found by
# locating the AL Language VS Code extension's `bin/Analyzers` directory,
# the one place both the editor and al-mcp/LSP are known to read
# `${analyzerFolder}`-prefixed entries from (confirmed by finding the old
# BusinessCentral.LinterCop.dll living there).
#
# Also installs the ALCops VS Code extension (Arthurvdv.alcops) when the
# `code` CLI is available, so interactive editing gets ALCops' own
# update-tracking/notification UX on top of the DLLs this hook places.
#
# Wired from hooks/hooks.json on SessionStart. Emits the Copilot hook output
# contract on stdout, same shape as ensure-al-tool.sh. Idempotent and cheap
# on repeat runs: skips the network entirely once ALCops.LinterCop.dll is
# already present in every discovered analyzer folder.
set -euo pipefail

EVENT="${1:-SessionStart}"
EXTENSION_ID="Arthurvdv.alcops"
PACKAGE="alcops.analyzers"
DLLS=(ALCops.ApplicationCop.dll ALCops.Common.dll ALCops.DocumentationCop.dll ALCops.FormattingCop.dll ALCops.LinterCop.dll ALCops.PlatformCop.dll ALCops.TestAutomationCop.dll)

emit() {
  # $1 must be free of " and \ so this stays valid JSON.
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$1"
}

join_dirs() {
  local IFS=', '
  echo "${TARGET_DIRS[*]}"
}

# --- Part 1: VS Code extension, for the interactive editing experience ---
if command -v code >/dev/null 2>&1 && ! code --list-extensions 2>/dev/null | grep -qi "^${EXTENSION_ID}$"; then
  code --install-extension "$EXTENSION_ID" >/dev/null 2>&1 || true
fi

# --- Part 2: the DLLs themselves, for al-mcp/LSP (and as a fallback for the
# editor, so headless environments don't depend on the extension activating) ---
# Locate by the extension root, not by an existing Analyzers folder: a fresh
# AL extension install has no bin/Analyzers directory yet (it's created lazily
# on first analyzer download), so `find -iname Analyzers` would find nothing
# and this hook would wrongly conclude the extension itself isn't installed.
mapfile -t EXT_DIRS < <(find "$HOME/.vscode/extensions" -maxdepth 1 -type d -iname "ms-dynamics-smb.al-*" 2>/dev/null)

if [ "${#EXT_DIRS[@]}" -eq 0 ]; then
  # No AL Language VS Code extension installed at all — nothing to seed yet;
  # it will be installed by its own onboarding, and this hook will catch up
  # next session.
  exit 0
fi

TARGET_DIRS=()
for ext_dir in "${EXT_DIRS[@]}"; do
  TARGET_DIRS+=("$ext_dir/bin/Analyzers")
done
mkdir -p "${TARGET_DIRS[@]}"

NEEDS_DOWNLOAD=0
for dir in "${TARGET_DIRS[@]}"; do
  if [ ! -f "$dir/ALCops.LinterCop.dll" ]; then
    NEEDS_DOWNLOAD=1
  fi
done

if [ "$NEEDS_DOWNLOAD" -eq 0 ]; then
  emit "ALCops.*.dll analyzers are already installed and up to date in: $(join_dirs). Let the user know their AL analyzer setup is ready — no action needed."
  exit 0
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
  emit "ALCops analyzer DLLs are missing from $(join_dirs) and this hook needs curl+unzip to fetch them automatically. Install the ALCops.Analyzers NuGet package manually (https://alcops.dev/docs/downloading-analyzers/) and copy lib/net8.0/ALCops.*.dll into each folder above."
  exit 0
fi

VERSION="$(curl -fsSL "https://api.nuget.org/v3-flatcontainer/${PACKAGE}/index.json" 2>/dev/null | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | tail -n1 || true)"

if [ -z "$VERSION" ]; then
  emit "Could not reach NuGet.org to fetch the latest ALCops.Analyzers version, so the ALCops.*.dll analyzers referenced in .vscode/settings.json are still missing from $(join_dirs). Retry once network access is available, or install manually per https://alcops.dev/docs/downloading-analyzers/."
  exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if ! curl -fsSL -o "$WORKDIR/alcops.nupkg" \
  "https://api.nuget.org/v3-flatcontainer/${PACKAGE}/${VERSION}/${PACKAGE}.${VERSION}.nupkg" 2>/dev/null; then
  emit "Downloading ALCops.Analyzers $VERSION from NuGet.org failed, so the ALCops.*.dll analyzers are still missing from $(join_dirs). Retry next session, or install manually per https://alcops.dev/docs/downloading-analyzers/."
  exit 0
fi

if ! unzip -q -o "$WORKDIR/alcops.nupkg" 'lib/net8.0/*' -d "$WORKDIR" 2>/dev/null; then
  emit "Extracting the ALCops.Analyzers $VERSION package failed, so the ALCops.*.dll analyzers are still missing from $(join_dirs). Retry next session, or install manually per https://alcops.dev/docs/downloading-analyzers/."
  exit 0
fi

for dir in "${TARGET_DIRS[@]}"; do
  for dll in "${DLLS[@]}"; do
    [ -f "$WORKDIR/lib/net8.0/$dll" ] && cp -f "$WORKDIR/lib/net8.0/$dll" "$dir/$dll"
  done
done

emit "The ALCops.*.dll analyzers (v$VERSION, successor to BusinessCentral.LinterCop) were missing and have been installed into: $(join_dirs). Reload any open AL project so al-mcp/the AL LSP server and the editor pick them up."
