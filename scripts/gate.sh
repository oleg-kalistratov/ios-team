#!/bin/bash
# gate.sh <worktree> [--tests <filter>]... [--plan Elva-PR|Elva-Nightly] [--no-build] [--base <ref>] [--logs <dir>]
# Verification gate for ios-engineer and the coordinator. Build (ios-dev ios.sh build --simulator) and tests run under
# `lease.sh run heavy`; tests via lib/test-run.sh (the CI plan and scheme, split into build-for-testing — skipped when the
# source tree is unchanged since the last test build — and test-without-building; never the ElvaTest scheme) on a
# simulator nobody has leased, held for the run (lib/test-on-free-sim.sh); lint via ios.sh lint; scan-diff on the branch diff vs base.
# Tests build into the worktree's own Xcode DerivedData (ELVA_TEST_DERIVED_DATA, unless the caller set it), so the app
# build, the tests and Xcode share one copy of the packages and modules instead of a second .build/DerivedData-Tests.
# --no-build skips the app build and lint. Logs: --logs, else $IOS_TEAM_SCRATCH/gate/<worktree>, else the session
# scratchpad that guard-bash remembered for this worktree (<scratchpad>/gate/<worktree>), else $TMPDIR/ios-team-gate/<worktree>.
# Prints one JSON line {verdict: ok|test_failures|build_break|lint|no_tests|infra, passed, failed, failing, scan_hits, simulator,
# logs, note} and writes it to <logs>/gate.json. Exit: 0 ok, 1 test_failures|build_break|lint|no_tests, 3 infra, 64 usage.
HERE=$(cd "$(dirname "$0")" && pwd)
[ -n "${1:-}" ] && [ "${1#-}" = "$1" ] || { sed -n 2,9p "$0" >&2; exit 64; }
wt=$1; shift; plan=Elva-PR; build=1; base=""; logs=""; filters=()
while [ $# -gt 0 ]; do
  case "$1" in
    --tests) filters+=("${2:?--tests needs a filter}"); shift 2 ;;
    --plan) plan=${2:?--plan needs a name}; shift 2 ;;
    --base) base=${2:?--base needs a ref}; shift 2 ;;
    --logs) logs=${2:?--logs needs a dir}; shift 2 ;;
    --no-build) build=0; shift ;;
    *) echo "gate.sh: unknown option $1" >&2; exit 64 ;;
  esac
done
wt=$(cd "$wt" 2>/dev/null && pwd) || { echo '{"verdict": "infra", "note": "нет такой папки"}'; exit 3; }
key=$(cd "$wt" && pwd -P | tr -d '\n' | shasum | cut -c1-12)
scr=$(cat "$HOME/.claude/ios-team/state/gate-scratch-$key" 2>/dev/null)
name=$(basename "$wt")
logs=${logs:-${IOS_TEAM_SCRATCH:+$IOS_TEAM_SCRATCH/gate/$name}}
logs=${logs:-${scr:+$scr/gate/$name}}
logs="${logs:-${TMPDIR:-/tmp}/ios-team-gate/$name}/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$logs" && touch "$logs/.start"
ios=${IOS_SH:-$(ls -d "$HOME"/.claude/plugins/cache/elva-tools/ios-dev/*/skills/build-run/scripts/ios.sh 2>/dev/null | sort -V | tail -1)}
[ -n "$ios" ] || ios=$(ls -t "$HOME/Library/Application Support/Claude"/*/*/*/rpm/*/skills/build-run/scripts/ios.sh 2>/dev/null | head -1)
infra=""; brc=""; lrc=""; trc=""
if [ $build = 1 ] && { [ -z "$ios" ] || [ ! -f "$ios" ]; }; then infra="ios.sh из плагина ios-dev не найден — сборку и линт не проверить"
elif [ ! -f "$wt/Project.swift" ]; then infra="$wt — не checkout elva-ios"
else
  export IOS_PROJECT_ROOT="$wt" IOS_LOG_DIR="$logs"
  export ELVA_TEST_DERIVED_DATA="${ELVA_TEST_DERIVED_DATA:-$("$HERE/lib/run.sh" derived-data "$wt/Elva.xcworkspace")}"
  if [ $build = 1 ]; then
    (cd "$wt" && "$HERE/lease.sh" run heavy -- bash "$ios" build --simulator) >"$logs/build.log" 2>&1; brc=$?
    [ "$brc" = 0 ] && { (cd "$wt" && bash "$ios" lint) >"$logs/lint.log" 2>&1; lrc=$?; }
  fi
  if [ "${brc:-0}" = 0 ]; then
    extra=(); for f in ${filters[@]+"${filters[@]}"}; do case $f in -only-testing:*) extra+=("$f") ;; *) extra+=("-only-testing:$f") ;; esac; done
    (cd "$wt" && "$HERE/lease.sh" run heavy -- "$HERE/lib/test-on-free-sim.sh" --plan "$plan" ${extra[@]+-- "${extra[@]}"}) >"$logs/tests.log" 2>&1; trc=$?
  fi
fi
"$HERE/lib/run.sh" scan --repo "$wt" --base "${base:-$("$HERE/lib/run.sh" base-guess "$wt")}" >"$logs/scan.txt" 2>&1; src=$?
INFRA=$infra BRC=$brc LRC=$lrc TRC=$trc SRC=$src LOGS=$logs SUM="$wt/.build/TestResults/$plan.summary.json" \
  "$(command -v python3 || echo /usr/bin/python3)" - <<'PY'
import json, os, re, sys
e = os.environ
logs = e["LOGS"]
log = lambda n: os.path.join(logs, n)
summary = {}
if os.path.exists(e["SUM"]) and os.path.getmtime(e["SUM"]) >= os.path.getmtime(log(".start")):
    with open(e["SUM"]) as handle:
        summary = json.load(handle)
failing = ["%s/%s" % (f.get("targetName", "?"), f.get("testName", "?")) for f in summary.get("testFailures", [])]
failed = int(summary.get("failedTests", len(failing)) or 0)
tests = open(log("tests.log"), errors="replace").read() if os.path.exists(log("tests.log")) else ""
sim = (re.search(r"^gate: simulator (.+)$", tests, re.M) or re.match("()", "")).group(1)
empty = (summary and summary.get("totalTestCount") == 0) or "selected no tests" in tests
hits = sum(1 for line in open(log("scan.txt"), errors="replace") if line.strip()) if e["SRC"] == "1" else 0
note = e["INFRA"]
if note:
    verdict = "infra"
elif e["BRC"] not in ("", "0"):
    verdict, note = "build_break", "сборка упала, см. build.log"
elif e["TRC"] not in ("", "0") or empty:
    if failed:
        verdict = "test_failures"
    elif e["TRC"] == "75":
        verdict, note = "infra", "тяжёлые слоты заняты дольше 45 мин, см. tests.log"
    elif e["TRC"] == "76":
        verdict, note = "infra", "нет свободного симулятора: все заняты другими сессиями, см. tests.log"
    elif empty:
        verdict, note = "no_tests", "фильтр не выбрал ни одного теста — проверь имя в --tests"
    elif re.search(r"error:|BUILD FAILED|TEST BUILD FAILED", tests):
        verdict, note = "build_break", "тесты не собрались, см. tests.log"
    else:
        verdict, note = "infra", "прогон тестов вернул %s без упавших тестов, см. tests.log" % e["TRC"]
elif e["LRC"] not in ("", "0") or hits:
    verdict, note = "lint", "swiftlint или scan-diff, см. lint.log и scan.txt"
else:
    verdict = "ok"
out = {"verdict": verdict, "passed": int(summary.get("passedTests", 0) or 0), "failed": failed, "failing": failing,
       "scan_hits": hits, "simulator": sim, "note": note, "logs": {n: log(n + s) for n, s in (("build", ".log"), ("lint", ".log"),
                                                                                             ("tests", ".log"), ("scan", ".txt"))}}
out["logs"]["summary"] = e["SUM"] if summary else ""
text = json.dumps(out, ensure_ascii=False)
open(log("gate.json"), "w").write(text + "\n")
print(text)
sys.exit({"ok": 0, "infra": 3}.get(verdict, 1))
PY
