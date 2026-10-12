#!/bin/bash
# lease.sh — leases shared by parallel sessions, one directory per lease under ~/.claude/ios-team/leases/.
#   lease.sh status                  list simulator, writer and heavy leases
#   lease.sh take sim <UDID>         break another session's simulator lease (guard-bash asks Oleg first)
#   lease.sh take writer <worktree>  break a writer lease (e.g. an ios-engineer paused on needs_decision)
#   lease.sh release <worktree>      drop every simulator and writer lease held from that worktree (worktree removal)
#   lease.sh run heavy -- <cmd...>   run <cmd> holding one of 2 heavy units (cold builds, tests, tuist); prints the holders
#                                    every 60 s while waiting, gives up after IOS_TEAM_HEAVY_WAIT s (default 2700 = 45 min)
# Exit: run -> the command's own code, 75 when no unit freed up in time; 64 usage.
LEASES="$HOME/.claude/ios-team/leases"
LIB="$(cd "$(dirname "$0")" && pwd)/lib"
case "${1:-}" in
  status) exec "$LIB/run.sh" lease-status ;;
  take) shift; exec "$LIB/run.sh" lease-take "$@" ;;
  release) shift; exec "$LIB/run.sh" lease-release-worktree "$@" ;;
  run) [ "${2:-}" = heavy ] && [ "${3:-}" = -- ] && [ $# -gt 3 ] || { sed -n 2,9p "$0" >&2; exit 64; }; shift 3 ;;
  *) sed -n 2,9p "$0" >&2; exit 64 ;;
esac
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
holders() {
  for d in "$LEASES"/heavy-*; do [ -d "$d" ] || continue
    printf '%s: %s — %s; ' "${d##*/}" "$(basename "$(sed -n 1p "$d/info" 2>/dev/null)")" "$(sed -n 2p "$d/info" 2>/dev/null | cut -c1-60)"
  done
}
mkdir -p "$LEASES"; slot=""; start=$SECONDS; said=-999
while [ -z "$slot" ]; do
  for i in $(seq 0 $(( ${IOS_TEAM_HEAVY_UNITS:-2} - 1 ))); do
    d="$LEASES/heavy-$i"
    if mkdir "$d" 2>/dev/null; then slot=$d; break; fi
    pid=$(cat "$d/pid" 2>/dev/null); hb=$(mtime "$d/heartbeat"); [ "$hb" = 0 ] && hb=$(mtime "$d")
    if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } || [ $(( $(date +%s) - hb )) -gt 600 ]; then
      mv "$d" "$d.stale.$$" 2>/dev/null && rm -rf "$d.stale.$$"
    fi
  done
  [ -n "$slot" ] && break
  if [ $(( SECONDS - start )) -ge "${IOS_TEAM_HEAVY_WAIT:-2700}" ]; then
    echo "lease: тяжёлые слоты заняты дольше ${IOS_TEAM_HEAVY_WAIT:-2700} с: $(holders)— подожди или спроси Олега" >&2; exit 75
  fi
  if [ $(( SECONDS - said )) -ge 60 ]; then
    echo "lease: жду тяжёлый слот $(( (SECONDS - start) / 60 )) из $(( ${IOS_TEAM_HEAVY_WAIT:-2700} / 60 )) мин, заняты: $(holders)" >&2; said=$SECONDS
  fi
  sleep "${IOS_TEAM_HEAVY_POLL:-5}"
done
echo $$ > "$slot/pid"; printf '%s\n%s\n' "$PWD" "$*" > "$slot/info"; touch "$slot/heartbeat"
( while sleep 30; do kill -0 $$ 2>/dev/null || exit 0; touch "$slot/heartbeat" 2>/dev/null || exit 0; done ) &
beat=$!
trap 'kill $beat 2>/dev/null; rm -rf "$slot"' EXIT
trap 'exit 130' INT TERM
"$@"
exit $?
