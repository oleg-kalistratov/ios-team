#!/bin/bash
# scan-diff.sh [--staged|--working|--base <ref>] [--repo <dir>] — CLAUDE.md invariants on ADDED Swift lines:
# try?, force unwrap, // comments (header/MARK/swiftlint aside), static func|var/.shared/top-level func, AnyView,
# Image("/Text(" literals, print(, XCTest, Task.sleep in tests, missing file header, analytics event names
# (4 blocks, <=40 chars, actor/action from documentation/analytics/methodology.md). Exit 0 clean, 1 hits, 3 not a repo.
exec "$(dirname "$0")/lib/run.sh" scan "$@"
