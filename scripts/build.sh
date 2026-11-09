#!/bin/bash
# Builds Clipback with Xcode's build tool and wraps the binary into build/Clipback.app.
# CONFIG=Debug (default, includes developer tools like snapshots) or CONFIG=Release (what install.sh uses).
#
# xcodebuild rather than `swift build`: Xcode's generated resource lookup finds package resources in
# Contents/Resources, so the app doesn't depend on the .build folder at runtime.
#
# ARCHS="arm64 x86_64" builds a universal app; the default is Apple Silicon only.
#
# Signs with a stable identity so macOS permissions survive rebuilds (see SIGN_ID below);
# an ad-hoc signature would force Accessibility / Screen Recording to be re-granted after each build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-Debug}"
ARCHS="${ARCHS:-arm64}"
if [ "$ARCHS" = "arm64" ]; then DESTINATION='platform=macOS,arch=arm64'; else DESTINATION='generic/platform=macOS'; fi
xcodebuild -scheme Clipback -configuration "$CONFIG" -destination "$DESTINATION" ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath .build/xcode -quiet build
BIN_DIR=".build/xcode/Build/Products/$CONFIG"

APP="build/Clipback.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Clipback" "$APP/Contents/MacOS/Clipback"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Package resource bundles (KeyboardShortcuts ships its localized strings this way).
for bundle in "$BIN_DIR"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Sparkle, for in-app updates. ditto keeps the framework's symlinks. Its XPC services are only for sandboxed apps,
# so they're left out, as Sparkle's docs suggest. The binary looks for it in Contents/Frameworks.
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
otool -l "$APP/Contents/MacOS/Clipback" | grep -q "@executable_path/../Frameworks" ||
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Clipback"

# Prefer an explicit identity, then a Developer ID (the identity releases use, so the installed copy and a
# downloaded one are the same app to macOS and keep the same permissions), then Apple Development, then ad-hoc.
# Always with the hardened runtime and the entitlements, so every build behaves like a released one.
# scripts/release.sh re-signs with a secure timestamp.
identity() { security find-identity -v -p codesigning | awk -v kind="$1" '$0 ~ kind {print $2; exit}'; }
DEFAULT_ID="$(identity "Developer ID Application")"
DEFAULT_ID="${DEFAULT_ID:-$(identity "Apple Development")}"
SIGN_ID="${CLIPBACK_SIGN_ID:-${DEFAULT_ID:--}}"
./scripts/sign.sh "$APP" "$SIGN_ID"
echo "Built $APP ($CONFIG, signed with: $SIGN_ID)"
