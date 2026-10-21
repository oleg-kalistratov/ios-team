#!/bin/bash
# generate.sh <worktree> — the full Tuist generate for a checkout, the way gate.sh's build expects it: `ios.sh generate` from the
# ios-dev plugin (tuist install + tuist generate --no-open) under the heavy lease. ios.sh records a fingerprint of the file set and
# the manifests after every generate it runs and regenerates on the next build when that fingerprint is missing or differs; a raw
# `tuist generate` leaves no fingerprint, so every later gate paid a second generate (measured: 100–150 s of a 30–50 s warm app
# build). Always the full generate — `tuist generate <Target>` drops SPM dependencies. Exit: ios.sh's code; 3 infra (no ios.sh,
# not a checkout); 64 usage.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/project.sh"
[ -n "${1:-}" ] && [ "${1#-}" = "$1" ] && [ $# = 1 ] || { sed -n 2,7p "$0" >&2; exit 64; }
wt=$(cd "$1" 2>/dev/null && pwd) || { echo "generate.sh: нет такой папки: $1" >&2; exit 3; }
[ -f "$wt/Project.swift" ] || { echo "generate.sh: $wt — не checkout проекта (нет Project.swift)" >&2; exit 3; }
pat=$(proj ios_dev_plugin_path "$HOME/.claude/plugins/cache/*/ios-dev/*/skills/build-run/scripts/ios.sh")
ios=${IOS_SH:-$(compgen -G "${pat/#\~/$HOME}" 2>/dev/null | sort -V | tail -1)}
[ -n "$ios" ] || ios=$(ls -t "$HOME/Library/Application Support/Claude"/*/*/*/rpm/*/skills/build-run/scripts/ios.sh 2>/dev/null | head -1)
[ -n "$ios" ] && [ -f "$ios" ] || { echo "generate.sh: ios.sh из плагина ios-dev не найден — поставь ios-dev или задай IOS_SH" >&2; exit 3; }
cd "$wt" && IOS_PROJECT_ROOT="$wt" exec "$HERE/lease.sh" run heavy -- bash "$ios" generate
