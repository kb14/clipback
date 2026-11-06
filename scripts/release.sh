#!/bin/bash
# Builds a release of Clipback for other Macs: signed with a Developer ID, notarized by Apple, the ticket stapled,
# and packaged as dist/Clipback-<version>.dmg. Opening it on another Mac then shows no Gatekeeper warning.
#
# Needs a "Developer ID Application" certificate in the keychain (or CLIPBACK_SIGN_ID), and notary credentials:
#   - locally, a keychain profile made once with
#       xcrun notarytool store-credentials clipback-notary --key <AuthKey.p8> --key-id <id> --issuer <issuer>
#     (NOTARY_PROFILE picks another name), or
#   - in CI, an App Store Connect API key: NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER.
#
# --skip-notarize signs and packages without Apple's check, to try the steps before the account exists. It falls
# back to the Apple Development certificate, and the DMG it makes is not for sharing.
# ARCHS="arm64 x86_64" makes a universal build; the default is Apple Silicon only.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=1
[ "${1:-}" = "--skip-notarize" ] && NOTARIZE=0

VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)}"
APP="build/Clipback.app"
DIST="dist"
DMG="$DIST/Clipback-$VERSION.dmg"
ENTITLEMENTS="Resources/Clipback.entitlements"

identity() { security find-identity -v -p codesigning | awk -v kind="$1" '$0 ~ kind {print $2; exit}'; }
SIGN_ID="${CLIPBACK_SIGN_ID:-$(identity "Developer ID Application")}"
if [ -z "$SIGN_ID" ]; then
  if [ "$NOTARIZE" = 1 ]; then
    echo "No Developer ID Application certificate in the keychain. Set CLIPBACK_SIGN_ID, or use --skip-notarize." >&2
    exit 1
  fi
  SIGN_ID="$(identity "Apple Development")"
  echo "Dry run: signing with the Apple Development certificate. Don't share this build." >&2
fi

notary() {
  if [ -n "${NOTARY_KEY_PATH:-}" ]; then
    xcrun notarytool "$@" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER"
  else
    xcrun notarytool "$@" --keychain-profile "${NOTARY_PROFILE:-clipback-notary}"
  fi
}

submit() {
  echo "Sending $1 to Apple for notarization (usually a few minutes)…"
  notary submit "$1" --wait --timeout 30m
  xcrun stapler staple "$2"
}

# 1. Build, then sign the app with the hardened runtime and a secure timestamp, which notarization requires.
CONFIG=Release CLIPBACK_SIGN_ID="$SIGN_ID" ./scripts/build.sh
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

# 2. Notarize the app itself and staple its ticket, so it opens without a network check once copied.
rm -rf "$DIST" && mkdir -p "$DIST"
if [ "$NOTARIZE" = 1 ]; then
  ditto -c -k --keepParent "$APP" "$DIST/Clipback.zip"
  submit "$DIST/Clipback.zip" "$APP"
  rm "$DIST/Clipback.zip"
fi

# 3. A DMG with the app and a shortcut to Applications, signed, then notarized and stapled as well.
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Clipback" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
[ "$NOTARIZE" = 1 ] && submit "$DMG" "$DMG"

# 4. Check what Gatekeeper will say on someone else's Mac.
if [ "$NOTARIZE" = 1 ]; then
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  xcrun stapler validate "$DMG"
fi
shasum -a 256 "$DMG"
# The DMG holds the app now. A second Clipback.app lying in build/ would show up in Spotlight and Launch Services.
rm -rf "$APP"
echo "Release ready: $DMG"
