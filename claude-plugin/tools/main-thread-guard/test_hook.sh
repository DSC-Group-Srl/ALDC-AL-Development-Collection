#!/usr/bin/env bash
# Self-test for pretooluse_hook.sh (deny path + fast path guardrails).
set -u
H="$(cd "$(dirname "$0")" && pwd)/pretooluse_hook.sh"
export TMPDIR="$(mktemp -d)"
FAIL=0

# decision <expected ALLOW|DENY> <label> <session> <tool> <old> <new> [extra-json-field]
decision() {
  local want="$1" label="$2" sid="$3" tool="$4" old="$5" new="$6" extra="${7:-}" out got
  out="$(printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"/a/b.al","old_string":"%s","new_string":"%s"%s}}' \
    "$sid" "$tool" "$old" "$new" "$extra" | bash "$H")"
  if [ -n "$out" ]; then got=DENY; else got=ALLOW; fi
  if [ "$got" = "$want" ]; then echo "ok   $label"; else echo "FAIL $label (want $want, got $got)"; FAIL=1; fi
}

decision ALLOW "caption typo"        a Edit "    Caption = 'Custmer';" "    Caption = 'Customer';"
decision ALLOW "comment typo"        a Edit "// tpyo" "// typo"
decision ALLOW "label text"          a Edit "x: Label 'Hi %1', Locked = true;" "x: Label 'Hey %1', Locked = true;"
decision DENY  "4th edit (budget 3)" a Edit "// a" "// b"
decision DENY  "logic change"        b Edit "Rec.Delete();" "Rec.Modify();"
decision DENY  "code smuggled after comment" b Edit "// a" "// b\\nRec.Delete();"
decision DENY  "multi-line old"      b Edit "// a\\n// b" "// c"
decision DENY  "replace_all"         b Edit "// a" "// b" ',"replace_all":true'
decision DENY  "identifier rename"   b Edit "Caption = 'a'; x" "Caption = 'b';"
decision DENY  "Write tool"          b Write "// a" "// b"
decision DENY  "no session id"       "" Edit "// a" "// b"
decision DENY  "non-text property"   b Edit "Visible = true;" "Visible = false;"

out="$(printf '{"session_id":"c","agent_type":"bc-dev:al-developer","tool_name":"Write","tool_input":{"file_path":"/a/b.al"}}' | bash "$H")"
if [ -z "$out" ]; then echo "ok   subagent passes"; else echo "FAIL subagent passes"; FAIL=1; fi

rm -rf "$TMPDIR"
exit "$FAIL"
