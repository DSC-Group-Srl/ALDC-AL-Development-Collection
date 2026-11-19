#!/usr/bin/env bash
#
# ALDC voice — SessionStart hook (run by tools/hooks/sessionstart.sh). Always on.
#
# Why: developers asked for answers they can act on fast. Agent files carry the same rule
# ("How you talk to the user"); this line covers the main session, which has no agent file.
# Same output contract as tools/git/branch_policy.sh: additionalContext, never blocking.
# Kill switch: ALDC_VOICE_DISABLE=1.
set -uo pipefail
[ "${ALDC_VOICE_DISABLE:-}" = "1" ] && exit 0
EVENT="${1:-SessionStart}"
msg="ALDC voice -- how to talk to the user: simple words, short sentences, straight to the point. Result or answer first, then the one next step. No long prose, no recaps, no filler, no jargon the user did not use. Lists over paragraphs. Ask one question at a time. Reports to other agents keep their exact formats and marker lines."
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$msg"
