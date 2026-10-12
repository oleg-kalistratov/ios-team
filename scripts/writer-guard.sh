#!/bin/bash
# PreToolUse Edit|Write|NotebookEdit. stdin: agent_id, agent_type, cwd, scratchpad_dir, tool_input.file_path|notebook_path (+ content).
# Deny (exit 2) / ask: disableAllHooks in the content -> deny; the plugin root, ~/.claude/plugins/**, any .claude/settings*.json,
# ~/.claude/ios-team/** -> deny for subagents, ask for the main session. Role scopes: reviewer|architect write nothing;
# qa-tester|analytics|publisher|wt-keeper only the session scratchpad and their agent-memory dir; ios-engineer its worktree
# (+ scratchpad), taking/refreshing the worktree writer lease on each write. Anyone else: a fresh writer lease of another agent -> deny.
# Fails closed on unreadable input; the lease part fails open.
IOS_TEAM_HOOK=crit exec "$(dirname "$0")/lib/run.sh" writer
