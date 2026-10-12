#!/bin/bash
# SubagentStart ios-team:.* . stdin: agent_type, agent_id, session_id, cwd, scratchpad_dir. Prints additionalContext (cwd, branch, base,
# main checkout, scratchpad, disk, leases, result contract). ios-engineer: takes the writer lease when cwd is a linked worktree (else on
# its first Edit/Write) and remembers the scratchpad for gate.sh logs. Fails open.
IOS_TEAM_HOOK=1 exec "$(dirname "$0")/lib/run.sh" substart
