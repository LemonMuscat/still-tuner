#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -module-cache-path "$PWD/build/ModuleCache" -O Sources/PitchDetector.swift Sources/PitchReading.swift Tests/main.swift -o build/PitchTests
build/PitchTests
