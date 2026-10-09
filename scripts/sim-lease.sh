#!/bin/bash
# PreToolUse mcp__Claude_Code_iOS_Simulator__.*|Bash. stdin: session_id, agent_id, cwd, tool_input. Bash: xcrun simctl with a UDID or
# 'booted'; sim.sh, idb, xcodebuild, ios.sh, Scripts/test.sh naming a UDID, --sim/--simulator <name> [--os/--runtime] or -destination;
# Scripts/test.sh without --simulator = the booted iPhone it would pick. Lease ~/.claude/ios-team/leases/sim-<UDID>: free or stale
# (>10 min; a needs_decision pause holds 60 min; a gate.sh run holds while its process lives) -> acquire, own session -> refresh,
# other -> exit 2. Fails open.
IOS_TEAM_HOOK=1 exec "$(dirname "$0")/lib/run.sh" sim
