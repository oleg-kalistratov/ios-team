#!/bin/bash
# wait-for.sh <file> <regex> [max_seconds=540] — blocks until a line of <file> matches <regex> (grep -E), then prints that line and
# exits 0; exits 124 when max_seconds passed (call it again: the wait is not a failure), 64 on usage. For agents waiting on a
# background command's log (`exit=`, `"verdict"`): a foreground call of this script keeps the agent's turn open, which the
# Monitor tool does not — Monitor returns at once, the turn ends with nothing to do, the stop hook asks for a result block, and
# the agent reports «tuist ещё идёт» as blocked (seen twice on 2026-10-23). The guard denies `until … sleep` loops in the
# command text; this script is the sanctioned loop. max_seconds stays under the Bash tool's 10-minute cap.
file=${1:-}; pattern=${2:-}; max=${3:-540}
[ -n "$file" ] && [ -n "$pattern" ] && [[ $max =~ ^[0-9]+$ ]] || { sed -n 2,7p "$0" >&2; exit 64; }
start=$SECONDS
while :; do
  if [ -f "$file" ] && line=$(grep -E -m1 -- "$pattern" "$file" 2>/dev/null) && [ -n "$line" ]; then printf '%s\n' "$line"; exit 0; fi
  [ $(( SECONDS - start )) -ge "$max" ] && { echo "wait-for: «$pattern» не появилось в $file за $max с — вызови ещё раз, команда может ещё идти" >&2; exit 124; }
  sleep "${WAIT_FOR_POLL:-5}"
done
