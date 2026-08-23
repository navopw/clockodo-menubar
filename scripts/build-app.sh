#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}/.."
APP_DIR="$ROOT_DIR/dist/Clockodo Menubar.app"
swift build --package-path "$ROOT_DIR" -c release
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/ClockodoMenubar" "$APP_DIR/Contents/MacOS/ClockodoMenubar"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

codesign --force --sign - "$APP_DIR"
print "Built $APP_DIR"
