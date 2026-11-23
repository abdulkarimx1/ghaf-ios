#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SIMULATOR_ID="${GHAF_SIMULATOR_ID:-40FD1630-A7FD-44B7-A896-C40FEC49B267}"
DERIVED_DATA="${GHAF_DERIVED_DATA:-/tmp/ghaf-check-derived}"

xcodegen generate
xcodebuild -project Ghaf.xcodeproj -scheme Ghaf -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Ghaf.xcodeproj -scheme Ghaf -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build
swift test --package-path Packages/GhafCore
xcodebuild -project Ghaf.xcodeproj -scheme Ghaf -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO -only-testing:GhafSnapshotTests test
xcodebuild -project Ghaf.xcodeproj -scheme Ghaf -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO -only-testing:GhafUITests/GhafTabSpeedTests/testTabCycleAndScrolling test
