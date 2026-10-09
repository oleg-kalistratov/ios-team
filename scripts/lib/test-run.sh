#!/bin/bash
# test-run.sh <udid> --plan <plan> [-- <xcodebuild args>...] — run by test-on-free-sim.sh from the worktree root.
# Same contract as the repo's Scripts/test.sh (result bundle, log and summary JSON in .build/TestResults/<plan>.*, the
# "<plan> passed|failed in Xm Ys" line, a failing-tests list), split in two so a re-run on unchanged code skips the build:
# build-for-testing runs only when the source tree changed since this plan was last built into this DerivedData
# (stamp = HEAD + tracked diff + untracked file hashes), then test-without-building on <udid>.
# -collect-test-diagnostics never: on any failure xcodebuild otherwise spends up to 600 s collecting a simulator
# sysdiagnose (measured on ELV-959: 2.5 min of tests, then a 10 min diagnostics timeout).
# Exit: xcodebuild's code; 65 when the test build fails; 1 when the run selected no tests.
set -uo pipefail
udid=${1:?udid}; shift
plan=Elva-PR; extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) plan=${2:?--plan needs a name}; shift 2 ;;
    --) shift; extra=("$@"); break ;;
    *) echo "test-run.sh: unknown option $1" >&2; exit 64 ;;
  esac
done
root=$(git rev-parse --show-toplevel) || exit 64
cd "$root" || exit 64
[ -f "TestPlans/$plan.xctestplan" ] || { echo "❌ No such test plan: TestPlans/$plan.xctestplan" >&2; exit 1; }
[ -d Elva.xcworkspace ] || tuist generate --no-open >/dev/null
dd=${ELVA_TEST_DERIVED_DATA:-$root/.build/DerivedData-Tests}
res=$root/.build/TestResults
bundle=$res/$plan.xcresult; log=$res/$plan.log; sum=$res/$plan.summary.json
mkdir -p "$res" "$dd"; rm -rf "$bundle" "$sum"
stamp_file=$dd/ios-team-build-for-testing-$plan.stamp
stamp=$({ git rev-parse HEAD; git diff HEAD; git ls-files --others --exclude-standard -z | xargs -0 shasum 2>/dev/null; } | shasum | cut -c1-40)
common=(-workspace Elva.xcworkspace -scheme "$plan" -testPlan "$plan" -destination "id=$udid" -derivedDataPath "$dd"
  -skipPackagePluginValidation -skipMacroValidation)
echo "▶︎ Plan:      $plan"
started=$SECONDS
finish() {
  local status=$1 elapsed=$((SECONDS - started))
  printf '\n%s in %dm %02ds\n' "$([ "$status" = 0 ] && echo "✅ $plan passed" || echo "❌ $plan failed")" $((elapsed / 60)) $((elapsed % 60))
  [ "$status" = 0 ] || echo "   Full log: ${log#"$root"/}"
  exit "$status"
}
if [ "$(cat "$stamp_file" 2>/dev/null)" = "$stamp" ] && ls "$dd"/Build/Products/"$plan"_*.xctestrun >/dev/null 2>&1; then
  echo "▶︎ Build:     reused (no source change since the last test build)"
  : >"$log"
else
  echo "▶︎ Build:     build-for-testing"
  rm -f "$stamp_file"
  if ! xcodebuild build-for-testing "${common[@]}" >"$log" 2>&1; then
    echo "No result bundle — the build failed before any test ran:"
    grep -E "^(.*: )?error: " "$log" | sort -u | head -20
    echo "TEST BUILD FAILED"
    finish 65
  fi
  echo "$stamp" >"$stamp_file"
fi
xcodebuild test-without-building "${common[@]}" -collect-test-diagnostics never -resultBundlePath "$bundle" ${extra[@]+"${extra[@]}"} >>"$log" 2>&1
status=$?
if [ -d "$bundle" ]; then
  xcrun xcresulttool get test-results summary --path "$bundle" --format json >"$sum"
  python3 - "$sum" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
total = report.get("totalTestCount", 0)
print("{}: {} passed, {} failed, {} skipped of {}".format(report.get("result", "unknown"), report.get("passedTests", 0),
      report.get("failedTests", 0), report.get("skippedTests", 0), total))
for failure in report.get("testFailures", []):
    print("  ✗ {}/{}".format(failure.get("targetName", "?"), failure.get("testName", "?")))
    message = (failure.get("failureText") or "").strip()
    if message:
        print("      " + message)
if not total:
    print("  ✗ the run selected no tests at all — an empty plan or a filter that matches nothing")
    sys.exit(1)
PY
  empty=$?
  [ "$status" = 0 ] && [ "$empty" != 0 ] && status=$empty
else
  echo "No result bundle — the test run failed before any test ran:"
  grep -E "^(.*: )?error: " "$log" | sort -u | head -20
fi
finish "$status"
