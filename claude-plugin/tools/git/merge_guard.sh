#!/usr/bin/env bash
#
# ALDC merge guard — PreToolUse on Bash|PowerShell, routed by tools/hooks/pretooluse.sh.
#
# Why: a developer asked Claude to push and publish their own work on dscgroup-base; Claude
# also merged a colleague's open PR (#81) on the way, with the developer's account. Nobody had
# asked for that. This guard makes the user see it before it happens.
#
# It looks for three ways to merge a pull request:
#   gh pr merge [<number>|<url>|<branch>] [-R owner/repo] ...
#   gh api [-X PUT] repos/<owner>/<repo>/pulls/<n>/merge
#   git merge <ref> / git pull <remote> <branch>   where <branch> is the head of an OPEN PR
# For each it asks GitHub who opened the PR and who is logged in to gh. Different person ->
# "ask": the user gets a permission prompt that names the PR and its author, also in auto mode.
# Same person -> silent. GitHub cannot be read -> "ask" too, saying the owner is unknown.
#
# Kill switch: ALDC_MERGE_GUARD_DISABLE=1. Test hook: ALDC_MERGE_GUARD_ME overrides the gh login.
# Self-test: tools/git/test_git.sh.
set -uo pipefail

[ "${ALDC_MERGE_GUARD_DISABLE:-}" = "1" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"

# Fast path: nothing that can merge -> leave before any parsing.
printf '%s' "$INPUT" | grep -qE 'gh[^"]*pr[^"]*merge|pulls/[0-9]+/merge|git[^"]*(merge|pull)' || exit 0

ask() {
  local esc bs dq
  bs=$(printf '\134'); dq=$(printf '\042')
  esc="$1"
  esc="${esc//"$bs"/"$bs$bs"}"
  esc="${esc//"$dq"/"$bs$dq"}"
  esc="${esc//$'\r'/}"
  esc="${esc//$'\n'/ }"
  esc="${esc//$'\t'/ }"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$esc"
  exit 0
}

# The command string, JSON-unescaped (\" -> ", \\ -> \, \n -> newline).
cmd="$(printf '%s' "$INPUT" | tr '\n' ' ' \
  | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 \
  | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//' \
  | sed -E 's/\\n/ ; /g; s/\\t/ /g; s/\\"/"/g; s/\\\\/\\/g')"
[ -n "$cmd" ] || exit 0

cwd="$(printf '%s' "$INPUT" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 \
  | sed -E 's/^"cwd"[[:space:]]*:[[:space:]]*"//; s/"$//; s/\\\\/\//g')"
if [ -n "$cwd" ]; then
  # C:/x -> /c/x for Git Bash
  case "$cwd" in [A-Za-z]:/*) cwd="/$(printf '%s' "${cwd:0:1}" | tr '[:upper:]' '[:lower:]')${cwd:2}" ;; esac
  cd "$cwd" 2>/dev/null || true
fi

command -v gh >/dev/null 2>&1 || exit 0
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 8"

me="${ALDC_MERGE_GUARD_ME:-}"
[ -n "$me" ] || me="$($TO gh api user --jq .login 2>/dev/null | tr -d '\r')"

# check <selector> <repo-or-empty> <how>: look up the PR, ask if it is not the user's.
check() {
  local sel="$1" repo="$2" how="$3" info author num title
  local rargs=()
  [ -n "$repo" ] && rargs=(-R "$repo")
  info="$($TO gh pr view $sel "${rargs[@]}" --json number,title,author \
    --jq '"\(.number)\t\(.author.login)\t\(.title)"' 2>/dev/null | tr -d '\r' | head -1)"
  if [ -z "$info" ]; then
    ask "Merge check: could not read this pull request on GitHub, so it is not clear who opened it. ${how}. Merge only a PR you opened, or one its author asked you to merge."
  fi
  num="$(printf '%s' "$info" | cut -f1)"
  author="$(printf '%s' "$info" | cut -f2)"
  title="$(printf '%s' "$info" | cut -f3-)"
  if [ -z "$me" ]; then
    ask "Merge check: PR #${num} \"${title}\" was opened by ${author}. Could not read your GitHub login to compare. ${how}. Merge only if this PR is yours or ${author} asked you to."
  fi
  if [ "$(printf '%s' "$author" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$me" | tr '[:upper:]' '[:lower:]')" ]; then
    ask "STOP: this merges someone else's work. PR #${num} \"${title}\" was opened by ${author}, not by you (${me}). ${how}. Say yes only if ${author} asked you to merge it. Otherwise say no and merge only your own PR."
  fi
}

# Split into simple commands; strip quoted strings so a --subject "a b" cannot look like a
# selector.
printf '%s\n' "$cmd" | sed -E "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g" | sed -E 's/(\&\&|\|\||;|\|)/\n/g' \
  | while IFS= read -r seg; do
  # shellcheck disable=SC2206
  t=($seg)
  n=${#t[@]}
  i=0
  # find the program word
  while [ $i -lt $n ]; do
    case "${t[$i]}" in gh|gh.exe|*/gh|*/gh.exe|git|git.exe|*/git|*/git.exe) break ;; esac
    i=$((i+1))
  done
  [ $i -lt $n ] || continue
  prog="${t[$i]##*/}"; prog="${prog%.exe}"

  if [ "$prog" = "gh" ]; then
    repo=""; sub=(); j=$((i+1))
    while [ $j -lt $n ]; do
      a="${t[$j]}"
      case "$a" in
        -R|--repo) j=$((j+1)); repo="${t[$j]:-}" ;;
        --repo=*) repo="${a#--repo=}" ;;
        *) sub+=("$a") ;;
      esac
      j=$((j+1))
    done
    if [ "${sub[0]:-}" = "pr" ] && [ "${sub[1]:-}" = "merge" ]; then
      sel=""; k=2
      while [ $k -lt ${#sub[@]} ]; do
        a="${sub[$k]}"
        case "$a" in
          -t|--subject|-b|--body|-F|--body-file|-A|--author-email|--match-head-commit) k=$((k+1)) ;;
          -*) ;;
          *) [ -z "$sel" ] && sel="$a" ;;
        esac
        k=$((k+1))
      done
      [ "$sel" = "Q" ] && sel=""
      check "$sel" "$repo" "Command: gh pr merge${sel:+ $sel}" < /dev/null
    elif [ "${sub[0]:-}" = "api" ]; then
      for a in "${sub[@]}"; do
        if printf '%s' "$a" | grep -qE 'repos/[^/]+/[^/]+/pulls/[0-9]+/merge'; then
          r="$(printf '%s' "$a" | sed -E 's#.*repos/([^/]+/[^/]+)/pulls/([0-9]+)/merge.*#\1#')"
          p="$(printf '%s' "$a" | sed -E 's#.*repos/([^/]+/[^/]+)/pulls/([0-9]+)/merge.*#\2#')"
          case "$r" in *"{"*) r="" ;; esac
          check "$p" "$r" "Command: gh api .../pulls/${p}/merge" < /dev/null
        fi
      done
    fi
  else
    # git [-C dir] merge <ref>...   |   git pull <remote> <branch>
    j=$((i+1))
    while [ $j -lt $n ]; do
      case "${t[$j]}" in -C|-c) j=$((j+2)) ;; -*) j=$((j+1)) ;; *) break ;; esac
    done
    verb="${t[$j]:-}"
    [ "$verb" = "merge" ] || [ "$verb" = "pull" ] || continue
    args=(); k=$((j+1))
    while [ $k -lt $n ]; do
      case "${t[$k]}" in
        -m|-s|-X|--strategy|--strategy-option|-F|--file) k=$((k+1)) ;;
        -*) ;;
        *) args+=("${t[$k]}") ;;
      esac
      k=$((k+1))
    done
    if [ "$verb" = "pull" ]; then
      branch="${args[1]:-}"
    else
      branch="${args[0]:-}"
      # origin/feat/x -> feat/x ; a plain local name stays as is
      for rm in origin upstream $(git remote 2>/dev/null); do
        case "$branch" in "$rm"/*) branch="${branch#"$rm"/}" ;; esac
      done
    fi
    [ -n "$branch" ] && [ "$branch" != "Q" ] || continue
    case "$branch" in main|master|test|HEAD|FETCH_HEAD) continue ;; esac
    open="$($TO gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null | tr -d '\r')"
    [ -n "$open" ] || continue
    check "$open" "" "Command: git ${verb} ${branch} (the branch of open PR #${open}); merging it locally and pushing ships it without the PR" < /dev/null
  fi
done | head -1
exit 0
