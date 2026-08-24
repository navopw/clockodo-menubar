#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}/.."
APP_DIR="$ROOT_DIR/dist/Clockodo Menubar.app"
APP_VERSION="${APP_VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build --package-path "$ROOT_DIR" -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/ClockodoMenubar" "$APP_DIR/Contents/MacOS/ClockodoMenubar"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
lipo -archs "$APP_DIR/Contents/MacOS/ClockodoMenubar"
print "Built $APP_DIR (version $APP_VERSION, build $BUILD_NUMBER)"
