#!/bin/bash
# sweep.sh [--dry-run] — frees what nobody needs any more, and only that: Xcode DerivedData whose workspace folder no longer
# exists (a removed worktree; info.plist WorkspacePath), the ticket simulators (ticket-sims.sh) of tickets that have no worktree
# under the main checkout's parent any more, and simulators whose runtime is gone (`simctl delete unavailable`). Never a live
# checkout's DerivedData, never a shared simulator, never a user file. Agents run it before they stop on a full disk (measured:
# three engineer runs and two QA runs stopped for «меньше 2 ГБ» in one week while 8 GB of dead DerivedData sat on the disk).
# Prints what it removed and «free: <before> → <after> GB». IOS_DERIVED_DATA_ROOT overrides the DerivedData folder. Exit 0; 64 usage.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/project.sh"
dry=0; case "${1:-}" in "") ;; --dry-run) dry=1 ;; *) sed -n 2,7p "$0" >&2; exit 64 ;; esac
free_gb() { df -g "$HOME" 2>/dev/null | awk 'NR == 2 { print $4 }'; }
before=$(free_gb)
dd_root=${IOS_DERIVED_DATA_ROOT:-$(defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation 2>/dev/null)}
dd_root=${dd_root:-$HOME/Library/Developer/Xcode/DerivedData}
main=$(proj main_checkout); main=${main/#\~/$HOME}
ws_name=$(proj workspace); ws_name=${ws_name%.*}
live_paths=$( [ -d "$main" ] && git -C "$main" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' )
discard() { # discard <dir> <why>: rename first (instant, Xcode stops seeing it), delete in the background — a multi-GB rm must not hold the caller
  local size trash; size=$(du -sh "$1" 2>/dev/null | cut -f1)
  if [ $dry = 1 ]; then echo "would remove DerivedData ${1##*/} ($size) — $2"; return; fi
  trash="$dd_root/.ios-team-trash-${1##*/}-$$"
  mv "$1" "$trash" 2>/dev/null && { (rm -rf "$trash" >/dev/null 2>&1 &); echo "removed DerivedData ${1##*/} ($size) — $2"; }
}
if [ -d "$dd_root" ] && [ ! -L "$dd_root" ]; then
  # Xcode names a folder <Workspace>-<md5 of the workspace path as 2×14 base-26 letters>. A folder without info.plist is what
  # `xcodebuild -resolvePackageDependencies` (run by tuist generate) leaves: Logs + SourcePackages, often GBs — so the live
  # checkouts' names are computed to tell their folders from a removed worktree's.
  live_names=$(printf '%s\n' $live_paths | while read -r p; do [ -n "$p" ] && printf '%s/%s\n' "$p" "$(proj workspace)" && printf '%s/%s\n' "$(cd "$p" 2>/dev/null && pwd -P)" "$(proj workspace)"; done |
    "$(command -v python3 || echo /usr/bin/python3)" -c '
import hashlib, sys
for path in sys.stdin.read().splitlines():
    digest = hashlib.md5(path.encode()).digest(); name = ""
    for half in (int.from_bytes(digest[:8], "big"), int.from_bytes(digest[8:], "big")):
        letters = ""
        for _ in range(14):
            letters = chr(97 + half % 26) + letters; half //= 26
        name += letters
    print(path.rsplit("/", 1)[-1].rsplit(".", 1)[0] + "-" + name)
' | sort -u)
  for dir in "$dd_root"/*/; do
    dir=${dir%/}; base=${dir##*/}
    [ -d "$dir" ] && [ ! -L "$dir" ] || continue
    if [ -f "$dir/info.plist" ]; then
      ws=$(plutil -extract WorkspacePath raw -o - "$dir/info.plist" 2>/dev/null)
      case $ws in /*) ;; *) continue ;; esac
      [ -e "${ws%/*}" ] || discard "$dir" "${ws%/*} no longer exists"
    elif [ -n "$ws_name" ] && [[ $base =~ ^${ws_name}-[a-z]{28}$ ]] && [ -n "$live_names" ] && ! printf '%s\n' "$live_names" | grep -qx "$base"; then
      discard "$dir" "no live checkout has this name (package resolution leftovers of a removed worktree)"
    fi
  done
  for trash in "$dd_root"/.ios-team-trash-*; do [ -d "$trash" ] && [ ! -L "$trash" ] && (rm -rf "$trash" >/dev/null 2>&1 &); done
fi
key=$(proj ticket_key_example ABC-1234); key=${key%%-*}
if [ -n "$key" ] && json=$(xcrun simctl list devices -j 2>/dev/null); then
  live=$(printf '%s\n' $live_paths | while read -r p; do [ -n "$p" ] && basename "$p"; done)
  printf '%s' "$json" | KEY=$key "$(command -v python3 || echo /usr/bin/python3)" -c '
import json, os, re, sys
seen = set()
for devices in json.load(sys.stdin).get("devices", {}).values():
    for d in devices:
        for m in re.finditer(r"(?:^|[^A-Za-z0-9])(%s-[0-9]+)(?:[^0-9]|$)" % re.escape(os.environ["KEY"]), d.get("name", ""), re.I):
            t = m.group(1).upper()
            if t not in seen:
                seen.add(t); print(t)
' | while read -r ticket; do
    printf '%s\n' "$live" | grep -qi "\(^\|[^A-Za-z0-9]\)$ticket\([^0-9]\|$\)" && continue
    if [ $dry = 1 ]; then echo "would delete the simulators of $ticket (no worktree)"; else
      "$HERE/ticket-sims.sh" "$ticket" delete | while IFS=$'\t' read -r udid name state; do echo "deleted simulator $name ($udid) — $ticket has no worktree"; done
    fi
  done
  [ $dry = 1 ] || xcrun simctl delete unavailable >/dev/null 2>&1
fi
echo "free: ${before:-?} → $(free_gb) GB"
exit 0
