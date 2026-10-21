#!/bin/bash
# PreToolUse Grep|Bash. stdin: session_id, agent_id, cwd, tool_name, tool_input. When the swift-code-index plugin is enabled and the
# checkout at cwd has an Xcode index (DerivedData/<Workspace>-<hash>/Index.noindex/DataStore), the first grep for a Swift symbol
# (a CamelCase identifier, `func name`, `struct Name` … over .swift files) is denied once per agent or main session, naming loadIndex,
# searchSymbol, getOccurrences, findImplementations and symbolsInFile; the retry passes. Strings, logs and lowercase words never match.
# Fails open.
IOS_TEAM_HOOK=1 exec "$(dirname "$0")/lib/run.sh" indexhint
