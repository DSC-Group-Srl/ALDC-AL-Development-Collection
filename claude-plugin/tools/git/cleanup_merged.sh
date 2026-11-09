#!/usr/bin/env bash
#
# ALDC post-merge cleanup: back to the trunk, up to date, merged branches gone.
#
#   bash cleanup_merged.sh [--dry-run]
#
# 1. fetch --prune origin, git worktree prune
# 2. pick the local branches whose work is already merged:
#      - an ancestor of origin/<trunk> (merge commit / fast-forward), or
#      - a merged PR (gh) whose head commit IS the local tip (squash and rebase merges)
#    A branch with local commits beyond its merged PR, with no PR, or checked out in another
#    worktree is kept and listed with the reason. main, master and test are never touched.
# 3. if the current branch is one of them: switch to the trunk (needs a clean working tree).
# 4. on the trunk: pull --ff-only.
# 5. delete the picked branches.
#
# Never deletes unmerged work, never force-pushes, never touches remote branches (GitHub deletes
# them on merge; fetch --prune drops the stale refs). Prints one line per action.
# Exit: 0 done, 1 not a git repo / dirty tree on a branch that must be left / pull failed.
set -uo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
run() { if [ "$DRY" -eq 1 ]; then echo "would run: $*"; else "$@"; fi; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository"; exit 1; }

trunk=main
git show-ref --verify --quiet refs/heads/main || { git show-ref --verify --quiet refs/heads/master && trunk=master; }

has_origin=0
git remote get-url origin >/dev/null 2>&1 && has_origin=1
if [ "$has_origin" -eq 1 ]; then
  git fetch --prune origin >/dev/null 2>&1 || echo "warning: git fetch --prune origin failed (offline?) -- using the refs already here"
fi
git worktree prune >/dev/null 2>&1 || true

base="refs/heads/$trunk"
[ "$has_origin" -eq 1 ] && git show-ref --verify --quiet "refs/remotes/origin/$trunk" && base="refs/remotes/origin/$trunk"

slug=""
url="$(git config --get remote.origin.url 2>/dev/null || true)"
case "$url" in *github.com[:/]*) slug="${url#*github.com[:/]}"; slug="${slug#/}"; slug="${slug%.git}" ;; esac
have_gh=0
[ -n "$slug" ] && command -v gh >/dev/null 2>&1 && have_gh=1
[ "${ALDC_GIT_NO_GH:-}" = "1" ] && have_gh=0

cur="$(git branch --show-current 2>/dev/null || true)"
# Branches checked out in OTHER worktrees (the current one is handled by switching away).
in_wt="$(git worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p')"

delete=()
kept=()
while IFS= read -r b; do
  [ -n "$b" ] || continue
  case "$b" in main|master|test) continue ;; esac
  if [ "$b" != "$cur" ] && printf '%s\n' "$in_wt" | grep -qxF "$b"; then
    kept+=("$b (checked out in another worktree)"); continue
  fi
  tip="$(git rev-parse "refs/heads/$b")"
  if git merge-base --is-ancestor "$tip" "$base" 2>/dev/null; then
    delete+=("$b"); continue
  fi
  if [ "$have_gh" -eq 1 ]; then
    head="$(gh pr list --repo "$slug" --head "$b" --state merged --json headRefOid --jq '.[0].headRefOid // empty' 2>/dev/null || true)"
    if [ -n "$head" ]; then
      if [ "$head" = "$tip" ]; then delete+=("$b"); else kept+=("$b (PR merged, but local commits after it)"); fi
      continue
    fi
  fi
  kept+=("$b (not merged)")
done < <(git for-each-ref --format='%(refname:short)' refs/heads)

cur_goes=0
for b in "${delete[@]+"${delete[@]}"}"; do [ "$b" = "$cur" ] && cur_goes=1; done

if [ "$cur_goes" -eq 1 ]; then
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "stop: $cur is merged but has uncommitted changes -- commit, stash or discard them first (user's call)."
    exit 1
  fi
  run git switch "$trunk" >/dev/null 2>&1 || { echo "stop: could not switch to $trunk"; exit 1; }
  echo "switched: $cur -> $trunk"
  cur="$trunk"
fi

if [ "$cur" = "$trunk" ] && [ "$has_origin" -eq 1 ]; then
  if [ "$DRY" -eq 1 ]; then echo "would pull: $trunk (ff-only)"
  elif git pull --ff-only --quiet origin "$trunk"; then
    echo "updated: $trunk = $(git rev-parse --short HEAD)"
  else
    echo "warning: git pull --ff-only failed on $trunk (local commits or offline) -- left as is"
  fi
fi

for b in "${delete[@]+"${delete[@]}"}"; do
  # -D: a squash/rebase-merged branch is never an ancestor; its merge was proven above.
  if [ "$DRY" -eq 1 ]; then echo "would delete: $b"; else git branch -D "$b" >/dev/null 2>&1 && echo "deleted: $b"; fi
done
for k in "${kept[@]+"${kept[@]}"}"; do echo "kept: $k"; done
[ "${#delete[@]}" -eq 0 ] && echo "nothing to delete"
exit 0
