#!/bin/bash
# Fake Scripts/test.sh for hooks.test.sh: writes a test.sh-shaped summary; FAKE_FAILED=n makes n tests fail, FAKE_EMPTY=1 selects
# no tests. FAKE_ARGS=<file> records the arguments, the lease names held while it runs and ELVA_TEST_DERIVED_DATA.
[ -n "${FAKE_ARGS:-}" ] && { echo "args: $*"; echo "leases: $(ls "$HOME/.claude/ios-team/leases" 2>/dev/null | tr '\n' ' ')"
  echo "dd: ${ELVA_TEST_DERIVED_DATA:-}"; } > "$FAKE_ARGS"
mkdir -p .build/TestResults; n=${FAKE_FAILED:-0}; fail=""; total=$((5 + n))
[ "$n" = 0 ] || fail='{"targetName": "FooTests", "testName": "testBar()"}'
[ -n "${FAKE_EMPTY:-}" ] && { n=0; total=0; echo "  ✗ the run selected no tests at all"; }
printf '{"passedTests": %s, "failedTests": %s, "totalTestCount": %s, "testFailures": [%s]}\n' "$((total - n))" "$n" "$total" "$fail" \
  > .build/TestResults/Elva-PR.summary.json
[ "$total" = 0 ] && exit 1
exit "$n"
