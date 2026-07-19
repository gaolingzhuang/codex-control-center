#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_APP="$ROOT_DIR/outputs/Codex Control Center.app"
TARGET_APP="/Applications/Codex Control Center.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT_DIR/scripts/build-app.sh"
fi

# Stop the already-loaded executable and widget extension before replacing the
# bundle. Otherwise macOS keeps displaying the previous version from memory.
/usr/bin/pkill -x "Codex Control Center" 2>/dev/null || true
/usr/bin/pkill -x "CodexControlCenterWidget" 2>/dev/null || true

/bin/rm -rf "$TARGET_APP"
ditto --noextattr --noqtn "$SOURCE_APP" "$TARGET_APP"
xattr -cr "$TARGET_APP"
codesign --force --sign - --entitlements "$ROOT_DIR/WidgetExtension/CodexControlCenterWidget.entitlements" "$TARGET_APP/Contents/PlugIns/CodexControlCenterWidget.appex"
codesign --force --sign - "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$TARGET_APP"
open "$TARGET_APP"
echo "已安装并启动：$TARGET_APP"
