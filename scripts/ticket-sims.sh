#!/bin/bash
# ticket-sims.sh <TICKET> [list|shutdown|delete] — the simulators made for one ticket: a device whose name contains the ticket
# key as a whole word (Duo-ABC-123, iPhone-ABC-123). The shared simulators from ~/.claude/ios-team/project.md (sim_prefix*,
# qa_sims_dev, qa_sims_prod) are never touched, whatever their name. Used by qa-tester at the end of a run (shutdown: a booted
# simulator keeps 2–4 GB of memory and a few hundred processes) and by wt-keeper op=remove (delete, in the same compound command
# as the worktree removal). Prints one "<udid>\t<name>\t<state>" line per matching device, after the action. Exit 0 also when
# nothing matched; 64 usage; 3 when simctl failed.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/project.sh"
ticket=${1:-}; op=${2:-list}
[[ $ticket =~ ^[A-Za-z][A-Za-z0-9]*-[0-9]+$ ]] || { sed -n 2,7p "$0" >&2; exit 64; }
case $op in list|shutdown|delete) ;; *) sed -n 2,7p "$0" >&2; exit 64 ;; esac
json=$(xcrun simctl list devices -j 2>/dev/null) || { echo "ticket-sims: xcrun simctl list failed" >&2; exit 3; }
TICKET=$ticket PREFIX=$(proj sim_prefix) SHARED="$(proj qa_sims_dev), $(proj qa_sims_prod)" \
  "$(command -v python3 || echo /usr/bin/python3)" - "$json" <<'PY' | while IFS=$'\t' read -r udid name state; do
import json, os, re, sys
e = os.environ
shared = {x.strip() for x in e["SHARED"].split(",") if x.strip()}
prefix = e["PREFIX"]
word = re.compile(r"(^|[^A-Za-z0-9])%s([^0-9]|$)" % re.escape(e["TICKET"]), re.I)
for devices in json.loads(sys.argv[1]).get("devices", {}).values():
    for d in devices:
        name = d.get("name", "")
        if name in shared or (prefix and name.startswith(prefix)) or not word.search(name):
            continue
        print("%s\t%s\t%s" % (d.get("udid", ""), name, d.get("state", "")))
PY
  case $op in
    shutdown) [ "$state" = Shutdown ] || xcrun simctl shutdown "$udid" >/dev/null 2>&1; state=Shutdown ;;
    delete) xcrun simctl shutdown "$udid" >/dev/null 2>&1; xcrun simctl delete "$udid" >/dev/null 2>&1 && state=Deleted ;;
  esac
  printf '%s\t%s\t%s\n' "$udid" "$name" "$state"
done
exit 0
