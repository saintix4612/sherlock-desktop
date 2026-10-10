#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
APP="$BUILD_DIR/Sherlock Desktop.app"
ARCH_DIR="$BUILD_DIR/release-architectures"
mkdir -p "$ARCH_DIR"
ARCH=arm64 bash "$REPO_ROOT/Scripts/build.sh"
cp "$APP/Contents/MacOS/SherlockDesktop" "$ARCH_DIR/SherlockDesktop-arm64"
ARCH=x86_64 bash "$REPO_ROOT/Scripts/build.sh"
cp "$APP/Contents/MacOS/SherlockDesktop" "$ARCH_DIR/SherlockDesktop-x86_64"
xcrun lipo -create "$ARCH_DIR/SherlockDesktop-arm64" "$ARCH_DIR/SherlockDesktop-x86_64" \
  -output "$APP/Contents/MacOS/SherlockDesktop"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
bash "$REPO_ROOT/Tests/test.sh"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/Sherlock-Desktop-macOS-universal.zip"
shasum -a 256 "$BUILD_DIR/Sherlock-Desktop-macOS-universal.zip"
echo "Release archive: $BUILD_DIR/Sherlock-Desktop-macOS-universal.zip"
