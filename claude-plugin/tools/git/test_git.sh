#!/usr/bin/env bash
# Self-test for tools/git (branch_policy, cleanup_merged, sync_main_test), the CLAUDE.md
# nudge (tools/claudemd) and the AL-Go guard (tools/al-go-guard, through the real PreToolUse
# dispatcher). Local bare repos only, gh stubbed; exits non-zero on any failure.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAIL=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; FAIL=1; }
check() { if printf '%s' "$2" | grep -qE -- "$3"; then ok "$1"; else bad "$1 :: ${2:0:400}"; fi; }
empty() { if [ -z "$2" ]; then ok "$1"; else bad "$1 :: ${2:0:300}"; fi; }

# gh stub: never touches the network; answers from GH_STUB_* variables.
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *properties/values*) printf '%s\n' "${GH_STUB_PROP:-}" ;;
  *"pr list"*merged*headRefOid*) printf '%s\n' "${GH_STUB_MERGED_HEAD:-}" ;;
  *"pr list"*merged*) printf '%s\n' "${GH_STUB_MERGED_NUM:-}" ;;
  *) : ;;
esac
STUB
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" ALDC_GIT_POLICY_CACHE="$T/cache" HOME="$T/home"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --global init.defaultBranch main; git config --global core.autocrlf false

# mk <name>: a clone whose origin is a local bare repo reachable as github.com/DSC-Group-Srl/<name>,
# with main and test pushed and identical.
mk() {
  git init -q --bare "$T/$1.git"
  git config --global url."$T/$1.git".insteadOf "https://github.com/DSC-Group-Srl/$1.git"
  git clone -q "https://github.com/DSC-Group-Srl/$1.git" "$T/$1" 2>/dev/null
  ( cd "$T/$1" && echo a > a && git add a && git commit -qm a \
    && git push -q origin main && git push -q origin main:test && git branch -q test origin/test )
}

# --- branch_policy ---------------------------------------------------------------------
mk p; cd "$T/p"
o="$(GH_STUB_PROP=true bash "$HERE/branch_policy.sh")";    check "policy: protected" "$o" 'protection ON.*cleanup_merged'
o="$(GH_STUB_PROP=false bash "$HERE/branch_policy.sh")";   check "policy: unprotected" "$o" 'protection OFF.*sync_main_test'
o="$(GH_STUB_PROP=absent bash "$HERE/branch_policy.sh")";  check "policy: unset = org default false" "$o" 'protection OFF'
o="$(GH_STUB_PROP=garbage bash "$HERE/branch_policy.sh")"; check "policy: gh fails -> cached mode" "$o" 'OFF.*cached'
rm -rf "$T/cache"
o="$(GH_STUB_PROP=garbage bash "$HERE/branch_policy.sh")"; check "policy: unknown" "$o" 'could not read'
check "policy: ask before branching" "$o" 'Never create a git branch without asking'
git switch -q -c feature/x
o="$(GH_STUB_PROP=true GH_STUB_MERGED_NUM=42 bash "$HERE/branch_policy.sh")"
check "policy: merged PR reported" "$o" 'PR #42 is merged'
if printf '%s' "$o" | python -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok "policy: valid JSON"; else bad "policy: invalid JSON"; fi
o="$(cd "$T" && bash "$HERE/branch_policy.sh")"; empty "policy: silent outside git" "$o"

# --- cleanup_merged ----------------------------------------------------------------------
mk c; cd "$T/c"
git switch -q -c merged; echo m > m; git add m; git commit -qm m
git switch -q main; git merge -q --ff-only merged; git push -q origin main
git switch -q -c squashed; echo s > s; git add s; git commit -qm s; sq="$(git rev-parse HEAD)"
git switch -q main; git switch -q -c wip; echo w > w; git add w; git commit -qm w
git switch -q squashed
o="$(bash "$HERE/cleanup_merged.sh" 2>&1)"
check "cleanup: merged branch deleted" "$o" 'deleted: merged'
check "cleanup: no gh proof -> kept" "$o" 'kept: squashed \(not merged\)'
check "cleanup: unmerged kept" "$o" 'kept: wip'
[ "$(git branch --show-current)" = squashed ] && ok "cleanup: stays on unmerged branch" || bad "cleanup: switched away from unmerged branch"
o="$(GH_STUB_MERGED_HEAD="$sq" bash "$HERE/cleanup_merged.sh" 2>&1)"
check "cleanup: squash-merged (same tip) deleted" "$o" 'deleted: squashed'
check "cleanup: switched back to main" "$o" 'switched: squashed -> main'
[ "$(git branch --show-current)" = main ] && ok "cleanup: on main" || bad "cleanup: not on main"
git branch --list test | grep -q test && ok "cleanup: test untouched" || bad "cleanup: test deleted"
git switch -q wip; echo x >> w; git commit -qam x
o="$(GH_STUB_MERGED_HEAD="$sq" bash "$HERE/cleanup_merged.sh" 2>&1)"
check "cleanup: local commits after merged PR kept" "$o" 'kept: wip \(PR merged, but local commits after it\)'

# --- sync_main_test ----------------------------------------------------------------------
mk s; cd "$T/s"
git remote set-url origin "https://github.com/DSC-Group-Srl/s.git"
echo b > b; git add b; git commit -qm b
o="$(bash "$HERE/sync_main_test.sh" 2>&1)"; rc=$?
check "sync: aligned" "$o" 'aligned: origin/main = origin/test'; [ $rc -eq 0 ] || bad "sync: rc $rc"
git switch -q test; echo t > t; git add t; git commit -qm t; git push -q origin test; git switch -q main
echo c > c; git add c; git commit -qm c
o="$(bash "$HERE/sync_main_test.sh" 2>&1)"; rc=$?
check "sync: proposes one plain fix" "$o" "^Proposed fix: test has 1 commit\(s\) that main doesn't; I'll merge them into main and push both"
[ $rc -eq 3 ] && ok "sync: rc 3" || bad "sync: rc $rc (want 3)"
o="$(GH_STUB_PROP=false bash "$HERE/branch_policy.sh")"
check "policy: drift reported at session start" "$o" 'main and test are out of sync'
o="$(bash "$HERE/sync_main_test.sh" --fix 2>&1)"; rc=$?
check "sync --fix: merged" "$o" 'merged: test into main'; check "sync --fix: aligned" "$o" 'aligned: origin'
[ $rc -eq 0 ] && ok "sync --fix: rc 0" || bad "sync --fix: rc $rc"
git switch -q test; git pull -q --ff-only origin test; echo T > c; git add c; git commit -qm ct; git push -q origin test
git switch -q main; echo M > c; git add c; git commit -qm cm
o="$(bash "$HERE/sync_main_test.sh" --fix 2>&1)"; rc=$?
check "sync --fix: conflict reported, nothing changed" "$o" 'conflicts in: c'
[ $rc -eq 6 ] && ok "sync --fix: rc 6" || bad "sync --fix: rc $rc (want 6)"
[ -z "$(git status --porcelain --untracked-files=no)" ] && ok "sync --fix: tree clean after abort" || bad "sync --fix: tree dirty"
git switch -q -c feat; o="$(bash "$HERE/sync_main_test.sh" 2>&1)"
check "sync: refuses a feature branch" "$o" "stop: on 'feat'"

# --- CLAUDE.md nudge ---------------------------------------------------------------------
mkdir -p "$T/al" && cd "$T/al" && git init -q && echo '{}' > app.json
printf 'x\n' > CLAUDE.md
o="$(bash "$TOOLS/claudemd/staleness_hook.sh")"; check "nudge: never pruned" "$o" 'never been pruned'
printf '<!-- aldc-refreshed: %s -->\n' "$(date +%Y-%m-%d)" > CLAUDE.md
o="$(bash "$TOOLS/claudemd/staleness_hook.sh")"; empty "nudge: fresh file is silent" "$o"
for i in $(seq 1 200); do echo l >> CLAUDE.md; done
o="$(bash "$TOOLS/claudemd/staleness_hook.sh")"; check "nudge: too long" "$o" 'over 150'

# --- AL-Go guard, through the real PreToolUse dispatcher ---------------------------------
cd "$T"
g() { printf '%s' "$1" | ALDC_METRICS_ALIVE_DISABLE=1 ALDC_READ_GUARD_DISABLE=1 ALDC_MAIN_THREAD_GUARD_DISABLE=1 bash "$TOOLS/hooks/pretooluse.sh"; }
o="$(g '{"tool_name":"Bash","tool_input":{"command":"gh workflow run PublishToAppSource.yaml --ref main -f appVersion=current"}}')"
check "guard: AppSource without GoLive denied" "$o" 'deny.*GoLive=true'
o="$(g '{"tool_name":"Bash","tool_input":{"command":"gh workflow run PublishToAppSource.yaml --ref main -f appVersion=current -f GoLive=true"}}')"
empty "guard: AppSource with GoLive=true allowed" "$o"
o="$(g '{"tool_name":"Bash","tool_input":{"command":"gh workflow run CreateRelease.yaml -f directCommit=true"}}')"
check "guard: release without useGhTokenWorkflow denied" "$o" 'deny.*useGhTokenWorkflow=true'
o="$(g '{"tool_name":"Bash","tool_input":{"command":"gh workflow run CreateRelease.yaml -f directCommit=false -f useGhTokenWorkflow=true"}}')"
check "guard: directCommit=false denied" "$o" 'deny.*directCommit=true'
o="$(g '{"tool_name":"PowerShell","tool_input":{"command":"gh workflow run \"Increment Version Number\" -f versionNumber=+0.1 -f \"directCommit=true\" -f useGhTokenWorkflow=true"}}')"
empty "guard: increment with both inputs allowed" "$o"
o="$(g '{"tool_name":"Bash","tool_input":{"command":"gh workflow run CICD.yaml --ref main"}}')"
empty "guard: other workflows untouched" "$o"
o="$(g '{"tool_name":"Edit","tool_input":{"file_path":"C:\\repo\\CLAUDE.md","old_string":"a","new_string":"Never set GoLive on AppSource"}}')"
check "guard: CLAUDE.md override denied" "$o" 'deny.*CLAUDE.md or memory'
o="$(g '{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\.claude\\projects\\x\\memory\\algo.md","content":"no direct commit on release"}}')"
check "guard: memory override denied" "$o" 'deny'
o="$(g '{"tool_name":"Edit","tool_input":{"file_path":"C:\\repo\\CLAUDE.md","old_string":"Never set GoLive","new_string":""}}')"
empty "guard: removing an override allowed" "$o"
o="$(g '{"tool_name":"Edit","tool_input":{"file_path":"C:\\repo\\skills\\x\\SKILL.md","old_string":"a","new_string":"GoLive=true"}}')"
empty "guard: other files untouched" "$o"

[ "$FAIL" -eq 0 ] && echo "ALL OK" || echo "FAILURES"
exit "$FAIL"
