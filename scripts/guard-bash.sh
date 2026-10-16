#!/bin/bash
# PreToolUse Bash|Monitor|mcp__terminal__run_in_terminal — everywhere. stdin: cwd, scratchpad_dir, agent_id, agent_type, tool_input.command.
# Normalises cd/git -C/pipes/;/&&/subshells/{ }/if-then-else/loops/case/!, $'…' quoting, wrappers (env -S, nice, time, exec, command,
# builtin, xargs, arch, watch, script, xcrun, bundle exec, ruby -S, lease.sh run), sh -c / eval payloads, here-strings fed to shells.
# Deny (exit 2): fastlane, gh pr merge (also gh -R x …, gh api merge, GraphQL mutations incl. -F query=@file), gh workflow run,
# gh release create, releases/tag refs via gh api, curl/wget/http writes to api.github.com, force/wildcard/matching/tag pushes,
# --no-verify, git -c core.hooksPath|alias.*|…, git config of those keys, GIT_CONFIG_PARAMETERS, commit-tree, sudo, launchctl, eval,
# never-list words inside sh -c / python -c / perl -e / here-strings / scripts in the repo or scratchpad, disableAllHooks,
# rm -rf of ~ / main checkout / live DerivedData / .git, writes and project code from reviewer|architect|analytics, outward acts from
# other subagents; from any subagent also writes into the plugin, ~/.claude/plugins, .claude/settings*.json, ~/.claude/ios-team,
# a $VAR command name and code piped into a shell.
# Ask (JSON permissionDecision ask, Russian reason): push, gh pr/issue/api writes, worktree remove, branch -D, device runs, lease take,
# rm -rf outside scratch/build dirs, rm -f outside a linked worktree/scratch, git stash -u/-a with Secrets/, main-checkout
# checkout/reset, and (main session) the self-protection, $VAR and piped-code cases above. Fails closed.
# permission_mode bypassPermissions: the routine asks above stay silent; self-protection, $VAR and piped-code cases still ask.
IOS_TEAM_HOOK=crit exec "$(dirname "$0")/lib/run.sh" bash
