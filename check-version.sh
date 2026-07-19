#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
EXPECTED_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
PROJECT_FILE="$ROOT_DIR/CodexControlCenter.xcodeproj/project.pbxproj"

if [[ -z "$EXPECTED_VERSION" ]]; then
  echo "VERSION is empty" >&2
  exit 1
fi

PROJECT_VERSIONS="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PROJECT_FILE" | sort -u)"
if [[ "$PROJECT_VERSIONS" != "$EXPECTED_VERSION" ]]; then
  echo "VERSION ($EXPECTED_VERSION) does not match Xcode MARKETING_VERSION values:" >&2
  echo "$PROJECT_VERSIONS" >&2
  exit 1
fi

echo "Version $EXPECTED_VERSION is consistent."
