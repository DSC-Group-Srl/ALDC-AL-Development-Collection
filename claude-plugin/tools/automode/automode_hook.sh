#!/usr/bin/env bash
#
# ALDC auto-mode rules — SessionStart hook (run by tools/hooks/sessionstart.sh).
#
# Auto mode's classifier blocked routine bc-dev work as "undermining oversight" (dry runs, release
# asset uploads, Docker, reading the session's own tool-results) because it did not know DSC's
# environment. Claude Code reads `autoMode` only from ~/.claude/settings.json, managed settings and
# --settings — not from a repo's or a plugin's settings.json — so this hook merges the DSC rules
# (dsc-automode.json) into the user's settings at every session start. Only entries tagged
# [bc-dev] are replaced; the user's own entries and "$defaults" choices are left alone.
# The rules take effect from the next session when they change (settings are read at start).
#
# Opt out: ALDC_AUTOMODE_RULES=off. Test override: ALDC_AUTOMODE_SETTINGS=<path to settings.json>.
# Same output contract as the other SessionStart scripts: additionalContext only when it changed
# something or failed, never blocking, always exit 0.
set -uo pipefail

EVENT="${1:-SessionStart}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

emit() {
  local esc bs dq
  bs=$(printf '\134'); dq=$(printf '\042')
  esc="$1"
  esc="${esc//"$bs"/"$bs$bs"}"
  esc="${esc//"$dq"/"$bs$dq"}"
  esc="${esc//$'\r'/}"
  esc="${esc//$'\n'/${bs}n}"
  esc="${esc//$'\t'/${bs}t}"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$esc"
}

[ "${ALDC_AUTOMODE_RULES:-on}" = "off" ] && exit 0
command -v node >/dev/null 2>&1 || exit 0   # ensure-npx installs node; the next session applies

args=()
[ -n "${ALDC_AUTOMODE_SETTINGS:-}" ] && args+=("$ALDC_AUTOMODE_SETTINGS")
result="$(node "$HERE/apply_automode.js" "${args[@]}" 2>&1 | tail -n 1)"

case "$result" in
  unchanged) ;;
  updated*)
    emit "bc-dev updated the DSC auto-mode rules ([bc-dev] entries under autoMode) in ~/.claude/settings.json; previous file saved as ${result#updated }. They apply from the next session. Tell the user in one line." ;;
  *)
    emit "bc-dev could not apply the DSC auto-mode rules to ~/.claude/settings.json: ${result#error }. Tell the user in one line." ;;
esac
exit 0
