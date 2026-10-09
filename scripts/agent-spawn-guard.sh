#!/bin/bash
# PreToolUse Agent|Task from the main session. stdin: session_id, tool_input.subagent_type. An ios-team agent of the same type that
# ended with needs_decision or blocked in this session and was not resumed -> deny: resume it with SendMessage instead. Fails open.
IOS_TEAM_HOOK=1 exec "$(dirname "$0")/lib/run.sh" agentspawn
