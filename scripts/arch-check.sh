#!/bin/bash
# arch-check.sh [--staged|--working|--base <ref>] [--repo <dir>] — structural changes in the diff: new Swift files under
# Frameworks/, a new import in Frameworks/<F> that <F> never had, Modules/A importing another feature module for the
# first time, new dependency lines in any Project.swift/Package.swift. Exit 0 clean, 1 hits, 3 not a repo.
exec "$(dirname "$0")/lib/run.sh" arch "$@"
