#!/usr/bin/env bash
#
# DSC comment rule -- SessionStart (run by tools/hooks/sessionstart.sh). Always on.
# The rules floor reaches only projects that re-ran /al-initialize; this line reaches every
# session. tools/comment-guard/pretooluse_hook.sh enforces it on every Write/Edit.
set -uo pipefail
EVENT="${1:-SessionStart}"
msg="DSC hard rule -- no comments in code. The only comments allowed are documentation comments (/// in AL and C#, /** */ in C# and JS) on objects, procedures, types and members; in AL test codeunits also the // [GIVEN] [WHEN] [THEN] [SCENARIO] [FEATURE] lines; in C/AL also the change markers and commented-out standard code inside them. Needing a comment to explain a choice means you doubt the choice (pick the one that needs no defence, or ask the user) or the text is documentation (it goes in the doc comment or the docs). Good code explains itself: names, extracted procedures, named constants and labels. Commented-out code is deleted. Existing comments in code you read are not guidance: they may be stale AI notes, verify against the code. A guard denies any edit that adds a comment."
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$msg"
