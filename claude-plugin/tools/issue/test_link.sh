#!/usr/bin/env bash
# Self-test for tools/issue/link_hook.sh: a throwaway AL project on a feature branch, a spec
# with and without the BC Issue line. Nothing reaches telemetry or the user's real state.
# Exits non-zero on any failure. Skips (exit 0) when no python is on PATH.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/link_hook.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; FAIL=1; }
check() { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1 :: ${2:0:400}"; fi; }
empty() { if [ -z "$2" ]; then ok "$1"; else bad "$1 :: ${2:0:300}"; fi; }

PY=""
for c in python3 python py; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
[ -n "$PY" ] || { echo "skip: no python on PATH"; exit 0; }

export ALDC_METRICS_EXCLUDE=1 ALDC_METRICS_APPINSIGHTS_DISABLE=1
export ALDC_LIVE_DIR="$T/live" CLAUDE_PLUGIN_DATA="$T/data"
unset ALDC_ISSUE_LINK_DISABLE CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR
export GIT_CONFIG_GLOBAL="$T/gitconfig"

P="$T/proj"; mkdir -p "$P/app/requirements/in-progress/0042-ddt"
echo '{"id":"x","name":"Test App"}' > "$P/app/app.json"
git init -q -b feature/0042-ddt "$P"
SPEC="$P/app/requirements/in-progress/0042-ddt/0042-ddt.spec.md"
spec() { printf '# 0042-ddt\n\n**Version:** 1.0\n**Branch:** `feature/0042-ddt`\n%s\n\n---\n' "$1" > "$SPEC"; }
run() { ( cd "$P" && printf '{"session_id":"%s","cwd":"x","source":"startup"}' "$1" | bash "$HOOK" ); }
linked() { cat "$T/live/$1.issue" 2>/dev/null; }

spec '**BC Issue:** 4821 (IL-2026-118)'
o="$(run sess-link-0001)"
check "linked from the spec: the agent is told" "$o" 'linked to Business Central Issue 4821'
[ "$(linked sess-link-0001)" = "4821" ] && ok "linked from the spec: the session link is written" || bad "session link not written"
if printf '%s' "$o" | "$PY" -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok "valid JSON"; else bad "invalid JSON :: ${o:0:200}"; fi
n1="$(grep -c '"AldcIssue"' "$T/data/metrics/aldc-metrics.jsonl" 2>/dev/null || echo 0)"
run sess-link-0001 >/dev/null
n2="$(grep -c '"AldcIssue"' "$T/data/metrics/aldc-metrics.jsonl" 2>/dev/null || echo 0)"
[ "$n1" = "1" ] && [ "$n2" = "1" ] && ok "one AldcIssue event, not one per session start" || bad "AldcIssue events: $n1 then $n2"
if grep -q 'IL-2026-118\|0042-ddt.spec' "$T/data/metrics/aldc-metrics.jsonl"; then bad "text leaked into the record"; else ok "only the number is recorded"; fi

spec '**BC Issue:** none'
o="$(run sess-link-0002)"; empty "spec says none: silent" "$o"
[ -z "$(linked sess-link-0002)" ] && ok "spec says none: nothing linked" || bad "linked on none"

spec '**Complexity:** MEDIUM'
o="$(run sess-link-0003)"; check "spec without the line: asks to resolve" "$o" "has no '**BC Issue:**' line"

rm "$SPEC"
o="$(run sess-link-0004)"; check "feature branch without a spec: asks to resolve" "$o" 'has no requirement spec yet'
( cd "$P" && git checkout -q -b main 2>/dev/null )
o="$(run sess-link-0005)"; empty "main without a spec: silent" "$o"
( cd "$P" && git checkout -q feature/0042-ddt 2>/dev/null )

spec '**BC Issue:** 4821'
o="$(cd "$P" && printf '{"session_id":"sess-link-0006"}' | ALDC_ISSUE_LINK_DISABLE=1 bash "$HOOK")"; empty "kill switch" "$o"
o="$(cd "$T" && printf '{"session_id":"sess-link-0007"}' | bash "$HOOK")"; empty "not an AL workspace: silent" "$o"

exit $FAIL
