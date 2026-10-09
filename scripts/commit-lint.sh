#!/bin/bash
# PreToolUse Bash|Monitor|mcp__terminal__run_in_terminal, self-filtered to git commit/merge/cherry-pick/revert/rebase/am inside elva-ios.
# stdin: cwd, tool_input.command. No 'if' filter: git -C / cd && / if-then forms are never skipped.
# Deny: message not one line '^(ELV-\d+|Tech): .+'; Co-Authored-By/Signed-off-by anywhere or any *-by: trailer line (also via $'…',
# -F file, heredoc, --amend --no-edit of a bad HEAD message); --signoff/-s/--trailer; git merge -m with a trailer.
# Merge commits (MERGE_HEAD present) skip the one-line rule and the diff scans (they list other people's code), not the trailer rule.
# Ask: scan-diff / arch-check hits on the staged diff, unreadable message. Exit 2 = deny, ask JSON, 0 = fine. Fails open.
IOS_TEAM_HOOK=1 exec "$(dirname "$0")/lib/run.sh" commit
