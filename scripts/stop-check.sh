#!/bin/bash
# Stop (main session turn end). An ios-team agent still waits (needs_decision/blocked) although Oleg answered a question after it
# stopped, and no SendMessage reached it -> block once with the agent ids to resume. stop_hook_active passes. Fails open.
IOS_TEAM_HOOK=1 exec "$(dirname "$0")/lib/run.sh" stopcheck
