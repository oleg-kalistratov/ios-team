#!/bin/bash
# hooks.test.sh — feeds realistic hook stdin JSON to every script in scripts/ inside a throwaway sandbox (HOME, a fake
# elva-ios repo + worktree, fake xcrun, fake secrets) and asserts the decision. Prints "PASS n / FAIL m"; exit 1 on a failure.
# Needs bash, git, jq, python3, plutil. Touches nothing outside its temp dir: HOME (leases, state), TMPDIR, the scratchpad and
# the main checkout (IOS_TEAM_MAIN_REPO) all live in one mktemp -d per run, so parallel runs cannot interfere (checked at the end).
# Known limits of the guards (pattern checks over command text, not a sandbox; same list in scripts/lib/team.py):
# - code hidden in files outside the repo and the session scratchpad, or generated at run time, is not read;
# - interpreter payloads and scripts (python -c, perl -e, sh file) are scanned only for never-list words: an ordinary push or
#   PR create inside them gets no dialog; runners that are not modelled (make, parallel, expect, npx/bunx, a REPL) can run anything;
# - exfiltration over the network is not detected, except write calls to api.github.com through curl/wget/http;
# - aliases, functions and variables from the user's shell profile are invisible ($VAR as a command name: ask/deny);
# - hardlinks to secret files and secrets copied under another name are not recognised (symlinks are resolved).
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); S=$ROOT/scripts; FX=$ROOT/tests/fixtures
T=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ios-team-test.XXXXXX")" && pwd -P); trap 'rm -rf "$T"' EXIT
export HOME=$T/home TMPDIR=$T/tmp IOS_TEAM_MAIN_REPO=$T/elva-ios PATH="$FX/bin:$PATH" GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R=$T/elva-ios W=$T/elva-ios-ELV-9999 SCR=$T/scratch L=$T/home/.claude/ios-team/leases A=AAAAAAAA-0000-0000-0000-000000000001 P=0 F=0
hdr() { printf '//\n//  %s\n//  ElvaFoo\n//\n//  Created by T on 7.10.26.\n//\n\n' "$1"; }
mkdir -p "$HOME" "$SCR" "$TMPDIR" && git init -q -b develop "$R" && cd "$R" &&
  mkdir -p Modules/ElvaFoo/Sources/Common/Analytics Frameworks/CV1Domain/Sources Secrets documentation/analytics &&
  cp "$FX/methodology.md" documentation/analytics/ && printf 'Secrets/\n.build/\n' > .gitignore && echo 'K = fake' > Secrets/Secrets.xcconfig &&
  printf 'let deps = [\n    .project(target: "CV1Domain", path: "Frameworks/CV1Domain"),\n]\n' > Project.swift &&
  { hdr Existing.swift; printf 'import Foundation\nstruct Existing {}\n'; } > Frameworks/CV1Domain/Sources/Existing.swift &&
  { hdr Old.swift; printf 'struct Old {\n    let a = 1\n}\n'; } > Modules/ElvaFoo/Sources/Old.swift &&
  git add -A && git commit -qm init && git worktree add -q "$W" -b feature/ELV-9999 && mkdir -p "$W/Secrets" "$W/Elva.xcworkspace" &&
  git init -q "$T/other" && git -C "$T/other" commit -q --allow-empty -m init && cd "$T" || { echo "sandbox setup failed"; exit 1; }

J() { # J <tool> <input json> [cwd] [agent_type] [session]; agent_id = "id-<agent_type>"
  jq -nc --arg t "$1" --argjson i "$2" --arg c "${3:-$R}" --arg at "${4:-}" --arg s "${5:-S1}" --arg scr "$SCR" '{session_id: $s, cwd: $c,
    scratchpad_dir: $scr, tool_name: $t, tool_input: $i} + (if $at != "" then {agent_id: ("id-" + $at), agent_type: $at} else {} end)'; }
B() { J Bash "$(jq -nc --arg c "$1" '{command: $c}')" "${2:-$R}" "${3:-}" "${4:-S1}"; }
EV() { # EV <agent_type> <session> [last message]
  jq -nc --arg at "$1" --arg s "$2" --arg m "${3:-}" --arg c "$W" --arg scr "$SCR" '{session_id: $s, cwd: $c, scratchpad_dir: $scr,
    last_assistant_message: $m} + (if $at != "" then {agent_id: ("id-" + $at), agent_type: $at} else {} end)'; }
check() { # check <want: allow|ask|deny|block|ctx> <script> <json> [regex over stdout+stderr]
  local out err rc got=allow
  out=$(printf '%s' "$3" | "$S/$2" 2>"$T/err"); rc=$?; err=$(cat "$T/err")
  [ $rc = 2 ] && got=deny; [ $rc != 0 ] && [ $rc != 2 ] && got=exit$rc
  [ $rc = 0 ] && case $out in *'"permissionDecision": "ask"'*) got=ask ;; *'"decision": "block"'*) got=block ;; *additionalContext*) got=ctx ;; esac
  if [ "$got" = "$1" ] && { [ -z "${4:-}" ] || grep -Eq -- "$4" <<<"$out$err"; }; then P=$((P + 1))
  else F=$((F + 1)); echo "FAIL [$2] want $1${4:+ /$4/}, got $got: ${3:0:160} -> ${out:0:200}${err:0:200}"; fi; }
b() { check "$1" "$2" "$(B "$3" "${4:-$R}" "${5:-}")" "${6:-}"; }       # b <want> <script> <command> [cwd] [agent_type] [regex]
j() { check "$1" "$2" "$(J "$3" "$4" "${5:-$R}" "${6:-}")" "${7:-}"; }  # j <want> <script> <tool> <input> [cwd] [agent_type] [regex]
ok() { if eval "$2"; then P=$((P + 1)); else F=$((F + 1)); echo "FAIL: $1"; fi; }
stage() { git -C "$W" reset -q --hard && git -C "$W" clean -fdq -e Secrets && mkdir -p "$W/$(dirname "$1")" && printf '%b' "$2" > "$W/$1" && git -C "$W" add -A; }
gp() { git -C "$W" rev-parse --path-format=absolute --git-path "$1"; }

X=guard-secrets.sh                                   # --- secrets: everywhere, fail closed
j deny $X Read '{"file_path":"'"$R"'/Secrets/SecretsTest.xcconfig"}' "$R" "" "секреты"
j allow $X Read '{"file_path":"'"$R"'/Modules/ElvaFoo/Sources/Old.swift"}'
j deny $X Read '{"file_path":"'"$R"'/fastlane/AuthKey_X.p8"}'
j deny $X Edit '{"file_path":"'"$R"'/.env.local"}'
ln -s "$R/Secrets/Secrets.xcconfig" "$SCR/innocent.txt"
j deny $X Read '{"file_path":"'"$SCR"'/innocent.txt"}'
b deny $X 'cat Secrets/Secrets.xcconfig | head -3'
b deny $X 'cat Secr*/*.xcconfig'
b deny $X 'head -5 ./Se?rets/*'
b deny $X 'cd Sec*/ && cat *'
b allow $X "cp $R/Secrets/*.xcconfig $W/Secrets/" "$T"
b allow $X "mkdir -p \"$W/Secrets\" && cp \"$R/Secrets/\"*.xcconfig \"$W/Secrets/\"" "$T"
b deny $X "cp $R/Secrets/*.xcconfig $W/Secrets/ && cat $W/Secrets/Secrets.xcconfig" "$T"
b allow $X 'Scripts/new-worktree.sh ELV-9999 feature develop'
b deny $X 'git status --ignored' "$R" "" "игнорируемые"
b deny $X 'git ls-files --others --ignored --exclude-standard'
b deny $X 'ls Secrets'
b deny $X "find . -name '*.xcconfig' -exec cat {} \\;"
b deny $X 'rg --no-ignore API_KEY .'
b deny $X 'grep -rn API_KEY .' "$R" "" "exclude-dir"
b allow $X 'grep -rn struct Modules'
b allow $X 'grep -n Secrets Project.swift'
b deny $X 'grep KEY Secrets/Secrets.xcconfig'
b deny $X 'xcodebuild -showBuildSettings -scheme ElvaTest'
b deny $X "python3 - <<'EOF'
print(open('Secrets/Secrets.xcconfig').read())
EOF"
b deny $X 'gh auth token'
b deny $X "cat $R/Secrets/Secrets.xcconfig" /tmp
j deny $X Glob '{"pattern":"**/*.xcconfig"}'
j allow $X Glob '{"pattern":"**/*.swift"}'
j deny $X Grep '{"pattern":"KEY","path":"'"$R"'/Secrets"}'
j deny $X mcp__xcode__GetTargetBuildSettings '{}'
j deny $X mcp__xcode__XcodeRead '{"filePath":"Elva/Secrets/Secrets.xcconfig"}'
b allow $X 'git commit -m "ELV-1: copy secrets into the worktree"'
j deny $X Monitor '{"command":"tail -f Secrets/Secrets.xcconfig","description":"x","timeout_ms":1000}'
check deny $X '{"tool_name": "Read", '

                                                     # --- V2: case-insensitive paths (APFS), input redirects, archives, keychain
j deny $X Read '{"file_path":"'"$R"'/SECRETS/SECRETS.XCCONFIG"}'
j deny $X Read '{"file_path":"'"$R"'/secrets/secretstest.xcconfig"}'
j deny $X Read '{"file_path":"'"$R"'/fastlane/AuthKey_FAKE.P8"}'
j deny $X Read '{"file_path":"'"$R"'/cert.P12"}'
j deny $X Edit '{"file_path":"'"$R"'/.ENV"}'
j deny $X mcp__xcode__XcodeRead '{"filePath":"'"$R"'/SECRETS/SECRETS.XCCONFIG"}'
j deny $X Grep '{"pattern":"KEY","path":"'"$R"'/SECRETS"}'
j deny $X Glob '{"pattern":"**/*.{xcconfig,p8}"}'
j deny $X Glob '{"pattern":"**/*.XCCONFIG"}'
ln -s "$R/Secrets" "$SCR/cfg"; j deny $X Write '{"file_path":"'"$SCR"'/cfg/planted.xcconfig"}'
for c in 'cat SECRETS/SECRETS.XCCONFIG' 'head fastlane/*.P8' 'cp -r secrets /tmp/s' 'cat < Secrets/Secrets.xcconfig' 'wc -c < fastlane/AuthKey_FAKE.p8' \
  'while read l; do echo $l; done < Secrets/Secrets.xcconfig' 'exec 3< Secrets/Secrets.xcconfig; cat <&3' "sh -s <<< 'cat Secrets/Secrets.xcconfig'" \
  'tar cf - . | tar xOf -' "tar -czf $SCR/a.tgz ." 'tar cf - Modules/..' "zip -r $SCR/a.zip ." "rsync -a --exclude .git ./ $SCR/d/" "cp -R . $SCR/c" \
  "ditto . $SCR/c" "git show 'stash@{0}^3'" 'xcrun xcodebuild -showBuildSettings -scheme ElvaTest' 'xcodebuild -scheme ElvaTest -showBuildSettingsForIndex -json' \
  'security find-generic-password -s gh:github.com -w' 'security find-internet-password -s github.com' 'security dump-keychain' 'cat ~/.config/gh/hosts.yml' \
  'if true; then cat Secrets/Secrets.xcconfig; fi'; do b deny $X "$c"; done
for c in "rsync -a --exclude Secrets ./ $SCR/d/" "tar --exclude=Secrets -czf $SCR/a.tgz ." "cp -R Modules $SCR/m" 'grep -rn --exclude-dir=Secrets API_KEY .' \
  'security find-generic-password -s other-service'; do b allow $X "$c"; done

X=guard-bash.sh                                      # --- never-list deny, outward ask
b ask $X 'git push -u origin feature/ELV-9999' "$W" "" "Пуш feature/ELV-9999 в origin"
b ask $X 'git push -u origin HEAD && gh pr create --base develop --title "[ELV-9999] fix" --body-file /tmp/b.md' "$W" "" \
  "Пуш feature/ELV-9999 в origin и создание PR в develop"
b deny $X 'git push --force origin develop' "$R" "" "force-push в develop"
b deny $X 'git push origin HEAD:refs/heads/develop -f' "$W"
b deny $X "git -C $R push -f origin HEAD" "$T"
b deny $X 'env GIT_TRACE=0 git push --force-with-lease origin develop'
b ask $X 'git push -f origin feature/ELV-9999' "$W" "" "force"
b deny $X 'git push --delete origin feature/x'
b deny $X 'git push origin :feature/x'
b deny $X 'git push --tags'
b deny $X 'git tag v1.2.3 && git push origin v1.2.3'
b deny $X 'gh pr merge 1254 --admin --squash' "$R" "" "мержит только Олег"
b deny $X 'bash -lc "gh pr merge 1"'
b deny $X 'scripts/lease.sh run heavy -- gh pr merge 3'
b deny $X 'echo "$(gh pr merge 3)"'
b deny $X 'gh api -X PUT repos/elva-apps/elva-ios/pulls/1/merge'
b deny $X "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'"
b deny $X 'gh api --method DELETE repos/elva-apps/elva-ios/git/refs/heads/x'
b allow $X 'gh api repos/elva-apps/elva-ios/pulls/1254'
b ask $X 'gh api -X POST repos/elva-apps/elva-ios/issues/1/comments -f body=hi' "$R" "" "gh api POST"
b deny $X 'gh workflow run nightly.yml'
b ask $X 'gh run rerun 123'
b deny $X 'bundle exec fastlane beta_test' "$R" "" "fastlane"
b deny $X 'cd fastlane && fastlane beta_prod'
b deny $X 'sudo rm -rf /tmp/x'
b deny $X 'launchctl unload x.plist'
b deny $X 'Scripts/ci-runner-setup.sh'
b deny $X 'git commit --no-verify -m "ELV-1: x"' "$W"
b allow $X 'git commit -m "ELV-9999: x"' "$W"
b deny $X 'git commit -m "ELV-9999: x"' "$W" ios-team:ios-engineer "координатор"
b deny $X 'gh pr create --base develop' "$W" ios-team:ios-engineer "publisher"
b ask $X 'gh pr create --base develop --title T' "$W" ios-team:publisher "создание PR в develop"
b deny $X 'rm -rf ~'
b deny $X "rm -rf $R" "$T"
b allow $X "rm -rf $SCR/tmp"
b allow $X "rm -rf $W/.build/agent-logs"
b ask $X "rm -rf $W/Modules" "$R" "" "rm -rf"
DDR=$HOME/Library/Developer/Xcode/DerivedData; mkdir -p "$DDR/Elva-live" "$DDR/Elva-gone"
for d in live:"$W" gone:"$T/elva-ios-ELV-1"; do f="$DDR/Elva-${d%%:*}/info.plist"
  plutil -create xml1 "$f" && plutil -insert WorkspacePath -string "${d#*:}/Elva.xcworkspace" "$f"; done
b deny $X "rm -rf $DDR/Elva-live" "$R" "" "живого worktree"
b ask $X "rm -rf $DDR/Elva-gone" "$R" "" "DerivedData"
b ask $X 'git checkout develop' "$R" "" "основной копии"
b ask $X "git -C $R reset --hard origin/develop" "$T"
b allow $X 'git checkout -- Modules' "$W"
b allow $X "git -C $R pull --ff-only origin develop" "$T"
b ask $X "git -C $R worktree remove $W" "$T" "" "Удаление worktree"
echo draft > "$W/notes.md"; b ask $X "git -C $R worktree remove --force $W" "$T" "" "ВМЕСТЕ с несохранёнными файлами: 1"; rm -f "$W/notes.md"
b deny $X "git -C $R worktree remove --force $W" "$T" ios-team:reviewer "force"
b ask $X 'git branch -D feature/ELV-1'
b ask $X 'bash ~/.claude/plugins/x/ios.sh run --console' "$W" "" "телефоне"
b allow $X 'ios.sh run --simulator' "$W"
b ask $X 'xcrun devicectl device install app --device X a.app'
b ask $X "\"$S/lease.sh\" take sim $A" "$R" "" "Забрать"
b deny $X 'xcodebuild -scheme Elva-PR test' "$W" ios-team:reviewer "только читает"
b allow $X 'git diff develop...HEAD -- Modules | head -200' "$W" ios-team:reviewer
b allow $X 'gh pr view 1254 --json files' "$W" ios-team:reviewer
b deny $X "echo x > $W/Modules/a.swift" "$W" ios-team:reviewer
b allow $X "cat > $SCR/notes.md <<'EOF'
- finding
EOF" "$W" ios-team:reviewer
b deny $X "sed -i '' s/a/b/ Modules/x.swift" "$W" ios-team:reviewer
b deny $X 'Scripts/test.sh' "$W" ios-team:reviewer
b deny $X 'git checkout develop' "$W" ios-team:reviewer
b deny $X 'gh pr comment 1 --body x' "$W" ios-team:reviewer
b deny $X 'tuist generate --no-open' "$W" ios-team:architect
b deny $X "python3 -c \"open('x.txt','w').write('1')\"" "$W" ios-team:analytics
b ask $X "git push origin 'x"
j deny $X Monitor '{"command":"gh pr merge 1","description":"x","timeout_ms":1000}'
j allow $X Monitor '{"ws":{"url":"wss://x"},"description":"x","timeout_ms":1000}'
j deny $X mcp__terminal__run_in_terminal '{"command":"bundle exec fastlane beta_prod"}'

                                                     # --- V2: keywords, wrappers, gh global flags
for c in 'if true; then gh pr merge 1; fi' 'for i in 1; do git push -f origin HEAD:develop; done' 'while true; do fastlane beta_prod; break; done' \
  'until false; do sudo ls; done' '! gh pr merge 1' '{ gh pr merge 1; }' '( gh pr merge 1 )' 'case x in x) gh pr merge 1;; esac' \
  'if true; then :; else gh pr merge 1; fi' 'if false; then :; elif gh pr merge 1; then :; fi' 'time -p gh pr merge 1' 'nice -n 5 gh pr merge 1' \
  'command gh pr merge 1' 'builtin exec gh pr merge 1' 'echo 1 | xargs -I{} gh pr merge {}' "env -S 'gh pr merge 1'" 'arch -arm64 gh pr merge 1' \
  'gh -R elva-apps/elva-ios pr merge 1' 'gh --repo elva-apps/elva-ios pr merge 1' 'gh --repo=elva-apps/elva-ios workflow run nightly.yml' \
  'gh -R elva-apps/elva-ios release create v9' 'gh pr --repo x merge 1' 'gh --hostname github.com api -X PUT repos/elva-apps/elva-ios/pulls/1/merge' \
  'if true; then git commit --no-verify -m x; fi'; do b deny $X "$c" "$W"; done
b ask $X 'if true; then git push origin HEAD; fi' "$W" "" "Пуш feature/ELV-9999"
b ask $X 'for i in 1; do gh pr create --base develop --title x; done' "$W" "" "создание PR"
b ask $X 'gh -R elva-apps/elva-ios pr create --base develop --title x' "$W" "" "создание PR в develop"
b allow $X 'gh -R elva-apps/elva-ios pr view 1254' "$W" ios-team:reviewer
                                                     # --- V2: scripts, interpreters, aliases, variables as command names
printf 'gh pr merge 1 --admin\n' > "$SCR/m.sh"; printf 'import subprocess\nsubprocess.run(["gh", "pr", "merge", "1"])\n' > "$SCR/m.py"
printf 'require("child_process").execSync("fastlane beta")\n' > "$SCR/m.js"; printf 'echo ok\n' > "$SCR/ok.sh"
for c in "bash $SCR/m.sh" "sh -e $SCR/m.sh" "source $SCR/m.sh" ". $SCR/m.sh" "chmod +x $SCR/m.sh && $SCR/m.sh" "python3 $SCR/m.py" "node $SCR/m.js" \
  "bash -c 'g=gh; \$g pr merge 1'" "sh -s <<< 'gh pr merge 1'" "bash <<'EOF'
git push --force origin develop
EOF" 'eval "echo hi"' "python3 -c \"import subprocess;subprocess.run(['gh','pr','merge','1'])\"" "perl -e 'system(\"gh pr merge 1\")'" \
  "osascript -e 'do shell script \"fastlane beta\"'" 'ruby -S fastlane beta_prod' "alias m='gh pr merge'; m 1" \
  "GIT_SSH_COMMAND='gh pr merge 1' git fetch" "GIT_CONFIG_PARAMETERS=\"'core.hooksPath=/dev/null'\" git commit -m 'ELV-1: x'"; do b deny $X "$c" "$W"; done
b deny $X "python3 -c \"import subprocess; subprocess.run(['git', 'push', '-f', 'origin', 'HEAD:develop'])\"" "$W" "" "запрещённое"
b allow $X "bash -c 'echo git push origin feature/fix-foo'" "$W"
b ask $X 'g=gh; $g pr merge 1' "$W" "" "переменной"
b deny $X 'g=gh; $g pr merge 1' "$W" ios-team:ios-engineer "переменной"
b ask $X "echo 'gh pr merge 1' | sh" "$W" "" "конвейера"
b deny $X "echo 'gh pr merge 1' | bash" "$W" ios-team:ios-engineer "конвейера"
b deny $X 'source <(echo gh pr merge 1)' "$W" ios-team:ios-engineer "конвейера"
b allow $X "bash $SCR/ok.sh" "$W"
b allow $X "bash -c 'echo hi'" "$W"
                                                     # --- V2: git config overrides, commit-tree, wildcard/tag pushes
b deny $X "git -c core.hooksPath=/dev/null commit -m 'ELV-9999: x'" "$W" "" "hooksPath"
b deny $X 'git commit-tree HEAD^{tree} -p HEAD -m x' "$W" "" "commit-tree"
b deny $X "git -c alias.m='!gh pr merge 1' m" "$W" "" "alias"
b deny $X "git config alias.x '!gh pr merge 1'" "$W" "" "alias.x"
b allow $X 'git -c color.ui=never log -1' "$W"
b allow $X 'git config --get core.hooksPath' "$W"
git -C "$W" tag v1.10.0
b deny $X "git push origin '+refs/heads/*:refs/heads/*'" "$W" "" "force-push"
b deny $X "git push origin 'refs/heads/*:refs/heads/*' -f" "$W"
b deny $X 'git push origin tag v1.10.0' "$W" "" "тегов"
b deny $X 'git push origin v1.10.0' "$W" "" "тегов"
b deny $X 'git -c push.default=matching push --force' "$W"
b ask $X "git push origin 'refs/heads/*:refs/heads/*'" "$W" "" "защищённую"
                                                     # --- V2: GraphQL from files, REST releases/tags, raw HTTP to api.github.com
printf 'mutation { addComment(input: {subjectId: "x", body: "y"}) { clientMutationId } }\n' > "$SCR/q.graphql"
printf 'query { viewer { login } }\n' > "$SCR/r.graphql"
b deny $X "gh api graphql -f query='mutation { addComment(input: {}) { clientMutationId } }'" "$W" "" "GraphQL"
b deny $X "gh api graphql -F query=@$SCR/q.graphql" "$W" "" "GraphQL"
b allow $X "gh api graphql -F query=@$SCR/r.graphql" "$W"
b deny $X 'gh api graphql -F query=@/etc/hosts' "$W" "" "вне репозитория"
b deny $X 'gh api graphql -f query="$(cat /tmp/q)"' "$W" "" "подстановкой"
b allow $X "gh api graphql -f query='query { viewer { login } }'" "$W"
b deny $X 'gh api repos/elva-apps/elva-ios/releases -f tag_name=v9' "$W" "" "релизы"
b deny $X 'gh api repos/elva-apps/elva-ios/git/refs -f ref=refs/tags/v9 -f sha=abc' "$W" "" "теги"
b deny $X 'curl -X PUT https://api.github.com/repos/elva-apps/elva-ios/pulls/1/merge' "$W" "" "curl"
b deny $X "curl -s -d '{}' https://api.github.com/repos/elva-apps/elva-ios/issues" "$W"
b deny $X 'wget --method=DELETE https://api.github.com/repos/elva-apps/elva-ios' "$W"
b deny $X 'http POST api.github.com/repos/elva-apps/elva-ios/issues title=x' "$W"
b allow $X 'curl -sSL https://api.github.com/repos/elva-apps/elva-ios/pulls/1' "$W"
                                                     # --- V3 F11 rm -f, V2 stash, self-protection through Bash
b allow $X "rm -f $W/Modules/ElvaFoo/Sources/Old.swift" "$W" ios-team:ios-engineer
b allow $X "rm -f $SCR/x.txt" "$W" ios-team:ios-engineer
b ask $X "rm -f $R/Modules/x.swift" "$R" "" "rm -f"
b deny $X "rm -f $W/.git" "$W" "" ".git"
b ask $X 'git stash -u' "$R" "" "Secrets"
b ask $X 'git stash push --include-untracked -m wip' "$R" "" "Secrets"
b allow $X 'git stash -m wip' "$W"
b ask $X "sed -i '' 's/deny(/print(/' \"$ROOT/scripts/lib/team.py\"" "$W" "" "файлы плагина"
b deny $X "sed -i '' 's/deny(/print(/' \"$ROOT/scripts/lib/team.py\"" "$W" ios-team:ios-engineer "файлы плагина"
b deny $X "echo '{\"disableAllHooks\":true}' > $W/.claude/settings.local.json" "$W" "" "disableAllHooks"
b ask $X 'cp /tmp/x.json ~/.claude/settings.json' "$W" "" "настройки Claude Code"
b deny $X "mv ~/.claude/ios-team/leases/sim-$A /tmp/x" "$W" ios-team:ios-engineer "аренды"
b deny $X 'rm -rf ~/.claude/ios-team/leases' "$W" ios-team:qa-tester
b deny $X "python3 -c \"open('.claude/settings.local.json','w').write('{}')\"" "$W" ios-team:ios-engineer "настройки"
b deny $X 'echo x > ~/.claude/plugins/cache/elva-tools/ios-team/0.1.0/hooks/guards.json' "$W" ios-team:wt-keeper "плагины"
b allow $X 'cat ~/.claude/settings.json' "$W"
b allow $X "cp $W/.claude/ios-build.conf $SCR/x.conf" "$W"

X=commit-lint.sh                                     # --- commit message + staged diff (elva-ios only)
stage Modules/ElvaFoo/Sources/Clean.swift "$(hdr Clean.swift)struct Clean {\n    let value = 1\n}\n"
b allow $X 'git commit -m "ELV-9999: add Clean"' "$W"
b allow $X 'git commit -m "Tech: bump build number"' "$W"
b deny $X "git commit -m \"\$(cat <<'EOF'
ELV-9999: add Clean

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)\"" "$W" "" "Co-Authored-By"
b deny $X 'git commit -m "ELV-9999: add Clean" -m "more text"' "$W" "" "одна строка"
b deny $X 'git commit -m "fix stuff"' "$W" "" "ELV-XXX"
b deny $X "cd $W && git commit -m 'wip'" "$T"
b deny $X "git commit -F - <<'EOF'
ELV-9999: x

body
EOF" "$W"
b allow $X 'git commit -m "whatever"' "$T/other"
b ask $X 'git commit --no-edit' "$W" "" "Не вижу текста"
printf 'Merge branch develop\n\nCo-Authored-By: someone\n' > "$(gp MERGE_MSG)"; touch "$(gp MERGE_HEAD)"
b deny $X 'git commit --no-edit' "$W" "" "трейлер"
rm -f "$(gp MERGE_HEAD)" "$(gp MERGE_MSG)"
stage Modules/ElvaFoo/Sources/Old.swift "$(hdr Old.swift)struct Old {\n    let a = try? load()\n    // explain\n    let b = c!\n    static func make() {}\n    let t = Text(\"Hello\")\n}\n"
b ask $X 'git commit -m "ELV-9999: x"' "$W" "" "try\\?.*комментарий.*force unwrap.*static.*литералом"
ok "scan-diff.sh exits 1 on hits" '"$S/scan-diff.sh" --staged --repo "$W" >/dev/null; [ $? = 1 ]'
stage Modules/ElvaFoo/Sources/Common/Analytics/DefaultFooAnalytics.swift "$(hdr DefaultFooAnalytics.swift)struct D {\n    let e = AnalyticsEvent(name: \"foo_user_bigButton_tap\")\n}\n"
b ask $X 'git commit -m "ELV-9999: x"' "$W" "" "action «tap»"
stage Modules/ElvaFoo/Sources/Common/Analytics/DefaultFooAnalytics.swift "$(hdr DefaultFooAnalytics.swift)struct D {\n    let e = AnalyticsEvent(\n        name: \"foo_user_bigButton_share\",\n    )\n}\n"
b allow $X 'git commit -m "ELV-9999: x"' "$W"
ok "scan-diff.sh exits 0 when clean (action 'share' read from methodology.md)" '"$S/scan-diff.sh" --staged --repo "$W" >/dev/null'
stage Frameworks/CV1Domain/Sources/NewService.swift "$(hdr NewService.swift)import Foundation\nstruct NewService {}\n"
b ask $X 'git commit -m "ELV-9999: x"' "$W" "" "новый файл в Frameworks"
stage Frameworks/CV1Domain/Sources/Existing.swift "$(hdr Existing.swift)import Foundation\nimport SwiftUI\nstruct Existing {}\n"
b ask $X 'git commit -m "ELV-9999: x"' "$W" "" "новый import SwiftUI"
stage Project.swift 'let deps = [\n    .project(target: "CV1Domain", path: "Frameworks/CV1Domain"),\n    .package(product: "Lottie"),\n]\n'
b ask $X 'git commit -m "ELV-9999: x"' "$W" "" "новая зависимость"
ok "arch-check.sh exits 1 on hits" '"$S/arch-check.sh" --staged --repo "$W" >/dev/null; [ $? = 1 ]'
stage Modules/ElvaFoo/Sources/Old.swift "$(hdr Old.swift)struct Old {\n    let a = 1\n}\n"
printf '%b' "$(hdr Old.swift)struct Old {\n    let a = try? x()\n}\n" > "$W/Modules/ElvaFoo/Sources/Old.swift"
b ask $X 'git commit -am "ELV-9999: x"' "$W" "" "try\\?"

                                                     # --- V2: trailers via flags, $'…', --no-edit, git merge -m; V3 F4 merge commits
stage Modules/ElvaFoo/Sources/Clean.swift "$(hdr Clean.swift)struct Clean {\n    let value = 2\n}\n"
printf 'ELV-9999: x\n\nco-authored-by: z\n' > "$SCR/msg.txt"
for c in "git commit -m 'ELV-9999: x' --trailer 'Co-authored-by: C <c@x>'" "git commit --trailer=Co-authored-by=C -m 'ELV-9999: x'" \
  "git commit -s -m 'ELV-9999: x'" "git commit -sm 'ELV-9999: x'" "git commit --signoff -m 'ELV-9999: x'" \
  "git commit -m \"ELV-9999: x\"\$'\\n\\nCo-Authored-By: y'" "git commit --no-edit -m 'whatever'" \
  "git merge --no-ff -m 'Merge x Co-Authored-By: y' develop" "git commit -F $SCR/msg.txt" "git commit -m 'ELV-9999: x co-authored-by: z'" \
  "if true; then git commit -m 'bad message no ticket'; fi" 'git cherry-pick -s HEAD'; do b deny $X "$c" "$W"; done
b deny $X 'git commit --amend --no-edit' "$W" "" "ELV-XXX"
b allow $X 'git commit -m "ELV-9999: msave fix"' "$W"
stage Modules/ElvaFoo/Sources/Old.swift "$(hdr Old.swift)struct Old {\n    let a = try? load()\n    print(a)\n}\n"
printf "Merge branch 'develop' into feature/ELV-9999\n\n# Conflicts:\n#\tModules/ElvaFoo/Sources/Old.swift\n" > "$(gp MERGE_MSG)"; touch "$(gp MERGE_HEAD)"
b allow $X 'git commit --no-edit' "$W"
b deny $X "git commit -m 'Merge develop' -m 'Co-Authored-By: x'" "$W" "" "трейлер"
rm -f "$(gp MERGE_HEAD)" "$(gp MERGE_MSG)"
b ask $X 'git commit -m "ELV-9999: x"' "$W" "" "try\\?"

X=guard-mcp-writes.sh JIRA=mcp__04c7e156-9165-43fb-b36d-e0f7d6bc2360    # --- MCP writes
JI='{"projectKey":"ELV","summary":"[iOS] Fix bubble","additional_fields":{"customfield_10020":42,"components":[{"id":"10000","name":"iOS"}]}}'
j ask $X ${JIRA}__createJiraIssue "$JI" "$R" "" "\[iOS\] Fix bubble.*спринт: 42.*компонент: iOS"
j deny $X ${JIRA}__createJiraIssue "$JI" "$W" ios-team:ios-engineer
j ask $X ${JIRA}__createJiraIssue "$JI" "$W" ios-team:publisher
j allow $X ${JIRA}__getJiraIssue '{"issueIdOrKey":"ELV-1739"}' "$W" ios-team:reviewer
j deny $X ${JIRA}__updateConfluencePage '{"pageId":"1"}' "$W" ios-team:analytics
j deny $X mcp__plugin_ios-testing_allure-testops__testops_delete_testcase '{"id":1}'
j ask $X mcp__plugin_ios-testing_allure-testops__testops_create_testcase '{"name":"x"}'
j deny $X mcp__ccd_pr__set_auto_merge '{}'
j deny $X mcp__3399ac1e-159a-4f8c-bcda-e7221e51e9e9__trash_file '{"fileId":"x"}'
j deny $X mcp__4b2518e5-e0be-4d20-b39f-face8183b886__use_figma '{}' "$W" ios-team:qa-tester
j deny $X mcp__ccd_session_mgmt__delete_session '{}' "$W" ios-team:wt-keeper
j ask $X mcp__ccd_session_mgmt__send_message '{}'
j allow $X mcp__Claude_Code_iOS_Simulator__control '{"action":"tap"}' "$W" ios-team:qa-tester
j allow $X mcp__ccd_sidebar__create_group '{"name":"ELV-9999"}'

                                                     # --- subagent tool bans, disableAllHooks, bypassPermissions
for t in mcp__claude-in-chrome__navigate mcp__Claude_Browser__javascript_tool mcp__computer-use__left_click mcp__ccd_session_mgmt__list_sessions \
  mcp__scheduled-tasks__create_scheduled_task mcp__remote-devices__computer_screenshot CronCreate CronDelete RemoteTrigger PushNotification SendMessage; do
  j deny $X $t '{"url":"https://github.com/elva-apps/elva-ios/pull/1"}' "$W" ios-team:qa-tester "субагента"; done
j deny $X mcp__claude-in-chrome__computer '{"action":"left_click"}' "$W" Explore
j allow $X SendMessage '{"to":"a1","message":"go on"}'
j allow $X mcp__Claude_Browser__navigate '{"url":"http://localhost:3000"}'
j deny $X mcp__ccd_settings__set_setting '{"key":"disableAllHooks","value":true}' "$R" "" "disableAllHooks"
j deny $X mcp__ccd_session_mgmt__set_session_permission_mode '{"mode":"bypassPermissions"}' "$R" "" "bypassPermissions"
j deny $X mcp__xcode__StringCatalogEdit '{"key":"x"}' "$W" ios-team:qa-tester

X=sim-lease.sh SIM=mcp__Claude_Code_iOS_Simulator__control    # --- simulator leases
sim() { check "$1" $X "$(J $SIM "$2" "$3" "${5:-}" "$4")" "${6:-}"; }   # sim <want> <input> <cwd> <session> [agent_type] [regex]
sim allow '{"action":"tap","device":"iPhone 17 Pro"}' "$W" S1
ok "lease directory created" '[ -f "$L/sim-$A/owner.json" ]'
sim allow '{"action":"screenshot"}' "$W" S1
sim deny '{"action":"tap","udid":"'$A'"}' "$R" S2 "" "Симулятор iPhone 17 Pro занят сессией feature/ELV-9999"
check deny $X "$(B 'xcrun simctl io booted screenshot /tmp/x.png' "$R" "" S3)"
check allow $X "$(B 'xcrun simctl list devices' "$R" "" S3)"
python3 -c "import json,sys; p=sys.argv[1]; o=json.load(open(p)); o['heartbeat']=0; json.dump(o,open(p,'w'))" "$L/sim-$A/owner.json"
sim allow '{"action":"tap","udid":"'$A'"}' "$R" S2
sim deny '{"action":"tap"}' "$W" S1
ok "lease.sh take frees it" '"$S/lease.sh" take sim $A | grep -q "Снял"'
sim allow '{"action":"tap"}' "$W" S1
ok "lease.sh status lists it" '"$S/lease.sh" status | grep -q "sim-$A"'
check allow session-end.sh "$(EV "" S1)"
ok "SessionEnd released it" '[ ! -d "$L/sim-$A" ]'

                                                     # --- sim leases also through ios.sh --sim, xcodebuild -destination, Scripts/test.sh, sim.sh
sim allow '{"action":"tap","udid":"'$A'"}' "$W" S1
for c in 'ios.sh run --simulator --sim "iPhone 17 Pro"' "xcodebuild test -destination id=$A" 'Scripts/test.sh --simulator "iPhone 17 Pro" --runtime 26' \
  "sim.sh --udid $A tap 1 2" 'Scripts/test.sh'; do check deny $X "$(B "$c" "$R" "" S2)" "занят"; done
check allow $X "$(B 'ios.sh run --simulator --sim "iPhone 17"' "$R" "" S2)"
check allow session-end.sh "$(EV "" S1)"; check allow session-end.sh "$(EV "" S2)"
ok "SessionEnd released both sessions' simulators" '! ls -d "$L"/sim-* >/dev/null 2>&1'

E=ios-team:ios-engineer                              # --- writer lease, subagent start/stop
check ctx subagent-start.sh "$(EV $E S1)" "writer lease on .*acquired"
check ctx subagent-start.sh "$(EV ios-team:qa-tester S1)" "branch: feature/ELV-9999.*scratchpad"
j deny writer-guard.sh Edit '{"file_path":"'"$W"'/Modules/a.swift"}' "$W" "" "пишет ios-engineer"
j allow writer-guard.sh Edit '{"file_path":"'"$W"'/Modules/a.swift"}' "$W" $E
j deny writer-guard.sh Write '{"file_path":"'"$W"'/b.swift"}' "$W" ios-team:qa-tester
j allow writer-guard.sh Edit '{"file_path":"'"$R"'/Modules/a.swift"}' "$R"
check block subagent-stop.sh "$(EV $E S1 'done, all good')" "блоком result"
check allow subagent-stop.sh "$(EV $E S1 'still no block')"
j allow writer-guard.sh Edit '{"file_path":"'"$W"'/Modules/a.swift"}' "$W"
sim allow '{"action":"tap"}' "$W" S5 ios-team:qa-tester
check allow subagent-stop.sh "$(EV ios-team:qa-tester S5 $'Готово.\n```result\nagent: qa-tester\nstatus: needs_decision\nsummary: x\n```')"
ok "needs_decision keeps qa-tester's sim lease, paused" '[ -d "$L/sim-$A" ] && grep -q paused "$L/sim-$A/owner.json"'
sim deny '{"action":"tap"}' "$W" S6 "" "занят"
check allow subagent-stop.sh "$(EV ios-team:qa-tester S5 $'```result\nstatus: blocked\n```\nQuoted: ```result\nstatus: needs_decision\n```\n```result\nagent: qa-tester\nstatus: ok\n```')"
ok "a final status: ok releases it (the last result block counts)" '[ ! -d "$L/sim-$A" ]'

X=writer-guard.sh                                    # --- role write scopes, self-protection, writer lease acquire-on-use
j allow $X Write '{"file_path":"'"$SCR"'/qa/notes.md"}' "$W" ios-team:qa-tester
j allow $X Write '{"file_path":"'"$HOME"'/.claude/agent-memory/qa-tester/MEMORY.md"}' "$W" ios-team:qa-tester
j deny $X Write '{"file_path":"'"$W"'/Modules/X.swift"}' "$W" ios-team:qa-tester "scratchpad"
j deny $X Write '{"file_path":"'"$R"'/Modules/X.swift"}' "$R" ios-team:analytics "scratchpad"
j allow $X Write '{"file_path":"'"$SCR"'/pr-body.md"}' "$W" ios-team:publisher
j deny $X Write '{"file_path":"'"$R"'/notes.md"}' "$R" ios-team:publisher
j deny $X Write '{"file_path":"'"$W"'/.claude/ios-build.conf"}' "$W" ios-team:wt-keeper
j deny $X Write '{"file_path":"'"$SCR"'/notes.md"}' "$W" ios-team:reviewer "только читает"
j deny $X Edit '{"file_path":"'"$SCR"'/adr.md"}' "$W" ios-team:architect
j allow $X Write '{"file_path":"'"$SCR"'/eng/plan.md"}' "$W" $E
j deny $X Edit '{"file_path":"'"$R"'/Modules/a.swift"}' "$W" $E "основную копию"
j deny $X Write '{"file_path":"'"$ROOT"'/scripts/lib/team.py"}' "$W" $E "файлы плагина"
j ask $X Write '{"file_path":"'"$ROOT"'/scripts/lib/team.py"}' "$W" "" "файлы плагина"
j deny $X Write '{"file_path":"'"$HOME"'/.claude/plugins/cache/elva-tools/ios-team/0.1.0/hooks/guards.json"}' "$W" $E "плагины"
j ask $X Write '{"file_path":"'"$HOME"'/.claude/settings.json"}' "$W" "" "настройки"
j deny $X Write '{"file_path":"'"$W"'/.claude/settings.local.json"}' "$W" $E "настройки"
j deny $X Write '{"file_path":"'"$HOME"'/.claude/ios-team/leases/sim-X/owner.json"}' "$W" $E "аренды"
j deny $X Edit '{"file_path":"'"$W"'/x.json","old_string":"a","new_string":"\"disableAllHooks\": true"}' "$W" "" "disableAllHooks"
check deny $X '{"tool_name": "Write", '
ok "no writer lease before the engineer's first edit" '! ls -d "$L"/writer-* >/dev/null 2>&1'
j allow $X Edit '{"file_path":"'"$W"'/Modules/a.swift"}' "$W" $E
ok "the engineer's first Edit took the writer lease" 'ls "$L"/writer-*/owner.json >/dev/null 2>&1'
j deny $X Edit '{"file_path":"'"$W"'/Modules/a.swift"}' "$W" "" "пишет ios-engineer"
check deny $X "$(jq -nc --arg c "$W" --arg f "$W/Modules/b.swift" --arg scr "$SCR" '{session_id: "S1", cwd: $c, scratchpad_dir: $scr,
  tool_name: "Edit", tool_input: {file_path: $f}, agent_id: "id-other", agent_type: "ios-team:ios-engineer"}')" "другой ios-engineer"
check allow subagent-stop.sh "$(EV $E S1 $'```result\nagent: ios-engineer\nstatus: needs_decision\n```')"
ok "needs_decision keeps the writer lease, paused" 'grep -q paused "$L"/writer-*/owner.json'
j deny $X Edit '{"file_path":"'"$W"'/Modules/a.swift"}' "$W" "" "ждёт решения"
j allow $X Edit '{"file_path":"'"$W"'/Modules/a.swift"}' "$W" $E
ok "the resumed engineer's Edit un-paused it" '! grep -q paused "$L"/writer-*/owner.json'
check allow subagent-stop.sh "$(EV $E S1 $'```result\nagent: ios-engineer\nstatus: needs_decision\n```')"
b ask guard-bash.sh "\"$S/lease.sh\" take writer $W" "$W" "" "Забрать writer"
ok "lease.sh take writer frees a paused lease" '"$S/lease.sh" take writer "$W" | grep -q "Снял" && ! ls -d "$L"/writer-* >/dev/null 2>&1'
j allow $X Edit '{"file_path":"'"$W"'/Modules/a.swift"}' "$W"
j allow $X Edit '{"file_path":"'"$W"'/Modules/a.swift"}' "$W" $E
check allow subagent-stop.sh "$(EV $E S1 $'```result\nagent: ios-engineer\nstatus: ok\n```')"
ok "status ok releases the writer lease" '! ls -d "$L"/writer-* >/dev/null 2>&1'

WK=ios-team:wt-keeper                                # --- a waiting agent is resumed, never respawned or left hanging
spawn() { J Agent "$(jq -nc --arg t "$1" '{subagent_type: $t, description: "x", prompt: "route: sonnet medium — механика\nx"}')" "$R" "" "$2"; }
spawnr() { J Agent "$(jq -nc --arg t "$1" --arg p "$2" --arg m "${3:-}" --arg e "${4:-}" '{subagent_type: $t, description: "x", prompt: $p}
  + (if $m != "" then {model: $m} else {} end) + (if $e != "" then {effort: $e} else {} end)')" "$R" "" S20; }
check deny agent-spawn-guard.sh "$(spawnr ios-team:ios-engineer 'ticket: ELV-1')" "no route line"
check allow agent-spawn-guard.sh "$(spawnr ios-team:ios-engineer $'route: sonnet medium — переименование в тестах\nticket: ELV-1' sonnet medium)"
check allow agent-spawn-guard.sh "$(spawnr ios-team:ios-engineer $'  route: opus high - навигация\nticket: ELV-1')"
check deny agent-spawn-guard.sh "$(spawnr ios-team:ios-engineer $'route: sonnet medium — x\nticket: ELV-1' opus medium)" "route says sonnet"
check deny agent-spawn-guard.sh "$(spawnr ios-team:ios-engineer $'route: opus high — x\nticket: ELV-1' opus low)" "effort high"
check ask agent-spawn-guard.sh "$(spawnr ios-team:ios-engineer $'route: fable xhigh — Metal-рендер\nticket: ELV-1' fable xhigh)" "Fable для ios-engineer.*Metal"
check allow agent-spawn-guard.sh "$(spawnr Explore 'map the code' sonnet)"

check allow subagent-stop.sh "$(EV $WK S7 $'```result\nagent: wt-keeper\nstatus: needs_decision\n```')"
check deny agent-spawn-guard.sh "$(spawn $WK S7)" "SendMessage.*id-ios-team:wt-keeper"
check allow agent-spawn-guard.sh "$(spawn ios-team:reviewer S7)"
check allow agent-spawn-guard.sh "$(spawn $WK S8)"
check allow agent-spawn-guard.sh "$(J Agent '{"subagent_type":"ios-team:wt-keeper","prompt":"x"}' "$R" ios-team:architect S7)"
check allow stop-check.sh "$(jq -nc '{session_id: "S7"}')"
check ctx asked.sh "$(J AskUserQuestion '{"questions":[]}' "$R" "" S7)" "waiting for Oleg: ios-team:wt-keeper \\(id-ios-team:wt-keeper"
check block stop-check.sh "$(jq -nc '{session_id: "S7"}')" "SendMessage.*id-ios-team:wt-keeper"
check allow stop-check.sh "$(jq -nc '{session_id: "S7", stop_hook_active: true}')"
check allow stop-check.sh "$(jq -nc '{session_id: "S7"}')"
check allow guard-mcp-writes.sh "$(J SendMessage '{"to":"id-ios-team:wt-keeper","message":"d1 closed"}' "$R" "" S7)"
check allow agent-spawn-guard.sh "$(spawn $WK S7)"
check allow subagent-stop.sh "$(EV $WK S7 $'```result\nagent: wt-keeper\nstatus: blocked\n```')"
check deny agent-spawn-guard.sh "$(spawn $WK S7)" "blocked"
check allow subagent-stop.sh "$(EV $WK S7 $'```result\nagent: wt-keeper\nstatus: ok\n```')"
check allow agent-spawn-guard.sh "$(spawn $WK S7)"
check allow asked.sh "$(J AskUserQuestion '{"questions":[]}' "$R" "" S7)"
check allow stop-check.sh "$(jq -nc '{session_id: "S7"}')"
RV=ios-team:reviewer                                 # questions under any status wait; a plain message from Oleg counts as an answer
UP() { jq -nc --arg s "$1" --arg p "$2" '{session_id: $s, hook_event_name: "UserPromptSubmit", prompt: $p}'; }
check allow subagent-stop.sh "$(EV $RV S9 $'```result\nagent: reviewer\nstatus: failed\nneeds_decision:\n  - {id: d1, question_ru: "Оставить баг с двойным тапом?", options: ["Да", "Нет"]}\nnoticed: []\n```')"
check deny agent-spawn-guard.sh "$(spawn $RV S9)" "failed with questions"
check ctx asked.sh "$(UP S9 'реши сам')" "reviewer \(id-ios-team:reviewer, failed with questions.*Оставить баг с двойным тапом"
check block stop-check.sh "$(jq -nc '{session_id: "S9"}')" "SendMessage.to: ..?id-ios-team:reviewer.*still waits"
check ctx asked.sh "$(UP S9 'Сообщение для reviewer: баг с двойным тапом пока давай оставим')" "addressed this message to reviewer \(id-ios-team:reviewer\).*SendMessage.to: ..?id-ios-team:reviewer"
check ctx asked.sh "$(UP S9 'Ответ для qa-tester (d1 «iPad?»): Да. Продолжи этого же агента (a9cc3631cb90cda46) через SendMessage')" "to: ..?a9cc3631cb90cda46"
check allow guard-mcp-writes.sh "$(J SendMessage '{"to":"id-ios-team:reviewer","message":"d1: оставляем; close without action"}' "$R" "" S9)"
check allow asked.sh "$(UP S9 'какой статус?')"
check allow stop-check.sh "$(jq -nc '{session_id: "S9"}')"
check allow subagent-stop.sh "$(EV $RV S9 $'```result\nagent: reviewer\nstatus: failed\nneeds_decision: []\n```')"
check allow agent-spawn-guard.sh "$(spawn $RV S9)"
check allow subagent-stop.sh "$(EV $RV S9 $'```result\nagent: reviewer\nstatus: ok\nneeds_decision:\n- id: d2\n  question_ru: "Проверять iPad?"\n```')"
check deny agent-spawn-guard.sh "$(spawn $RV S9)" "ok with questions"
check allow asked.sh "$(UP S9 '<agent-message from="x">done</agent-message>')"
check allow stop-check.sh "$(jq -nc '{session_id: "S9"}')"
mkdir -p "$L"; b allow guard-secrets.sh "grep -rl -e \"$W\" -e feature/ELV-9999 $L/"   # wt-keeper's lease check: -e values are patterns
b deny guard-secrets.sh "grep -rl -e token $W" "$R" "" "exclude-dir"
b allow guard-bash.sh "bash $ROOT/tests/hooks.test.sh" "$ROOT"     # the plugin's own suite quotes never-list words on purpose
b deny guard-bash.sh "bash $ROOT/tests/hooks.test.sh" "$ROOT" ios-team:reviewer "запрещённое"

ok "disk-check below threshold exits 3" '"$S/disk-check.sh" 999999 >/dev/null 2>&1; [ $? = 3 ]'   # --- helpers
ok "disk-check prints free GB" '"$S/disk-check.sh" 0 | grep -Eq "^[0-9]+$"'
ok "lease run heavy passes the exit code" '"$S/lease.sh" run heavy -- sh -c "exit 7"; [ $? = 7 ] && ! ls -d "$L"/heavy-* 2>/dev/null'
mkdir -p "$L/heavy-0" "$L/heavy-1" && for i in 0 1; do echo $$ > "$L/heavy-$i/pid"; touch "$L/heavy-$i/heartbeat"; done
ok "both heavy units busy -> 75" 'IOS_TEAM_HEAVY_WAIT=1 IOS_TEAM_HEAVY_POLL=1 "$S/lease.sh" run heavy -- true 2>/dev/null; [ $? = 75 ]'
echo 99999 > "$L/heavy-1/pid"
ok "a dead holder is broken" 'IOS_TEAM_HEAVY_WAIT=3 IOS_TEAM_HEAVY_POLL=1 "$S/lease.sh" run heavy -- true 2>/dev/null'
gate() { G=$("$S/gate.sh" "$W" --logs "$SCR/gate" "$@" 2>/dev/null); GRC=$?; }
gate; ok "gate without ios.sh is infra, never ok" '[ $GRC = 3 ] && grep -q "\"verdict\": \"infra\"" <<<"$G"'
git -C "$W" reset -q --hard && git -C "$W" clean -fdq -e Secrets && mkdir -p "$W/Scripts" && cp "$FX/fake-test.sh" "$W/Scripts/test.sh"
export IOS_SH=$FX/bin/fake-ios.sh IOS_TEAM_TEST_RUNNER=repo
gate; ok "gate green: verdict ok, passed 5" '[ $GRC = 0 ] && grep -q "\"verdict\": \"ok\", \"passed\": 5" <<<"$G"'
FAKE_FAILED=1 gate --tests FooTests; ok "gate: failing test listed" '[ $GRC = 1 ] && grep -q "test_failures.*FooTests/testBar()" <<<"$G"'
FAKE_IOS_FAIL=build gate; ok "gate: build break stops before tests" '[ $GRC = 1 ] && grep -q build_break <<<"$G"'
C=CCCCCCCC-0000-0000-0000-000000000003 B2=BBBBBBBB-0000-0000-0000-000000000002   # --- gate: free simulator, no_tests, --no-build, logs
FAKE_ARGS=$T/args gate; ok "gate tests run on the dedicated Elva-Tests simulator" 'grep -q -- "--simulator Elva-Tests-0 --runtime 26 --plan Elva-PR" "$T/args"'
ok "gate held the sim lease while the tests ran" 'grep -q "sim-$C" "$T/args"'
ok "gate released the sim lease after the run" '[ ! -d "$L/sim-$C" ]'
ok "gate JSON names the simulator" 'grep -q "\"simulator\": \"Elva-Tests-0 ($C), iOS 26\"" <<<"$G"'
ok "Xcode DerivedData name for a known workspace path" '[ "$("$S/lib/run.sh" derived-data /Users/elva/Desktop/elva-ios-pilot-ELV-1739/Elva.xcworkspace)" = "$HOME/Library/Developer/Xcode/DerivedData/Elva-dqyslfbvicbdqogepcjkrmluzdqn" ]'
ok "gate tests build into the worktree's Xcode DerivedData" 'grep -q "^dd: $("$S/lib/run.sh" derived-data "$W/Elva.xcworkspace")$" "$T/args"'
ELVA_TEST_DERIVED_DATA=$T/ci-dd FAKE_ARGS=$T/args gate; ok "a preset ELVA_TEST_DERIVED_DATA (CI) is kept" 'grep -q "^dd: $T/ci-dd$" "$T/args"'
lease() { mkdir -p "$L/sim-$1" && jq -nc --arg u "$1" --argjson t "$(date +%s)" '{session_id: "S9", agent_id: "", branch: "other", udid: $u,
  acquired: $t, heartbeat: $t}' > "$L/sim-$1/owner.json"; }
lease $C; FAKE_ARGS=$T/args gate; ok "a leased simulator is skipped: the shut-down iPhone comes next" 'grep -q -- "--simulator iPhone 17 --runtime" "$T/args"'
lease $B2; lease $A; gate; ok "every simulator leased -> infra, no tests run" '[ $GRC = 3 ] && grep -q "нет свободного симулятора" <<<"$G"'
rm -rf "$L/sim-$A" "$L/sim-$B2" "$L/sim-$C"
FAKE_EMPTY=1 gate --tests NoSuchTests; ok "an empty selection is no_tests, not infra" '[ $GRC = 1 ] && grep -q "\"verdict\": \"no_tests\"" <<<"$G"'
FAKE_IOS_FAIL=lint gate --no-build; ok "--no-build skips lint too" '[ $GRC = 0 ] && grep -q "\"verdict\": \"ok\"" <<<"$G"'
FAKE_IOS_FAIL=lint gate; ok "lint still runs with a build" '[ $GRC = 1 ] && grep -q "\"verdict\": \"lint\"" <<<"$G"'
check allow guard-bash.sh "$(B "\"$S/gate.sh\" $W --tests FooTests" "$W" "$E")"
G=$("$S/gate.sh" "$W" 2>/dev/null); ok "gate logs default to the scratchpad guard-bash remembered" 'grep -q "\"tests\": \"$SCR/gate/elva-ios-ELV-9999/" <<<"$G"'
mkdir -p "$L/heavy-0" "$L/heavy-1" && for i in 0 1; do echo $$ > "$L/heavy-$i/pid"; touch "$L/heavy-$i/heartbeat"; done
ok "heavy wait defaults to 45 min and reports progress" 'grep -q "IOS_TEAM_HEAVY_WAIT:-2700" "$S/lease.sh" &&
  IOS_TEAM_HEAVY_WAIT=1 IOS_TEAM_HEAVY_POLL=1 "$S/lease.sh" run heavy -- true 2>&1 | grep -q "жду тяжёлый слот 0 из 0 мин"'
rm -rf "$L/heavy-0" "$L/heavy-1"
unset IOS_SH
cp -R "$FX/bundle-a" "$T/bundle-b" && echo extra >> "$T/bundle-b/socket-logs.txt"
BP=$("$S/bundle-prepass.sh" "$FX/bundle-a" --prev "$T/bundle-b")
ok "prepass: coverage mismatch" 'grep -q "COVERAGE MISMATCH: bundle generated 07-10-2026" <<<"$BP"'
ok "prepass: PII masked" '! grep -Eq "40e3b553|user@example|912 345|1633541234|9F8E7D6C5B|Test User" <<<"$BP"'
ok "prepass: endpoint census" 'grep -q "GET /v1/projects/{id}/media -> 500: 1" <<<"$BP"'
ok "prepass: cmp with previous bundle" 'grep -q "info.txt, app-logs.txt" <<<"$BP"'
ok "prepass: tag histogram" 'grep -q "Upload: 1" <<<"$BP"'

if [ -z "${IOS_TEAM_TEST_CHILD:-}" ]; then              # --- isolation: two whole suites at once must not interfere
  IOS_TEAM_TEST_CHILD=1 bash "$ROOT/tests/hooks.test.sh" >"$T/par1.log" 2>&1 & p1=$!
  IOS_TEAM_TEST_CHILD=1 bash "$ROOT/tests/hooks.test.sh" >"$T/par2.log" 2>&1 & p2=$!
  wait $p1; r1=$?; wait $p2; r2=$?
  ok "two suites run in parallel both pass ($(tail -1 "$T/par1.log"); $(tail -1 "$T/par2.log"))" '[ $r1 = 0 ] && [ $r2 = 0 ]'
  [ $r1 = 0 ] && [ $r2 = 0 ] || grep -h "^FAIL" "$T/par1.log" "$T/par2.log" | head -20
fi

echo "PASS $P / FAIL $F"
[ "$F" = 0 ]
