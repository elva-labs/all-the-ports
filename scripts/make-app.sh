#!/bin/sh
# Assembles "all the ports.app" from the SwiftPM release build.
#
# Usage: scripts/make-app.sh [output-dir]        (default: ./build)
#
# Environment:
#   SIGN_IDENTITY  codesign identity. Default "-" (ad-hoc, local use only).
#                  Release builds set this to "Developer ID Application: …",
#                  which also enables the hardened runtime + secure timestamp
#                  that notarization requires.
#   VERSION        overrides CFBundleShortVersionString (e.g. from a git tag).
#   BUILD_NUMBER   overrides CFBundleVersion (e.g. the CI run number).
set -eu

cd "$(dirname "$0")/.."
OUT="${1:-build}"
APP="$OUT/all the ports.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

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

if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
  # Ad-hoc: fine for the local machine, not distributable.
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

codesign --verify --strict "$APP"
echo "Built: $APP (signed: $SIGN_IDENTITY)"
