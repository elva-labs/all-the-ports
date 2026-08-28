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

# xcodebuild (not `swift build`) is required here: the Bundle.module accessor
# SwiftPM generates for `swift build` only looks in the app bundle ROOT and in
# the build machine's absolute .build path, so dependency resource bundles
# (e.g. KeyboardShortcuts localizations) trap at runtime on any other machine
# — and codesign rejects bundles placed at the app root ("unsealed contents").
# Xcode's generated accessor searches Contents/Resources, where we copy them.
if [ -z "${DEVELOPER_DIR:-}" ] \
  && ! xcode-select -p | grep -q "Xcode.app" \
  && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

PRODUCTS=".build/xcodebuild/Build/Products/Release"
xcodebuild -scheme AllThePorts -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath .build/xcodebuild \
  CODE_SIGNING_ALLOWED=NO build

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$PRODUCTS/AllThePorts" "$APP/Contents/MacOS/AllThePorts"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# SwiftPM dependencies with resources emit .bundle directories next to the
# binary; the Xcode-generated Bundle.module accessor finds them in
# Contents/Resources and traps if they're missing.
for bundle in "$PRODUCTS"/*.bundle; do
  [ -d "$bundle" ] || continue
  cp -R "$bundle" "$APP/Contents/Resources/"
done
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
