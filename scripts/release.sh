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
# It also writes dist/appcast.xml, the update feed Sparkle reads from the latest GitHub Release, signed with the
# Sparkle EdDSA key: from the login keychain locally (made once with generate_keys), or SPARKLE_KEY_FILE in CI.
# RELEASE_TAG (default v<version>) is the tag the DMG will be downloaded from.
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

# 0. Sparkle only offers an update whose CFBundleVersion is higher than the installed one, so a release that
#    forgets to raise it would never reach anyone.
BUILD="$(plutil -extract CFBundleVersion raw Resources/Info.plist)"
if [ "$NOTARIZE" = 1 ]; then
  PUBLISHED="$(curl -fsSL https://github.com/kb14/clipback/releases/latest/download/appcast.xml 2>/dev/null |
    sed -n 's/.*<sparkle:version>\([0-9]*\)<.*/\1/p' | head -1 || true)"
  if [ -n "$PUBLISHED" ] && [ "$BUILD" -le "$PUBLISHED" ]; then
    echo "CFBundleVersion is $BUILD but the latest release already has $PUBLISHED. Raise it in Resources/Info.plist." >&2
    exit 1
  fi
fi

# 1. Build, then sign the app with the hardened runtime and a secure timestamp, which notarization requires.
CONFIG=Release CLIPBACK_SIGN_ID="$SIGN_ID" ./scripts/build.sh
./scripts/sign.sh "$APP" "$SIGN_ID" --timestamp
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

# 4. The update feed: one item for this DMG, with its EdDSA signature and this version's CHANGELOG section as
#    release notes. It's attached to the GitHub Release next to the DMG.
if [ "$NOTARIZE" = 1 ]; then
  SPARKLE_BIN=".build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin"
  TAG="${RELEASE_TAG:-v$VERSION}"
  NOTES="$DIST/Clipback-$VERSION.md"
  awk -v v="$VERSION" '/^## /{inside = ($2 == v); next} inside' CHANGELOG.md > "$NOTES"
  KEY=()
  [ -n "${SPARKLE_KEY_FILE:-}" ] && KEY=(--ed-key-file "$SPARKLE_KEY_FILE")
  "$SPARKLE_BIN/generate_appcast" ${KEY[@]+"${KEY[@]}"} --embed-release-notes \
    --download-url-prefix "https://github.com/kb14/clipback/releases/download/$TAG/" \
    --link "https://github.com/kb14/clipback" -o "$DIST/appcast.xml" "$DIST"
  rm "$NOTES"
fi

# 5. Check what Gatekeeper will say on someone else's Mac.
if [ "$NOTARIZE" = 1 ]; then
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  xcrun stapler validate "$DMG"
fi
shasum -a 256 "$DMG"
# The DMG holds the app now. A second Clipback.app lying in build/ would show up in Spotlight and Launch Services.
rm -rf "$APP"
echo "Release ready: $DMG"
