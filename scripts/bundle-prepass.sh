#!/bin/bash
# bundle-prepass.sh <diagnostic bundle dir> [--prev <older bundle dir>] — read-only facts for the coordinator:
# inventory, date coverage (+COVERAGE MISMATCH), identical files vs the previous bundle, endpoint census, levels,
# [Area] tags, socket job timeline, analytics events, errors. UUIDs, emails, phones, long hex, ids >= 6 digits and
# name/email/user/device values are masked. Prints Markdown to stdout. Exit 64 on usage.
exec "$(dirname "$0")/lib/run.sh" prepass "$@"
