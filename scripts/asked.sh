#!/bin/bash
# PostToolUse AskUserQuestion and UserPromptSubmit from the main session: remembers when Oleg last spoke, for stop-check.sh, and
# adds context: which agents wait for him, and where a message addressed to one agent («Сообщение для <name>: …») must go. Fails open.
IOS_TEAM_HOOK=1 exec "$(dirname "$0")/lib/run.sh" asked
