#!/usr/bin/env bash
# Builds and runs the headless parse/snapshot benchmark in scripts/bench.
#
# It compiles the real terminal sources directly rather than linking the app
# target: the app is a GUI executable with a Metal renderer and a PTY, none of
# which a throughput measurement should have to start. Optimisation settings
# match the release build, so the numbers are the ones a shipped Kuddo gets.
set -euo pipefail

cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/kuddo-bench"

swiftc -O -whole-module-optimization -package-name Kuddo -framework SwiftUI -o "$out" \
    scripts/bench/main.swift \
    $(find Sources/KuddoCore -name '*.swift' | sort)

exec "$out" "$@"
