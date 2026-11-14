#!/bin/bash
# app-product.sh <worktree> [dev|prod] — prints the path of the app the last gate (or any ios.sh build) left in the worktree's Xcode
# DerivedData, when it is fresh: Build/Products/Debug-iphonesimulator/<dev_scheme|prod_scheme>.app, newer than every .swift,
# .xcstrings and .xcassets file under the worktree. The tester installs it with `xcrun simctl install <UDID> <app>` instead of
# building again: a QA build takes the one heavy slot for 5–25 minutes and waited behind the engineer's gates up to 45 minutes
# (measured on 2026-11-13: eleven QA stops in one ticket, every one «сборка ещё идёт» or «слот занят»). Exit 0 and the path;
# 1 when the app is missing or stale (reason on stderr: build first); 64 usage.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/project.sh"
wt=${1:-}; flavor=${2:-dev}
[ -n "$wt" ] && [ -d "$wt" ] || { sed -n 2,7p "$0" >&2; exit 64; }
case $flavor in dev) scheme=$(proj dev_scheme) ;; prod) scheme=$(proj prod_scheme) ;; *) sed -n 2,7p "$0" >&2; exit 64 ;; esac
ws=$(proj workspace)
[ -n "$scheme" ] && [ -n "$ws" ] || { echo "app-product: в project.md нет dev_scheme/prod_scheme или workspace" >&2; exit 1; }
wt=$(cd "$wt" && pwd -P)
dd=${IOS_DERIVED_DATA:-$("$HERE/lib/run.sh" derived-data "$wt/$ws")}
app="$dd/Build/Products/Debug-iphonesimulator/$scheme.app"
[ -d "$app" ] || { echo "app-product: нет $app — сначала сборка (gate.sh или ios.sh build --simulator)" >&2; exit 1; }
newer=$(find "$wt" \( -name .git -o -name .build -o -name Derived -o -name '*.xcodeproj' -o -name '*.xcworkspace' \) -prune -o \
  -type f \( -name '*.swift' -o -name '*.xcstrings' -o -name '*.strings' -o -name '*.json' -o -name '*.png' -o -name '*.pdf' \) -newer "$app/Info.plist" -print 2>/dev/null | head -3)
[ -z "$newer" ] || { echo "app-product: сборка старее правок: $(tr '\n' ' ' <<<"$newer") — нужна новая сборка" >&2; exit 1; }
printf '%s\n' "$app"
