#!/bin/bash
# test-on-free-sim.sh [Scripts/test.sh args...] — run by gate.sh from the worktree root, inside `lease.sh run heavy`.
# Picks a simulator nobody has leased (<sim_prefix>* from project.md first, then a shut-down iPhone, then a booted one; only unique
# name+runtime pairs), holds its sim lease for the run (owner = this process, so the lease lives exactly as long as
# the tests), runs lib/test-run.sh <udid> <args> (build-for-testing only when the tree changed, then
# test-without-building; IOS_TEAM_TEST_RUNNER=repo falls back to Scripts/test.sh), releases the lease on exit.
# Prints "gate: simulator <name> (<udid>), iOS <major>". Exit: the runner's code; 76 when every simulator is leased.
LIB=$(cd "$(dirname "$0")" && pwd)
pick=$("$LIB/run.sh" sim-pick $$ "$PWD") || { echo "gate: нет свободного симулятора — все заняты другими сессиями" >&2; exit 76; }
IFS=$'\t' read -r udid name major <<<"$pick"
trap '"$LIB/run.sh" lease-release sim "$udid" "gate-$$" >/dev/null 2>&1' EXIT
echo "gate: simulator $name ($udid), iOS $major"
if [ "${IOS_TEAM_TEST_RUNNER:-}" = repo ]; then Scripts/test.sh --simulator "$name" --runtime "$major" "$@"
else "$LIB/test-run.sh" "$udid" "$@"; fi
