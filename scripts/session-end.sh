#!/bin/bash
# SessionEnd. stdin: session_id. Releases this session's simulator and writer leases. Never blocks.
IOS_TEAM_HOOK=1 exec "$(dirname "$0")/lib/run.sh" sessend
