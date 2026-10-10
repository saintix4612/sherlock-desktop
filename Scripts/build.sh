#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
APP="$BUILD_DIR/Sherlock Desktop.app"
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Install Apple's Command Line Tools with: xcode-select --install" >&2
  exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/AppIcon.iconset"
xcrun swiftc -parse-as-library -target "$ARCH-apple-macosx14.0" \
  "$REPO_ROOT/SherlockDesktop.swift" -o "$APP/Contents/MacOS/SherlockDesktop" \
  -framework SwiftUI -framework AppKit
cp "$REPO_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
xcrun swift "$REPO_ROOT/Scripts/draw-icon.swift" "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$REPO_ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$REPO_ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
