#!/usr/bin/env bash
#
# BCQuality precondition hook — detects whether the shared BCQuality knowledge
# base is present, auto-installs it on first use, and keeps it refreshed in the
# background. INJECTS a directive into the agent session via additionalContext.
#
# This is the single source of the "what to do about BCQuality" rule (Layer 2 of
# the precondition-hook design). It replaces the precondition prose duplicated in
# each consuming agent: detection is deterministic here, the agent just enacts the
# injected directive. The agents keep a thin prose backstop in case the hook does
# not fire.
#
# USER-SCOPE, NOT PROJECT-SCOPE. The clone lives ONCE at ~/.claude/bcquality
# (override: $BCQUALITY_HOME) and is shared by every AL project on this machine —
# no more "../bcquality" sibling folder cluttering each project. First run clones
# it in the background (this session still runs the native A-G checklist, since
# the clone isn't ready yet); later runs fetch a fresh copy in the background at
# most once every $BCQUALITY_UPDATE_INTERVAL_HOURS (default 12h). The background
# job never blocks or fails the session, even fully offline.
#
# A project's aldc.yaml (if present) can still override home/entryPoint/url/ref/
# pinnedCommit for advanced/pinned use, but is no longer required — the defaults
# below are enough to make BCQuality work with zero per-project setup.
#
# Wired from hooks/hooks.json on SessionStart.
# Emits the Copilot hook output contract on stdout:
#   {"hookSpecificOutput":{"hookEventName":"<Event>","additionalContext":"<text>"}}
#
# NOTE: messages below deliberately avoid " and \ so a plain printf yields valid
# JSON with no dependency on python/jq.
set -euo pipefail

EVENT="${1:-SessionStart}"
ALDC="aldc.yaml"

url="https://github.com/microsoft/BCQuality.git"
ref="main"
pin=""
entry="skills/entry.md"
default_home="${HOME:-${USERPROFILE:-.}}/.claude/bcquality"

# Source and version ship with the plugin in bcquality.pin — the single source of
# truth, rewritten by the weekly bump workflow. Resolved from this script's own
# directory so it works whether or not $CLAUDE_PLUGIN_ROOT is exported.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
pinfile="$script_dir/bcquality.pin"
pinval() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$pinfile" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]' || true; }
if [ -f "$pinfile" ]; then
  v=$(pinval url); [ -n "${v:-}" ] && url="$v"
  v=$(pinval ref); [ -n "${v:-}" ] && ref="$v"
  v=$(pinval pin); [ -n "${v:-}" ] && pin="$v"
fi

# DSC's BCQuality /custom/ layer ships inside the plugin and is overlaid onto the clone.
# It lives untracked in the clone's custom/ (upstream tracks only .gitkeep there), so it
# survives the checkout --detach of a refresh. Re-applied every session so a plugin
# upgrade lands without waiting for the next fetch. Strict no-op while the layer is empty.
custom_src="$(cd "$script_dir/../.." 2>/dev/null && pwd)/bcquality-custom"

custom_layer_files() {
  [ -d "$custom_src" ] || { echo 0; return 0; }
  find "$custom_src/knowledge" "$custom_src/skills" -type f ! -name '.gitkeep' 2>/dev/null | wc -l | tr -d '[:space:]'
}

apply_custom_overlay() {
  dest="$1"
  [ -d "$custom_src" ] || return 0
  for sub in knowledge skills; do
    [ -d "$custom_src/$sub" ] || continue
    if [ -n "$(find "$custom_src/$sub" -type f ! -name '.gitkeep' 2>/dev/null | head -1)" ]; then
      mkdir -p "$dest/custom/$sub" 2>/dev/null || true
      cp -rf "$custom_src/$sub/." "$dest/custom/$sub/" 2>/dev/null || true
    fi
  done
}

# A project's aldc.yaml still wins over the shipped pin (advanced/per-project use).
if [ -f "$ALDC" ]; then
  h=$(grep -E '^[[:space:]]*home:' "$ALDC" | head -1 | sed -E 's/.*home:[[:space:]]*"?([^"#]+)"?.*/\1/' | tr -d '[:space:]' || true)
  e=$(grep -E '^[[:space:]]*entryPoint:' "$ALDC" | head -1 | sed -E 's/.*entryPoint:[[:space:]]*"?([^"#]+)"?.*/\1/' | tr -d '[:space:]' || true)
  u=$(grep -E '^[[:space:]]*url:' "$ALDC" | head -1 | sed -E 's/.*url:[[:space:]]*"?([^"#]+)"?.*/\1/' | tr -d '[:space:]' || true)
  r=$(grep -E '^[[:space:]]*ref:' "$ALDC" | head -1 | sed -E 's/.*ref:[[:space:]]*"?([^"#]+)"?.*/\1/' | tr -d '[:space:]' || true)
  p=$(grep -E '^[[:space:]]*pinnedCommit:' "$ALDC" | head -1 | sed -E 's/.*pinnedCommit:[[:space:]]*"?([^"#]*)"?.*/\1/' | tr -d '[:space:]' || true)
  [ -n "${h:-}" ] && default_home="$h"
  [ -n "${e:-}" ] && entry="$e"
  [ -n "${u:-}" ] && url="$u"
  [ -n "${r:-}" ] && ref="$r"
  [ -n "${p:-}" ] && pin="$p"
fi

home="${BCQUALITY_HOME:-$default_home}"
entrypath="$home/$entry"
target="${pin:-$ref}"
interval_h="${BCQUALITY_UPDATE_INTERVAL_HOURS:-12}"
lockdir="${home}.lock"
stamp="${home}.last-check"
logfile="${home}.log"
syncscript="${home}.sync.sh"

emit() {
  # $1 must be free of " and \ (kept that way below) so this stays valid JSON.
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$1"
}

acquire_lock() { mkdir "$lockdir" 2>/dev/null; }

# Writes a standalone sync script (paths baked in) and backgrounds it fully
# detached — `( cmd & )` exiting its subshell immediately reparents the child so
# it outlives this hook process, with no dependency on nohup/setsid being present.
spawn_background_sync() {
  cat > "$syncscript" <<EOF
#!/usr/bin/env bash
set -eu
trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT
date +%s > "$stamp" 2>/dev/null || true
mkdir -p "$home"
if [ ! -d "$home/.git" ]; then
  git init --quiet "$home"
  git -C "$home" remote add origin "$url"
fi
# Windows/NTFS: BCQuality's nested knowledge paths can exceed MAX_PATH (260)
# under a deep user profile; without this, checkout silently drops files.
git -C "$home" config core.longpaths true
if ! git -C "$home" fetch --quiet --depth 1 origin "$target"; then
  git -C "$home" fetch --quiet --depth 1 origin "$ref" || exit 0
fi
git -C "$home" checkout --quiet --detach FETCH_HEAD
# Re-apply the plugin's /custom/ layer: a fresh clone has none, and a refresh does not
# remove untracked files but a first install has nothing to preserve.
for sub in knowledge skills; do
  if [ -d "$custom_src/\$sub" ] && [ -n "\$(find "$custom_src/\$sub" -type f ! -name .gitkeep 2>/dev/null | head -1)" ]; then
    mkdir -p "$home/custom/\$sub"
    cp -rf "$custom_src/\$sub/." "$home/custom/\$sub/"
  fi
done
EOF
  chmod +x "$syncscript" 2>/dev/null || true
  ( bash "$syncscript" >>"$logfile" 2>&1 & )
}

if [ -f "$entrypath" ]; then
  apply_custom_overlay "$home"
  custom_n=$(custom_layer_files)
  custom_note=""
  [ "${custom_n:-0}" -gt 0 ] && custom_note=" DSC custom layer overlaid (${custom_n} files) - it wins over the microsoft and community layers."
  sha=$(git -C "$home" rev-parse --short HEAD 2>/dev/null || echo unknown)
  now=$(date +%s)
  last=$(cat "$stamp" 2>/dev/null || echo 0)
  age_h=$(( (now - last) / 3600 ))
  if [ "$age_h" -ge "$interval_h" ] && acquire_lock; then
    spawn_background_sync
    emit "BCQuality is PRESENT at ${home} (SHA ${sha}, one shared user-scope cache reused by every project). A background refresh just started (last synced ${age_h}h ago); this session still uses SHA ${sha} unaffected. Treat it as the citation source of truth for review/audit: read ${entry} and follow its entry then read then do dispatch; record the SHA in your report.${custom_note}"
  else
    emit "BCQuality is PRESENT at ${home} (SHA ${sha}, one shared user-scope cache reused by every project, last synced ${age_h}h ago). Treat it as the citation source of truth for review/audit: read ${entry} and follow its entry then read then do dispatch; record the SHA in your report.${custom_note}"
  fi
else
  if command -v git >/dev/null 2>&1 && acquire_lock; then
    spawn_background_sync
    emit "BCQuality is not installed yet. A one-time background install just started at ${home} - a shared, user-scope cache reused by every project on this machine, not a per-project clone. It will not be ready this session. Apply the BCQuality precondition: set bcquality.outcome to not-applicable, skip the BCQuality consultation, and review natively via the FULL A-G checklist (reactivate B Naming via al-naming-conventions, D Performance via al-performance plus skill-performance, E Error-handling via al-error-handling, and the commit-in-subscriber part of A via al-events; permissions via skill-permissions). Cap confidence at medium; secrets and security have no native check. NEVER block or fail the review for the missing layer. It should be ready on your next session."
  else
    emit "BCQuality is ABSENT (no ${entrypath}) and could not be auto-installed right now - git is missing, or an install/refresh from another session is already in flight. Apply the BCQuality precondition: set bcquality.outcome to not-applicable, skip the BCQuality consultation, and review natively via the FULL A-G checklist (reactivate B Naming via al-naming-conventions, D Performance via al-performance plus skill-performance, E Error-handling via al-error-handling, and the commit-in-subscriber part of A via al-events; permissions via skill-permissions). Cap confidence at medium; secrets and security have no native check. NEVER block or fail the review for the missing layer. This is the pre-BCQuality ALDC review, not a stub."
  fi
fi
