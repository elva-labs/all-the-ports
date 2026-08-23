#!/bin/sh
# Assembles "all the ports.app" from the SwiftPM release build.
# Usage: scripts/make-app.sh [output-dir]   (default: ./build)
set -eu

cd "$(dirname "$0")/.."
OUT="${1:-build}"
APP="$OUT/all the ports.app"

# SwiftUI macros need the full Xcode toolchain; if only the Command Line
# Tools are selected but Xcode is installed, point at Xcode for this build.
if [ -z "${DEVELOPER_DIR:-}" ] \
  && ! xcode-select -p | grep -q "Xcode.app" \
  && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/AllThePorts" "$APP/Contents/MacOS/AllThePorts"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature so the bundle runs locally. Release builds for other
# people should be signed with a Developer ID and notarized instead.
codesign --force --sign - "$APP"

echo "Built: $APP"
