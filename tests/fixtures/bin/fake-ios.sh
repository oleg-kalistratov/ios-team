#!/bin/bash
# Fake ios-dev ios.sh for hooks.test.sh: every command succeeds unless FAKE_IOS_FAIL names it.
[ "${FAKE_IOS_FAIL:-}" = "$1" ] && { echo "error: fake $1 failure"; exit 1; }
echo "fake $1 ok"
