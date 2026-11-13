#!/bin/bash
# worktree.sh create <TICKET | tech-<slug>> [--type feature|bugfix|tech|hotfix|pilot] [--base <branch | sha for a pilot>] [--target <abs>] [--no-generate]
# worktree.sh remove <abs worktree> [--owner-session <id>] [--unmerged-ok] [--pilot-discard-ok] [--discard-files <file, one path per line>]
# worktree.sh scratch <ref> <name> --dir <session scratchpad> [--build]
# worktree.sh remove-scratch <abs worktree under the scratchpad>
# The worktree recipe the wt-keeper agent followed in 0.1–0.3, as one deterministic script the coordinator runs itself (measured
# over three weeks: a third of that agent's stops were questions a script never asks, 60 round trips). Values come from
# ~/.claude/ios-team/project.md (main_checkout, repo_name, github_repo, workspace). The heavy steps (new-worktree.sh, generate.sh)
# take the heavy lease; run the script in the background with `> <log> 2>&1; echo "exit=$?" >> <log>` and wait with wait-for.sh.
# Prints `key: value` lines. Exit 0 ok; 1 failed (reason on stderr); 3 a decision for Oleg («decision: …» and «options: …» on
# stdout, nothing changed unless said); 64 usage. remove is ONE command for Oleg's dialog: worktree + branch + prune + leases +
# DerivedData + the ticket's simulators; nothing is removed before every check passed.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/project.sh"
usage() { sed -n 2,5p "$0" >&2; exit 64; }
fail() { echo "worktree: $*" >&2; exit 1; }
decide() { printf 'decision: %s\noptions: %s\n' "$1" "$2"; exit 3; }
note() { printf 'note: %s\n' "$*"; }
free_gb() { df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { printf "%d", $4 / 1048576 }'; }
main=$(proj main_checkout); main=${main/#\~/$HOME}; repo=$(proj repo_name); gh_repo=$(proj github_repo); ws=$(proj workspace)
[ -n "$main" ] && [ -e "$main/.git" ] || fail "main_checkout в ~/.claude/ios-team/project.md не чекаут: ${main:-пусто}"
main=$(cd "$main" && pwd -P)
has_origin() { git -C "$main" remote get-url origin >/dev/null 2>&1; }
leases=${IOS_TEAM_LEASES:-$HOME/.claude/ios-team/leases}
clean_dd=$(compgen -G "$HOME/.claude/plugins/cache/*/ios-dev/*/skills/remove-worktree/scripts/clean-derived-data.sh" 2>/dev/null | sort -V | tail -1)
op=${1:-}; shift 2>/dev/null

sweep_and_retry() { # sweep_and_retry <log> <cmd...>: on «No space left» in <log>, sweep once and run <cmd> again
  local log=$1; shift
  grep -q "No space left" "$log" 2>/dev/null || return 1
  note "диск кончился во время шага — sweep и одна повторная попытка"
  "$HERE/sweep.sh" | sed 's/^/note: sweep: /'
  "$@" >>"$log" 2>&1
}

case $op in
create)
  key=${1:-}; shift 2>/dev/null || usage; type=feature; base=develop; target=""; gen=1
  while [ $# -gt 0 ]; do case $1 in
    --type) type=${2:?}; shift 2 ;; --base) base=${2:?}; shift 2 ;; --target) target=${2:?}; shift 2 ;; --no-generate) gen=0; shift ;; *) usage ;;
  esac; done
  if [[ $key =~ ^tech-(.+)$ ]]; then slug=${BASH_REMATCH[1]}; type=tech; branch="tech/$slug"; name="$repo-$slug"
  else
    [[ $key =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]] || fail "ключ задачи вида ABC-123 или tech-<slug>, получено «${key}»"
    key=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]'); slug=$key
    case $type in
      feature|bugfix|tech|hotfix) branch="$type/$key"; name="$repo-$key" ;;
      pilot) branch="pilot/$key"; name="$repo-pilot-$key"; [[ $base =~ ^[0-9a-f]{7,40}$ ]] || fail "пилот стартует от точного sha, получено «${base}»" ;;
      *) fail "type: feature|bugfix|tech|hotfix|pilot" ;;
    esac
  fi
  default_target="$(dirname "$main")/$name"; target=${target:-$default_target}
  [ "$(dirname "$target")" = "$(dirname "$main")" ] || fail "ворктри должна лежать рядом с основным чекаутом: $target"
  case $(basename "$target") in *"$slug"*) ;; *) fail "имя папки должно содержать $slug: $target" ;; esac
  wl=$(git -C "$main" worktree list --porcelain)
  [ -e "$target" ] && decide "Папка $target уже есть ($(git -C "$target" branch --show-current 2>/dev/null || echo 'не git'))." \
    "использовать существующую (Recommended, если ветка та же и там никто не работает) | новое имя через --target"
  grep -qx "branch refs/heads/$branch" <<<"$wl" && decide "Ветка $branch уже выдана другой ворктри: $(grep -B2 -x "branch refs/heads/$branch" <<<"$wl" | sed -n 's/^worktree //p')." \
    "использовать её (Recommended) | новая ветка, имя даёт Oleg"
  if [ "$type" != pilot ] && command -v gh >/dev/null 2>&1 && [ -n "$gh_repo" ]; then
    prs=$(gh pr list --repo "$gh_repo" --head "$branch" --state all --json number,state 2>/dev/null || echo "[]")
    if grep -Eq '"state": *"(MERGED|CLOSED)"' <<<"$prs" && ! grep -q '"state": *"OPEN"' <<<"$prs"; then
      decide "По ветке $branch PR уже MERGED или CLOSED ($prs) — новая работа пересоздаст смёрженную ветку." "новая ветка, имя даёт Oleg (Recommended) | всё равно $branch"
    fi
  fi
  min=${IOS_TEAM_MIN_FREE_GB:-10}; free=$(free_gb)
  if [ "${free:-0}" -lt "$min" ]; then
    "$HERE/sweep.sh" | sed 's/^/note: sweep: /'; free=$(free_gb)
    [ "${free:-0}" -lt "$min" ] && decide "Свободно $free ГБ, ворктри со сборкой и гейтом занимает ~8 ГБ плюс 2 ГБ системе. Самое крупное: $(du -sh "$HOME"/Library/Developer/Xcode/DerivedData/* 2>/dev/null | sort -h | tail -3 | tr '\t' ' ' | tr '\n' ';')" \
      "Oleg освобождает ~$((min - free)) ГБ сам (Recommended) | продолжить с риском (IOS_TEAM_MIN_FREE_GB=$free)"
  fi
  manual=0; start=$base
  if [ "$type" = pilot ]; then
    has_origin && git -C "$main" fetch -q origin 2>/dev/null
    git -C "$main" cat-file -e "$base^{commit}" 2>/dev/null || fail "коммит $base не найден"
    manual=1
  elif has_origin; then
    git -C "$main" fetch -q origin "$base" 2>/dev/null || fail "на origin нет ветки $base"
    cur=$(git -C "$main" branch --show-current)
    if [ "$cur" = "$base" ] && [ -z "$(git -C "$main" status --porcelain --untracked-files=no)" ]; then
      git -C "$main" pull -q --ff-only origin "$base" 2>/dev/null || note "основной чекаут на $base не перемотался (локальные коммиты) — стартую от origin/$base"
    elif ! grep -qx "branch refs/heads/$base" <<<"$wl"; then
      git -C "$main" fetch -q origin "$base:$base" 2>/dev/null || note "локальная $base не перемоталась — стартую от origin/$base"
    else
      note "$base занята ($cur в main или другая ворктри) — не трогаю, стартую от origin/$base"
    fi
    if [ "$(git -C "$main" rev-parse --verify -q "$base")" = "$(git -C "$main" rev-parse --verify -q "origin/$base")" ]; then start=$base; else start="origin/$base"; manual=1; fi
  else
    git -C "$main" rev-parse --verify -q "$base" >/dev/null || fail "нет ветки $base (и нет origin)"
    note "у основного чекаута нет origin — база локальная"
  fi
  log=$(mktemp "${TMPDIR:-/tmp}/worktree-create.XXXXXX")
  if [ $manual = 0 ] && [ "$type" != tech ] && [ "$type" != hotfix ] && [ "$target" = "$default_target" ] && [ -x "$main/Scripts/new-worktree.sh" ]; then
    path=script
    (cd "$main" && "$HERE/lease.sh" run heavy -- Scripts/new-worktree.sh "$key" "$type" "$base") >"$log" 2>&1 || \
      sweep_and_retry "$log" bash -c "cd '$main' && '$HERE/lease.sh' run heavy -- Scripts/new-worktree.sh '$key' '$type' '$base'" || \
      fail "Scripts/new-worktree.sh упал: $(tail -15 "$log" | tr '\n' ' ')"
    [ -d "$target" ] || fail "скрипт отработал, а $target не появилась: $(tail -5 "$log" | tr '\n' ' ')"
  else
    path=manual
    git -C "$main" show-ref --verify --quiet "refs/heads/$branch" && decide "Ветка $branch уже есть локально ($(git -C "$main" log -1 --format=%h%x20%s "$branch"))." \
      "взять её (Recommended, если это та же работа) | новое имя ($( [ "$type" = pilot ] && echo "pilot/$key-2" || echo 'Oleg называет'))"
    if [ "$type" != pilot ] && has_origin && git -C "$main" show-ref --verify --quiet "refs/remotes/origin/$branch"; then start="origin/$branch"; note "ветка $branch уже на origin — подхватываю запушенную работу"; fi
    git -C "$main" worktree add "$target" -b "$branch" "$start" >"$log" 2>&1 || fail "git worktree add: $(tail -5 "$log" | tr '\n' ' ')"
    if compgen -G "$main/Secrets/*.xcconfig" >/dev/null 2>&1; then mkdir -p "$target/Secrets" && cp "$main"/Secrets/*.xcconfig "$target/Secrets/"; else note "в основном чекауте нет Secrets/*.xcconfig — сборка без них не пойдёт"; fi
    if [ $gen = 1 ] && { command -v tuist >/dev/null 2>&1 || [ -n "${IOS_SH:-}" ]; }; then
      "$HERE/generate.sh" "$target" >>"$log" 2>&1 || sweep_and_retry "$log" "$HERE/generate.sh" "$target" || fail "generate.sh упал: $(tail -15 "$log" | tr '\n' ' ')"
    else [ $gen = 1 ] && note "tuist не установлен — проект не сгенерирован"; fi
  fi
  conf=no
  if [ -f "$target/.claude/ios-build.conf" ]; then conf=yes
  elif [ -f "$main/.claude/ios-build.conf" ]; then mkdir -p "$target/.claude" && cp "$main/.claude/ios-build.conf" "$target/.claude/ios-build.conf" && conf=copied
  else note "нет .claude/ios-build.conf ни в ворктри, ни в основном чекауте — ios.sh не соберёт"; fi
  got=$(git -C "$target" branch --show-current); [ "$got" = "$branch" ] || fail "в $target ветка $got, ожидалась $branch"
  git -C "$target" merge-base --is-ancestor "$start" HEAD 2>/dev/null || note "HEAD ворктри не содержит $start — проверь базу"
  dirty=$(git -C "$target" status --porcelain | wc -l | tr -d ' '); [ "$dirty" = 0 ] || note "сразу после создания в ворктри $dirty изменённых файлов — странно"
  printf 'worktree: %s\nbranch: %s\nbase: %s\nstart: %s\nbase_sha: %s\npath: %s\ngenerated: %s\nconf: %s\nfree_gb: %s\nlog: %s\n' \
    "$target" "$branch" "$base" "$start" "$(git -C "$target" rev-parse "$start" 2>/dev/null || git -C "$target" rev-parse HEAD)" "$path" \
    "$( [ -d "$target/$ws" ] && echo yes || echo no)" "$conf" "$(free_gb)" "$log"
  ;;
remove|remove-scratch)
  path=${1:-}; shift 2>/dev/null || usage; owner=""; unmerged=0; pilot_ok=0; discard=""
  while [ $# -gt 0 ]; do case $1 in
    --owner-session) owner=${2:?}; shift 2 ;; --unmerged-ok) unmerged=1; shift ;; --pilot-discard-ok) pilot_ok=1; shift ;; --discard-files) discard=${2:?}; shift 2 ;; *) usage ;;
  esac; done
  [ -d "$path" ] || fail "нет папки $path"
  path=$(cd "$path" && pwd -P)
  [ "$path" != "$main" ] || fail "это основной чекаут, его не удаляем"
  git -C "$main" worktree list --porcelain | grep -qx "worktree $path" || fail "$path не линкованная ворктри $main"
  branch=$(git -C "$path" branch --show-current); key=$(grep -oE '[A-Za-z]+-[0-9]+' <<<"${branch}:$(basename "$path")" | head -1)
  if [ "$op" = remove-scratch ]; then case $path in */scratchpad/*|*/wt/*) ;; *) fail "remove-scratch только для чекаута в scratchpad: $path" ;; esac; fi
  now=$(date +%s)
  for f in "$leases"/*/owner.json; do
    [ -f "$f" ] || continue
    grep -q -e "\"$path\"" -e "\"$branch\"" "$f" 2>/dev/null || continue
    sid=$(sed -n 's/.*"session_id": *"\([^"]*\)".*/\1/p' "$f"); hb=$(sed -n 's/.*"heartbeat": *\([0-9]*\).*/\1/p' "$f")
    if [ -n "$sid" ] && [ "$sid" != "$owner" ] && [ $(( now - ${hb:-0} )) -lt 600 ]; then
      decide "Ворктри ещё в работе у другой сессии: $(basename "$(dirname "$f")") (сессия ${sid:0:8}, активность $(( (now - hb) / 60 )) мин назад)." "подождать (Recommended) | Oleg закрывает ту сессию"
    fi
  done
  busy=$( { lsof -a -d cwd -F pcn 2>/dev/null | awk -v p="$path" '/^p/{pid=substr($0,2)} /^c/{cmd=substr($0,2)} /^n/{n=substr($0,2); if (index(n,p)==1) print pid, cmd}'; pgrep -fl -- "$(printf '%s' "$path" | sed 's/[][\.*^$]/\\&/g')" 2>/dev/null | grep -v " $$ "; } | sort -u)
  heavy=$(grep -Ei 'xcode|xcodebuild|tuist|swift|simulator' <<<"$busy" | grep -v -i 'claude' | head -5)
  [ -n "$heavy" ] && decide "В ворктри работают процессы: $(tr '\n' ';' <<<"$heavy")" "остановить их и повторить (Recommended) | оставить ворктри"
  [ -n "$busy" ] && note "процессы с cwd в ворктри (не мешают удалению): $(head -3 <<<"$busy" | tr '\n' ';')"
  force=""
  dirty=$(git -C "$path" status --porcelain --untracked-files=all)
  if [ -n "$dirty" ]; then
    if [ -n "$discard" ] && [ -f "$discard" ] && [ "$(sed 's/^...//' <<<"$dirty" | sort)" = "$(grep -v '^$' "$discard" | sort)" ]; then force="--force"; note "несохранённые файлы удаляются по списку Oleg: $(wc -l < "$discard" | tr -d ' ')"
    else decide "В ворктри несохранённые или неотслеживаемые файлы: $(sed 's/^...//' <<<"$dirty" | head -8 | tr '\n' ';')" \
      "Oleg сам переносит или удаляет их, потом повторить (Recommended) | удалить вместе с ними (--discard-files <список>) | оставить ворктри"; fi
  fi
  if [ "$op" = remove ]; then
    case $branch in
      pilot/*) [ $pilot_ok = 1 ] || decide "Пилотная ветка $branch без PR, коммиты: $(git -C "$path" log --oneline -5 | tr '\n' ';')" "удалить (--pilot-discard-ok) | оставить" ;;
      *) state=""; command -v gh >/dev/null 2>&1 && [ -n "$gh_repo" ] && state=$(gh pr view "$branch" --repo "$gh_repo" --json state,headRefName 2>/dev/null | sed -n 's/.*"state": *"\([A-Z]*\)".*/\1/p')
         if [ "$state" != MERGED ] && [ $unmerged = 0 ]; then
           decide "PR ветки $branch ${state:-не найден} (не MERGED) — работа ещё не влита." "подождать мержа (Recommended) | удалить всё равно (--unmerged-ok)"
         fi; [ "$state" = MERGED ] || note "PR ${state:-не найден}, удаляю по слову Oleg" ;;
    esac
  fi
  before=$(free_gb)
  cd "$main" || fail "cd $main"
  git -C "$main" worktree remove $force "$path" || fail "git worktree remove не прошёл — ничего не удалено"
  if [ "$op" = remove ]; then git -C "$main" branch -D "$branch" >/dev/null 2>&1 && printf 'branch_deleted: %s\n' "$branch" || note "ветка $branch не удалена (уже нет?)"; else note "ветка $branch оставлена (scratch)"; fi
  git -C "$main" worktree prune
  "$HERE/lease.sh" release "$path" 2>/dev/null | sed 's/^/leases: /'
  [ -n "$clean_dd" ] && bash "$clean_dd" "$path" 2>&1 | sed 's/^/derived_data: /' || note "clean-derived-data.sh из ios-dev не найден — DerivedData не почищена"
  [ "$op" = remove ] && [ -n "$key" ] && "$HERE/ticket-sims.sh" "$key" delete | sed 's/^/simulator_deleted: /'
  printf 'removed: %s\nfree_gb: %s -> %s\nmain_branch: %s\n' "$path" "$before" "$(free_gb)" "$(git -C "$main" branch --show-current)"
  ;;
scratch)
  ref=${1:-}; name=${2:-}; shift 2 2>/dev/null || usage; dir=""; build=0
  while [ $# -gt 0 ]; do case $1 in --dir) dir=${2:?}; shift 2 ;; --build) build=1; shift ;; *) usage ;; esac; done
  [ -n "$dir" ] || usage
  case $ref in pull/*) [ $build = 0 ] || fail "чужой PR (pull/N/head) не собираем: его Project.swift — это код" ;; esac
  target="$dir/wt/$name"; [ -e "$target" ] && fail "уже есть $target"
  has_origin && git -C "$main" fetch -q origin "$ref" 2>/dev/null
  mkdir -p "$dir/wt" && git -C "$main" worktree add --detach "$target" "$(git -C "$main" rev-parse --verify -q FETCH_HEAD 2>/dev/null || echo "$ref")" >/dev/null || fail "worktree add --detach $ref"
  if [ $build = 1 ]; then
    [ "$(free_gb)" -ge 16 ] || { "$HERE/sweep.sh" >/dev/null; [ "$(free_gb)" -ge 16 ] || decide "Свободно $(free_gb) ГБ, сборка scratch-чекаута хочет 16." "Oleg освобождает место | без сборки"; }
    compgen -G "$main/Secrets/*.xcconfig" >/dev/null 2>&1 && mkdir -p "$target/Secrets" && cp "$main"/Secrets/*.xcconfig "$target/Secrets/"
    [ -f "$main/.claude/ios-build.conf" ] && mkdir -p "$target/.claude" && cp "$main/.claude/ios-build.conf" "$target/.claude/"
    "$HERE/generate.sh" "$target" >/dev/null 2>&1 || fail "generate.sh упал в $target"
  fi
  printf 'worktree: %s\nsha: %s\nbuilt: %s\n' "$target" "$(git -C "$target" rev-parse HEAD)" "$( [ $build = 1 ] && echo yes || echo no)"
  ;;
*) usage ;;
esac
