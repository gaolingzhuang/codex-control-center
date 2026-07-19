#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_APP="$ROOT_DIR/outputs/Codex Control Center.app"
OUTPUT_ZIP="$ROOT_DIR/outputs/Codex-Control-Center-macOS.zip"
DERIVED_DIR="$ROOT_DIR/work/xcode-derived"
BUILT_APP_DIR="$DERIVED_DIR/Build/Products/Release/Codex Control Center.app"
STAGING_DIR="$(mktemp -d "/private/tmp/codex-control-center-stage.XXXXXX")"
APP_DIR="$STAGING_DIR/Codex Control Center.app"
WIDGET_DIR="$APP_DIR/Contents/PlugIns/CodexControlCenterWidget.appex"

cleanup() {
  /bin/rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$ROOT_DIR/outputs"
mkdir -p "$DERIVED_DIR"
build_project() {
  DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
  xcodebuild \
    -quiet \
    -project "$ROOT_DIR/CodexControlCenter.xcodeproj" \
    -scheme CodexControlCenter \
    -configuration Release \
    -derivedDataPath "$DERIVED_DIR" \
    build \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO
}

# Reuse the local derived-data directory so Xcode does not need to rebuild the
# complete macOS SDK module cache on every package. Retry once for transient
# dependency-scan failures without discarding the successful cached work.
build_project || build_project

ditto --noextattr --noqtn "$BUILT_APP_DIR" "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --force --sign - --entitlements "$ROOT_DIR/WidgetExtension/CodexControlCenterWidget.entitlements" "$WIDGET_DIR"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

/bin/rm -rf "$OUTPUT_APP"
ditto --noextattr --noqtn "$APP_DIR" "$OUTPUT_APP"
/bin/rm -f "$OUTPUT_ZIP"
# Package from the verified temporary bundle. Cloud-backed Documents folders
# can attach Finder metadata immediately after copying, which should not be
# folded back into a code signature.
ditto -c -k --keepParent "$APP_DIR" "$OUTPUT_ZIP"

echo "$OUTPUT_APP"
echo "$OUTPUT_ZIP"
