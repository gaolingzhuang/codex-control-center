#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SWIFT_BUILD_DIR="$ROOT_DIR/work/swiftpm-cache"
XCODE_DERIVED_DIR="$ROOT_DIR/work/ci-derived"
MODULE_CACHE_DIR="$ROOT_DIR/work/module-cache"

mkdir -p "$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR"

"$ROOT_DIR/scripts/check-version.sh"

swift test --package-path "$ROOT_DIR" --scratch-path "$SWIFT_BUILD_DIR"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
xcodebuild \
  -quiet \
  -project "$ROOT_DIR/CodexControlCenter.xcodeproj" \
  -scheme CodexControlCenter \
  -configuration Release \
  -derivedDataPath "$XCODE_DERIVED_DIR" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

echo "All checks passed."
