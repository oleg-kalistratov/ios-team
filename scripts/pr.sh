#!/bin/bash
# pr.sh check  <worktree> --base <base> [--ticketless-ok]                      pre-push checks only
# pr.sh push   <worktree> --base <base> [--ticketless-ok]                      checks, then `git push -u origin <branch>`
# pr.sh create <worktree> --base <base> --title <t> --body-file <f> [--ticketless-ok]   checks, push and `gh pr create` in one go
# pr.sh status <pr number | branch>                                            CI checks and review decision, once
# The publisher agent's GitHub recipe (0.1–0.3) as one script the coordinator runs itself; the PR body is still written by the
# coordinator with the pr-description-ru skill (Russian prose is model work, the checks are not). Values from
# ~/.claude/ios-team/project.md: github_repo, commit_pattern. Never merges, labels, force-pushes, rebases, renames or deletes.
# Exit 0 ok; 1 a check failed (what and which commits, on stderr); 3 a decision for Oleg («decision: … / options: …»); 64 usage.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/project.sh"
usage() { sed -n 2,5p "$0" >&2; exit 64; }
fail() { echo "pr: $*" >&2; exit 1; }
decide() { printf 'decision: %s\noptions: %s\n' "$1" "$2"; exit 3; }
gh_repo=$(proj github_repo); pattern=$(proj commit_pattern '^[A-Z][A-Z0-9]+-[0-9]+: .+|^Tech: .+')
op=${1:-}; shift 2>/dev/null
if [ "$op" = status ]; then
  [ -n "$gh_repo" ] || fail "github_repo не задан в project.md"
  gh pr checks "${1:?pr or branch}" --repo "$gh_repo" 2>&1 | head -40
  gh pr view "${1}" --repo "$gh_repo" --json number,url,state,reviewDecision,isDraft 2>/dev/null
  exit 0
fi
wt=${1:-}; shift 2>/dev/null || usage; base=""; title=""; body=""; ticketless=0
while [ $# -gt 0 ]; do case $1 in
  --base) base=${2:?}; shift 2 ;; --title) title=${2:?}; shift 2 ;; --body-file) body=${2:?}; shift 2 ;; --ticketless-ok) ticketless=1; shift ;; *) usage ;;
esac; done
case $op in check|push|create) ;; *) usage ;; esac
[ -d "$wt" ] || fail "нет папки $wt"
[ -n "$base" ] || usage
[ "$base" != main ] && [ "$base" != master ] || fail "база $base: PR идут в develop или release/*, не в $base"
[ -n "$gh_repo" ] || fail "github_repo не задан в ~/.claude/ios-team/project.md"
branch=$(git -C "$wt" branch --show-current); [ -n "$branch" ] || fail "в $wt нет ветки (detached HEAD)"
git -C "$wt" remote get-url origin >/dev/null 2>&1 || fail "у $wt нет origin"
prs=$(gh pr list --repo "$gh_repo" --head "$branch" --state all --json number,state,url 2>/dev/null || echo "[]")
open_url=$(python3 -c 'import json,sys; print(next((p["url"] for p in json.load(sys.stdin) if p.get("state") == "OPEN"), ""))' <<<"$prs" 2>/dev/null)
if [ -z "$open_url" ] && grep -Eq '"state": *"(MERGED|CLOSED)"' <<<"$prs"; then fail "по ветке $branch PR уже MERGED/CLOSED — push пересоздал бы смёрженную ветку; новая работа идёт в новую ветку"; fi
if git -C "$wt" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  git -C "$wt" fetch -q origin "$branch" && range="origin/$branch..HEAD"
else
  git -C "$wt" fetch -q origin "$base" 2>/dev/null || fail "на origin нет ветки $base"
  range="origin/$base..HEAD"
fi
bad=""
# One NUL-terminated record per commit, fields split by \x1f: a body may hold newlines and tabs, so line-based parsing is out.
split_rec() { h=${1%%$'\x1f'*}; rest=${1#*$'\x1f'}; s=${rest%%$'\x1f'*}; b=${rest#*$'\x1f'}; }
while IFS= read -r -d '' rec; do
  split_rec "$rec"; [ -n "$h" ] || continue
  # «${s}» with braces: bash 3.2 in a UTF-8 locale expands «$s» to nothing when a multibyte char follows the name
  printf '%s' "$s" | grep -Eq "$pattern" || bad+="$h «${s}»: не подходит под commit_pattern «${pattern}»"$'\n'
  [ -z "$(printf '%s' "$b" | tr -d '[:space:]')" ] || bad+="$h «${s}»: у коммита есть тело (должна быть одна строка)"$'\n'
  printf '%s %s' "$s" "$b" | grep -Eqi 'co-authored-by|signed-off-by|generated with' && bad+="$h «${s}»: трейлер в сообщении"$'\n'
  printf '%s' "$s" | grep -Eq '^Tech: Release' && bad+="$h «${s}»: «Tech: Release …» ставит защищённый тег"$'\n'
done < <(git -C "$wt" log --first-parent --no-merges --format='%h%x1f%s%x1f%b%x00' "$range" 2>/dev/null)
while IFS= read -r -d '' rec; do
  split_rec "$rec"; [ -n "$h" ] || continue
  printf '%s' "$b" | grep -Eqi 'co-authored-by|signed-off-by|generated with' && bad+="$h (merge) «${s}»: трейлер в теле"$'\n'
done < <(git -C "$wt" log --first-parent --merges --format='%h%x1f%s%x1f%b%x00' "$range" 2>/dev/null)
[ -z "$bad" ] || fail "коммиты не проходят проверку (squash-merge скопирует их в $base):"$'\n'"$bad   → переписать сообщения по слову Oleg, потом снова"
case $branch in
  feature/*-[0-9]*|bugfix/*-[0-9]*|hotfix/*-[0-9]*|tech/*-[0-9]*|sync/*|back-merge/*) ;;
  *) [ $ticketless = 1 ] || decide "Ветка $branch без ключа задачи: CI-проверка branch-and-title упадёт, смержить можно будет только через bypass." "пушить, как решил Oleg (--ticketless-ok) | завести задачу и переименовать ветку (Recommended)" ;;
esac
count=$(git -C "$wt" rev-list --count "$range" 2>/dev/null || echo 0)
printf 'branch: %s\nbase: %s\nrange: %s\ncommits: %s\nopen_pr: %s\n' "$branch" "$base" "$range" "$count" "${open_url:-none}"
[ "$op" = check ] && exit 0
git -C "$wt" push -u origin "$branch" || fail "push отклонён (non-fast-forward?) — force не делаем"
printf 'pushed: %s\n' "$branch"
[ "$op" = push ] && exit 0
if [ -n "$open_url" ]; then printf 'pr_url: %s\nnote: PR уже открыт — второй не создаю\n' "$open_url"; exit 0; fi
[ -n "$title" ] && [ -f "$body" ] || fail "create: нужны --title и --body-file"
case $title in *"'"*) fail "в заголовке PR одинарная кавычка — убери" ;; esac
url=$(gh pr create --repo "$gh_repo" --base "$base" --head "$branch" --title "$title" --body-file "$body") || fail "gh pr create не прошёл"
printf 'pr_url: %s\n' "$url"
gh pr view "$url" --repo "$gh_repo" --json number,url,state,baseRefName,title 2>/dev/null || true
