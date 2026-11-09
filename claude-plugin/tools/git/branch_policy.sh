#!/usr/bin/env bash
#
# ALDC git branch policy — SessionStart hook (run by tools/hooks/sessionstart.sh).
#
# Two complaints this answers:
#  1. Claude cut a new branch for every small change "to keep things separated". Branch
#     creation is now a question to the user, follow-ups stay on the branch already checked
#     out, and once a PR is merged Claude goes back to main and deletes the merged branches
#     (tools/git/cleanup_merged.sh).
#  2. Repos still on the legacy flow have no branch protection. The org custom property
#     `branch-protection-enabled` (true_false, default false) on DSC-Group-Srl says which flow a
#     repo uses: true -> trunk-based (branch from main, PR into main); false -> no PRs, commit on
#     main and keep main and test identical on every push (tools/git/sync_main_test.sh).
#
# Same output contract as tools/routing/precondition_hook.sh: additionalContext via
# hookSpecificOutput, never blocking, silent outside a git repo.
#
# The property is read with `gh api repos/{o}/{r}/properties/values` and cached per repo in
# ~/.claude/aldc-cache/branch-protection/ so an offline session still knows the mode.
# Test overrides: ALDC_GIT_POLICY_MODE=protected|unprotected|unknown skips the lookup;
# ALDC_GIT_POLICY_CACHE replaces the cache directory.
set -uo pipefail

EVENT="${1:-SessionStart}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

emit() {
  # JSON-escape: see tools/routing/precondition_hook.sh emit() for why the literals are octal.
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

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# owner/repo from origin (https or ssh GitHub URL); empty when not GitHub.
url="$(git config --get remote.origin.url 2>/dev/null || true)"
slug=""
case "$url" in
  *github.com[:/]*)
    slug="${url#*github.com[:/]}"; slug="${slug#/}"; slug="${slug%.git}"; slug="${slug%/}" ;;
esac

have_gh=0
command -v gh >/dev/null 2>&1 && have_gh=1

cache_dir="${ALDC_GIT_POLICY_CACHE:-$HOME/.claude/aldc-cache/branch-protection}"
cache_file=""
[ -n "$slug" ] && cache_file="$cache_dir/${slug//\//__}"

mode="${ALDC_GIT_POLICY_MODE:-}"
source_note=""
if [ -z "$mode" ]; then
  mode="unknown"
  if [ -n "$slug" ] && [ "$have_gh" -eq 1 ]; then
    v="$(gh api "repos/$slug/properties/values" \
          --jq '[.[] | select(.property_name=="branch-protection-enabled") | .value][0] // "absent"' \
          2>/dev/null || true)"
    case "$v" in
      true)   mode="protected" ;;
      false)  mode="unprotected" ;;
      # Property not set on the repo: the org default is false.
      absent) case "$slug" in DSC-Group-Srl/*) mode="unprotected" ;; esac ;;
    esac
    if [ "$mode" != "unknown" ]; then
      mkdir -p "$cache_dir" 2>/dev/null && printf '%s\n' "$mode" > "$cache_file" 2>/dev/null
    fi
  fi
  if [ "$mode" = "unknown" ] && [ -n "$cache_file" ] && [ -f "$cache_file" ]; then
    mode="$(head -n1 "$cache_file" 2>/dev/null)"
    case "$mode" in protected|unprotected) source_note=" (cached; gh lookup failed this session)" ;; *) mode="unknown" ;; esac
  fi
fi

repo_label="${slug:-this repo}"
cur="$(git branch --show-current 2>/dev/null || true)"
trunk="main"
git show-ref --verify --quiet refs/heads/main || { git show-ref --verify --quiet refs/heads/master && trunk="master"; }

cleanup="bash \"$HERE/cleanup_merged.sh\""
sync="bash \"$HERE/sync_main_test.sh\""

common="Never create a git branch without asking first. Before any git switch -c / checkout -b / new branch for the user's work, ask once with AskUserQuestion: the proposed name and why, with 'stay on the current branch' as an option. Follow-up fixes, small changes and review rework go on the branch already checked out (for an open PR that simply updates it) -- never a new branch per small thing, never 'to keep things separated'. Delegation briefs say 'commit on the current branch, do not create branches'. (al-conductor's own per-work-package worktree branches are internal and it deletes them; they need no question.)"

case "$mode" in
  protected)
    policy="ALDC git -- $repo_label has branch protection ON (trunk-based)$source_note. $common New branches are cut from an up-to-date $trunk and PR into $trunk, never test. After a PR is merged (the user says so, gh shows it, or this message reports it below): with the Bash tool run $cleanup -- it switches back to $trunk, pulls, prunes, and deletes only local branches whose work is already merged (merged into $trunk, or merged PR with the same tip); tell the user in one line what it deleted and what it kept. It needs no confirmation: it never deletes unmerged work." ;;
  unprotected)
    policy="ALDC git -- $repo_label has branch protection OFF (legacy flow, no pull requests)$source_note. Work on $trunk directly; do not create feature branches or open PRs unless the user asks for one. $common main and test must stay identical: after committing, ask once 'push to main and test?'; on yes, with the Bash tool run $sync -- it pushes the current branch and fast-forwards the other to it, then checks both remotes match. When main and test are out of sync (the script stops with 'Proposed fix: ...', or this message says so below), always offer to fix it: give the user that one plain sentence, nothing more (no options list, no git jargon), ask yes/no, and on yes run the script again with --fix. A conflict it reports -> offer to resolve those files together. Never force-push, never reset, never leave main pushed without test (or the reverse). /bc-dev:al-pr-prepare and the 'open the PR?' step do not apply here. If the user is mid-way through a branch, finish it by merging into $trunk (ask), then sync, then run $cleanup." ;;
  *)
    policy="ALDC git -- could not read the branch-protection-enabled property of $repo_label (gh missing, offline, or not a DSC-Group-Srl GitHub repo). $common Before the first PR or push decision, find out which flow the repo uses: gh api repos/<owner>/<repo>/properties/values (branch-protection-enabled true = branch from main and PR into main; false = no PRs, push to main and keep test identical with $sync), or ask the user. After a PR is merged, run $cleanup with the Bash tool." ;;
esac

# Current state the main thread should act on.
state=""
if [ -n "$cur" ] && [ "$cur" != "$trunk" ] && [ "$cur" != "test" ] && [ "$have_gh" -eq 1 ] && [ -n "$slug" ] && [ -z "${ALDC_GIT_POLICY_MODE:-}" ]; then
  n="$(gh pr list --repo "$slug" --head "$cur" --state merged --json number --jq '.[0].number // empty' 2>/dev/null || true)"
  if [ -n "$n" ]; then
    open="$(gh pr list --repo "$slug" --head "$cur" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)"
    if [ -z "$open" ]; then
      state="Current branch $cur: its PR #$n is merged. Tell the user at the start of your first reply and run the cleanup unless they are about to keep working on it."
    fi
  fi
fi
# Legacy flow: main and test should be identical. Uses the refs from the last fetch (no
# network here); the sync script re-checks after a fetch.
if [ "$mode" = "unprotected" ] && git rev-parse --verify --quiet origin/main >/dev/null    && git rev-parse --verify --quiet origin/test >/dev/null; then
  m_only="$(git rev-list --count origin/test..origin/main 2>/dev/null || echo 0)"
  t_only="$(git rev-list --count origin/main..origin/test 2>/dev/null || echo 0)"
  if [ "$m_only" -gt 0 ] || [ "$t_only" -gt 0 ]; then
    state="${state:+$state }main and test are out of sync (main has $m_only commit(s) test lacks, test has $t_only main lacks, as of the last fetch). At the start of your first reply offer to fix it in one plain sentence (e.g. 'main and test have drifted apart: I'll merge test's 2 commits into main and push both so they match. Go ahead?'); on yes run $sync --fix from main."
  fi
fi
gone="$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads 2>/dev/null | grep -c '\[gone\]' || true)"
if [ "${gone:-0}" -gt 0 ]; then
  state="${state:+$state }$gone local branch(es) track a remote branch that no longer exists (usually a merged PR): offer the cleanup."
fi

emit "$policy${state:+ $state}"
