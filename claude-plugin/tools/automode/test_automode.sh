#!/usr/bin/env bash
# Self-test for apply_automode.js / automode_hook.sh. Never touches the real ~/.claude/settings.json.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
q() { node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(JSON.stringify(eval(process.argv[2])))" "$1" "$2"; }
n_ours=$(node -e "const r=require(process.argv[1]);console.log(r.environment.length+' '+r.allow.length)" "$HERE/dsc-automode.json")
n_env=${n_ours% *}; n_allow=${n_ours#* }

# 1. no settings file -> created with $defaults first
r=$(node "$HERE/apply_automode.js" "$T/a.json"); check "new file created" '[[ $r == updated* ]]'
check "allow starts with \$defaults" '[ "$(q "$T/a.json" "j.autoMode.allow[0]")" = "\"\$defaults\"" ]'
check "allow count" '[ "$(q "$T/a.json" "j.autoMode.allow.length")" = "$((n_allow+1))" ]'

# 2. idempotent
r=$(node "$HERE/apply_automode.js" "$T/a.json"); check "second run unchanged" '[ "$r" = unchanged ]'

# 3. user entries and other keys kept, stale [bc-dev] entries replaced, no $defaults added to a user list
cat > "$T/b.json" <<'EOF'
{ "theme": "dark", "permissions": { "allow": ["Bash(ls)"] },
  "autoMode": { "environment": ["user env line", "[bc-dev] old stale line"], "soft_deny": ["$defaults", "user deny"] } }
EOF
r=$(node "$HERE/apply_automode.js" "$T/b.json"); check "existing file updated" '[[ $r == updated* ]]'
check "backup written" '[ -f "$T/b.json.bc-dev-backup" ]'
check "theme kept" '[ "$(q "$T/b.json" "j.theme")" = "\"dark\"" ]'
check "user env kept first" '[ "$(q "$T/b.json" "j.autoMode.environment[0]")" = "\"user env line\"" ]'
check "stale entry gone" '! grep -q "old stale line" "$T/b.json"'
check "env count" '[ "$(q "$T/b.json" "j.autoMode.environment.length")" = "$((n_env+1))" ]'
check "soft_deny untouched" '[ "$(q "$T/b.json" "j.autoMode.soft_deny")" = "[\"\$defaults\",\"user deny\"]" ]'

# 4. invalid JSON left untouched
printf '{ broken' > "$T/c.json"
r=$(node "$HERE/apply_automode.js" "$T/c.json"); check "invalid json -> error" '[[ $r == error* ]]'
check "invalid json untouched" '[ "$(cat "$T/c.json")" = "{ broken" ]'

# 5. hook: emits on change, silent when unchanged, silent when opted out
out=$(ALDC_AUTOMODE_SETTINGS="$T/d.json" bash "$HERE/automode_hook.sh" SessionStart); check "hook emits on change" '[[ $out == *additionalContext* ]]'
out=$(ALDC_AUTOMODE_SETTINGS="$T/d.json" bash "$HERE/automode_hook.sh" SessionStart); check "hook silent when unchanged" '[ -z "$out" ]'
out=$(ALDC_AUTOMODE_RULES=off ALDC_AUTOMODE_SETTINGS="$T/e.json" bash "$HERE/automode_hook.sh"); check "opt-out silent, no file" '[ -z "$out" ] && [ ! -f "$T/e.json" ]'

[ $fail -eq 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
