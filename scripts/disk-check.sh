#!/bin/bash
# disk-check.sh <min GB> [path] — prints free GB on the volume of path (default $HOME); exit 3 below the threshold.
# Callers stop and ask Oleg; nobody deletes anything to make room.
min=${1:?usage: disk-check.sh <min GB> [path]}
free=$(df -Pk "${2:-$HOME}" 2>/dev/null | awk 'NR==2 {printf "%d", $4 / 1048576}')
[ -n "$free" ] || { echo "disk-check: df не ответил для ${2:-$HOME}" >&2; exit 1; }
echo "$free"
[ "$free" -ge "$min" ] || { echo "disk-check: свободно $free GB < $min GB — остановись и спроси Олега, ничего не удаляй" >&2; exit 3; }
