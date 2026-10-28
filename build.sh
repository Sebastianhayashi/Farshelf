#!/bin/bash
# Builds build.noindex/Farshelf.app, signed with the hardened runtime (as releases are, so dev builds behave the same).
#   ./build.sh                       signed with the identity named in .sign-id (one line, gitignored), so macOS keeps
#                                    folder permissions across rebuilds; ad-hoc without it (macOS then asks again
#                                    after each build)
#   SIGN_ID="<identity>" ./build.sh  this identity instead
#   RELEASE=1 SIGN_ID="Developer ID Application: …" ./build.sh   plus the secure timestamp notarization needs
#                                    (scripts/release.sh does that, then notarizes and makes the DMG)
# There's no install step: run it from build.noindex (see scripts/dev-run.sh).
# These replace Info.plist values: BUNDLE_ID, VERSION, BUILD_NUMBER.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Farshelf"
# ".noindex" keeps Spotlight (and the Apps list) from showing this staging copy.
APP="build.noindex/$APP_NAME.app"

# Use full Xcode's toolchain when it's installed, even if xcode-select points at the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# llama.cpp, the embedding runtime, linked into the helper (only rebuilt when its tag or patch changes).
scripts/build-llama.sh

# Both executables: the app, and the `digup` CLI, which the app runs as its indexing helper and query encoder.
swift build -c release --product DigUpApp
swift build -c release --product digup
BIN_DIR="$(swift build -c release --show-bin-path)"

# The Farshelf app icon (Resources/AppIcon/README.md): macOS 26 draws AppIcon.icon (compiled into
# Assets.car), older macOS the .icns. Without the former, macOS 26 shows the icon shrunk inside a gray square.
ICON="Resources/AppIcon.icns"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
# The binary is DigUpApp in SwiftPM (it can't share a name with the `digup` CLI on a case-insensitive disk).
cp "$BIN_DIR/DigUpApp" "$APP/Contents/MacOS/$APP_NAME"
# The indexing helper lives in Helpers/: the app starts it as Contents/Helpers/digup (Engine.swift).
cp "$BIN_DIR/digup" "$APP/Contents/Helpers/digup"
cp Resources/Info.plist "$APP/Contents/Info.plist"
xcrun actool --compile "$APP/Contents/Resources" --platform macosx --target-device mac --minimum-deployment-target 14.0 \
  --app-icon AppIcon --output-partial-info-plist "$(mktemp -d)/AppIcon.plist" --enable-on-demand-resources NO \
  --development-region en "$PWD/Resources/AppIcon/AppIcon.icon" > /dev/null
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Acknowledgements.txt "$APP/Contents/Resources/Acknowledgements.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/AppIcon/tray.png Resources/AppIcon/tray-dim.png Resources/AppIcon/tray-paused.png "$APP/Contents/Resources/"   # the menubar's logo

PLIST="$APP/Contents/Info.plist"
[[ -n "${BUNDLE_ID:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
[[ -n "${VERSION:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
[[ -n "${BUILD_NUMBER:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

# Nested code first, then the bundle. The helper needs no entitlements: llama.cpp compiles its Metal shaders at run
# time through Metal's own compiler service, which the hardened runtime allows (checked 2026-10-08). The app's one
# entitlement lets it ask QuickTime Player to open a recording at a moment.
IDENTITY="${SIGN_ID:-$( [[ -f .sign-id ]] && head -1 .sign-id || echo - )}"
TIMESTAMP=$([[ "${RELEASE:-}" == 1 ]] && echo --timestamp || echo --timestamp=none)
codesign --force --sign "$IDENTITY" --options runtime $TIMESTAMP "$APP/Contents/Helpers/digup"
codesign --force --sign "$IDENTITY" --options runtime $TIMESTAMP --entitlements Resources/DigUp.entitlements "$APP"
echo "Signed $([[ "$IDENTITY" == - ]] && echo ad-hoc || echo "with \"$IDENTITY\"") (hardened runtime)"
echo "Built $APP"
