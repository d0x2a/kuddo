#!/usr/bin/env bash
# Builds and runs the PTY benchmark in scripts/ptybench: `cat` of a large file
# through a real pseudo-terminal, read once by nothing and once by Kuddo's
# parser and grid the way Session reads.
#
# Like bench.sh, it compiles the real terminal sources directly rather than
# linking the app target, with the release build's optimisation settings.
# Pass a path to cat that file instead of the generated 100 MB log.
set -euo pipefail

cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/kuddo-ptybench"

swiftc -O -whole-module-optimization -package-name Kuddo -framework SwiftUI -o "$out" \
    scripts/ptybench/main.swift \
    $(find Sources/KuddoCore -name '*.swift' | sort)

exec "$out" "$@"
