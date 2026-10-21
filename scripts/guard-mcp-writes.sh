#!/bin/bash
# PreToolUse mcp__.* and CronCreate|CronDelete|RemoteTrigger|PushNotification|SendMessage. stdin: tool_name, tool_input, agent_id, agent_type.
# Deny from any subagent: claude-in-chrome, Claude_Browser, computer-use, ccd_session_mgmt, scheduled-tasks MCP tools and the five tools above.
# Deny always: TestOps delete/restore, set_auto_merge, trash_file, share_file, disableAllHooks in the input, bypassPermissions mode;
# session delete/archive/stop from subagents. Write-like tools: deny from subagents except ios-team:publisher, ask (Russian, with key
# fields) from the main session and publisher, allow (logged) when permission_mode is bypassPermissions. Read-like and local UI tools pass.
# Fails closed.
IOS_TEAM_HOOK=crit exec "$(dirname "$0")/lib/run.sh" mcp
