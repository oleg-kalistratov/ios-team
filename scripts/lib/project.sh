#!/bin/bash
# project.sh — sourced by gate.sh and lib/test-run.sh. proj KEY [DEFAULT] prints the value of `KEY: value` from
# ~/.claude/ios-team/project.md (the first such line; lines starting with # never match), else DEFAULT. Never fails.
PROJECT_MD="$HOME/.claude/ios-team/project.md"
proj() {
  local v
  v=$(sed -n "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//p" "$PROJECT_MD" 2>/dev/null | head -1 | tr -d '\r' | sed 's/[[:space:]]*$//')
  printf '%s' "${v:-${2:-}}"
}
