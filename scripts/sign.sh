#!/bin/bash
# Signs Clipback.app and the Sparkle framework inside it, inside out, the way Sparkle documents (never --deep,
# which would hand the app's entitlements to Sparkle's helpers). Called by build.sh and release.sh.
#
#   scripts/sign.sh <app> <identity> [--timestamp]
#
# <identity> is a certificate hash or name, or "-" for ad hoc. Ad hoc builds skip the hardened runtime: its library
# validation only loads frameworks signed by the same team, and an ad hoc signature has no team.
# --timestamp asks Apple for a secure timestamp, which notarization needs; everyday builds skip it to work offline.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?Usage: $0 <app> <identity> [--timestamp]}"
ID="${2:?Usage: $0 <app> <identity> [--timestamp]}"
TIMESTAMP="--timestamp=none"
[ "${3:-}" = "--timestamp" ] && TIMESTAMP="--timestamp"
RUNTIME=(--options runtime)
[ "$ID" = "-" ] && RUNTIME=()

sign() { codesign --force ${RUNTIME[@]+"${RUNTIME[@]}"} "$TIMESTAMP" --sign "$ID" "$@"; }

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  sign "$SPARKLE/Versions/B/Autoupdate"
  sign "$SPARKLE/Versions/B/Updater.app"
  sign "$SPARKLE"
fi
sign --entitlements Resources/Clipback.entitlements "$APP"
