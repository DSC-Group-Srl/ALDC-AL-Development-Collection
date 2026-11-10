#!/usr/bin/env bash
#
# Prints the developer's COMPANY e-mail on one line, for skill-bc-issue: it is how the agent
# finds the developer's employee record in DSC's Business Central (List_Employees ->
# companyEMail) and from there the Issues assigned to them.
#
# Order: the GitHub account `gh` is signed in with (public e-mail, then the verified addresses
# when the token has the user:email scope — most tokens do not, and GitHub hides the address
# by default), then `git config user.email`, then the Claude account. The first address on the
# company domain wins. Prints nothing when none is found; never fails.
#
# The address stays on this machine and in the conversation: it is only ever used as a filter
# on DSC's own Business Central. ALDC_COMPANY_EMAIL_DOMAIN overrides the domain (dsc-group.net).
set -uo pipefail
domain="${ALDC_COMPANY_EMAIL_DOMAIN:-dsc-group.net}"

pick() {
  local e
  while IFS= read -r e; do
    e="$(printf '%s' "$e" | tr -d '\r" ' | tr '[:upper:]' '[:lower:]')"
    case "$e" in
      *[!a-z0-9._+@-]*|"") continue ;;
      *@"$domain") printf '%s\n' "$e"; return 0 ;;
    esac
  done
  return 1
}

if command -v gh >/dev/null 2>&1; then
  gh api user --jq '.email // empty' 2>/dev/null | pick && exit 0
  gh api user/emails --jq '.[] | select(.verified) | .email' 2>/dev/null | pick && exit 0
fi
git config user.email 2>/dev/null | pick && exit 0
f="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
[ -f "$f" ] || f="$HOME/.claude.json"
if [ -f "$f" ]; then
  grep -oE '"emailAddress"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null \
    | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/' | pick && exit 0
fi
exit 0
