#!/bin/bash
# run.sh <mode> [args]: runs team.py with the first python3 found. IOS_TEAM_HOOK=crit makes a crash or a missing python3
# block (exit 2); IOS_TEAM_HOOK=1 lets it pass with a stderr note; unset = helper CLI, exit codes pass through.
py=$(command -v python3 || command -v /opt/homebrew/bin/python3 || command -v /usr/bin/python3)
[ -n "$py" ] && { "$py" "$(dirname "$0")/team.py" "$@"; rc=$?; } || rc=127
{ [ -z "${IOS_TEAM_HOOK:-}" ] || [ $rc = 0 ] || [ $rc = 2 ]; } && exit $rc
[ "$IOS_TEAM_HOOK" = crit ] && { echo "ios-team: проверка $1 не сработала (код $rc) — действие заблокировано" >&2; exit 2; }
echo "ios-team: проверка $1 не сработала (код $rc), пропускаю" >&2; exit 0
