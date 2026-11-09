#!/usr/bin/env bash
#
# ALDC legacy flow (repo property branch-protection-enabled = false): push the current branch
# and make the other of main/test identical to it. Run only after the user said yes to the push.
#
#   bash sync_main_test.sh [--fix] [--dry-run]
#
# Run from main or test, with a clean working tree. Steps:
#   1. fetch origin
#   2. find what the current branch is missing: commits on origin/<itself>, on <other> or on
#      origin/<other>. Something missing and no --fix -> print ONE plain-language proposed fix
#      ("Proposed fix: ...") and stop with exit 3. The caller shows that sentence to the user
#      and, on yes, runs again with --fix.
#   3. --fix: merge the missing commits into the current branch (normal merge, no rewrite).
#      A conflict -> merge aborted, conflicting files listed, exit 6.
#   4. push the current branch, fast-forward the other to it, push the other
#   5. verify origin/main and origin/test point to the same commit
# Never force-pushes, never resets, never rewrites history.
# Exit: 0 aligned; 1 usage/environment problem; 3 out of sync, fix proposed; 4 a push failed;
#       5 not aligned afterwards; 6 the fix hit a merge conflict.
set -uo pipefail

DRY=0; FIX=0
for a in "$@"; do
  case "$a" in --dry-run) DRY=1 ;; --fix) FIX=1 ;; esac
done
run() { if [ "$DRY" -eq 1 ]; then echo "would run: $*"; else "$@"; fi; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository"; exit 1; }
git remote get-url origin >/dev/null 2>&1 || { echo "no origin remote"; exit 1; }

cur="$(git branch --show-current 2>/dev/null || true)"
case "$cur" in
  main) other=test ;;
  test) other=main ;;
  *) echo "stop: on '$cur' -- this flow commits on main (or test). Merge the branch into main first (ask), then run again."; exit 1 ;;
esac
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "stop: uncommitted changes -- commit them first."; exit 1
fi

git fetch origin >/dev/null 2>&1 || { echo "stop: git fetch origin failed"; exit 1; }

# Refs whose commits the current branch lacks, in the order they would be merged.
missing=()
total=0
for ref in "origin/$cur" "$other" "origin/$other"; do
  git rev-parse --verify --quiet "$ref" >/dev/null || continue
  n="$(git rev-list --count "$cur..$ref" 2>/dev/null || echo 0)"
  [ "$n" -gt 0 ] || continue
  # Skip a ref whose commits are all already covered by one listed before it.
  dup=0
  for m in "${missing[@]+"${missing[@]}"}"; do
    git merge-base --is-ancestor "$ref" "$m" 2>/dev/null && dup=1
  done
  [ "$dup" -eq 1 ] && continue
  missing+=("$ref"); total=$(( total + n ))
done

if [ "${#missing[@]}" -gt 0 ] && [ "$FIX" -eq 0 ]; then
  only_other=1
  for m in "${missing[@]}"; do [ "$m" = "origin/$cur" ] && only_other=0; done
  if [ "$only_other" -eq 1 ]; then
    echo "Proposed fix: $other has $total commit(s) that $cur doesn't; I'll merge them into $cur and push both branches so main and test are identical again."
  else
    echo "Proposed fix: $cur is missing $total commit(s) from the remote and/or $other; I'll merge them into $cur and push both branches so main and test are identical again."
  fi
  echo "commits:"
  for m in "${missing[@]}"; do git log --oneline "$cur..$m"; done | sort -u | head -10
  echo "(on yes: run again with --fix)"
  exit 3
fi

if [ "${#missing[@]}" -gt 0 ]; then
  for m in "${missing[@]}"; do
    if [ "$DRY" -eq 1 ]; then echo "would merge: $m into $cur"; continue; fi
    if ! git merge --no-edit -q "$m" >/dev/null 2>&1; then
      files="$(git diff --name-only --diff-filter=U | head -10 | tr '\n' ' ')"
      git merge --abort >/dev/null 2>&1
      echo "stop: merging $m into $cur conflicts in: $files-- nothing was changed. These files need a manual merge (offer to do it with the user)."
      exit 6
    fi
    echo "merged: $m into $cur"
  done
fi

run git push -q origin "$cur" || { echo "stop: push of $cur rejected"; exit 4; }
echo "pushed: $cur = $(git rev-parse --short "$cur")"

# Fast-forward the other branch to the current one without checking it out.
if git show-ref --verify --quiet "refs/heads/$other"; then
  run git branch -f "$other" "$cur" >/dev/null
fi
run git push -q origin "$cur:refs/heads/$other" || { echo "stop: push of $other rejected (not a fast-forward, or protected)"; exit 4; }
echo "pushed: $other = $(git rev-parse --short "$cur")"

[ "$DRY" -eq 1 ] && exit 0
git fetch origin >/dev/null 2>&1 || true
a="$(git rev-parse "origin/main" 2>/dev/null)"; b="$(git rev-parse "origin/test" 2>/dev/null)"
if [ -n "$a" ] && [ "$a" = "$b" ]; then
  echo "aligned: origin/main = origin/test = ${a:0:7}"; exit 0
fi
echo "not aligned: origin/main=${a:0:7} origin/test=${b:0:7}"; exit 5
