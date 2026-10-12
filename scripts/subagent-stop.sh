#!/bin/bash
# SubagentStop ios-team:.* . stdin: agent_id, last_assistant_message, stop_hook_active. Reads status: from the LAST ```result block.
# None -> decision block, once per agent. status: needs_decision -> that agent's writer and simulator leases stay, marked paused
# (they hold 60 min, so a resumed agent is still protected); any other status releases them. Fails open.
IOS_TEAM_HOOK=1 exec "$(dirname "$0")/lib/run.sh" substop
