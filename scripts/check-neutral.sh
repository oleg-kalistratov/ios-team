#!/bin/bash
# check-neutral.sh — the repository stays generic: no project or company name in any tracked text file. Prints every hit as
# path:line:text and exits 1; prints nothing and exits 0 when clean. Project values live in ~/.claude/ios-team/project.md.
# The bracketed first letters keep this file from matching itself; the first run also covers the company's domain and the
# last one that project's ticket keys. Case-insensitive, text files only (-I).
# No allow-list is needed today: no English word in the repo contains these letter runs. Add a narrow one here if that changes.
root=$(cd "$(dirname "$0")/.." && pwd -P)
pat='[e]lva|[c]ivione|[E]LV-'
if [ "$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" = "$root" ]; then
  hits=$(git -C "$root" grep -n -I -i -E "$pat")
else
  hits=$(cd "$root" && grep -rnIiE --exclude-dir=.git "$pat" .)
fi
[ -z "$hits" ] && exit 0
printf '%s\n' "$hits"
exit 1
