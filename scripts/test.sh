#!/bin/sh
# Run syntax checks, lint, and every regression test from the repository root.
set -eu
cd "$(dirname "$0")/.."

if command -v lua5.1 >/dev/null 2>&1; then
    luac5.1 -p Estimator.lua Checks.lua DistanceToTarget.lua Options.lua tools/*.lua tests/*.lua
    run() { lua5.1 "$@"; }
else
    echo "lua5.1 not found; running tests with fengari (no syntax check)"
    run() { npm exec --yes --package=fengari-node-cli -- fengari "$@"; }
fi

if command -v luacheck >/dev/null 2>&1; then
    luacheck Estimator.lua Checks.lua DistanceToTarget.lua Options.lua tools tests
else
    echo "luacheck not found; skipping lint"
fi

for test in tests/*.lua; do
    echo "$test"
    run "$test"
done
