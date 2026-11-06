#!/bin/bash
# Developer tool: builds Clipback, renders every review-window screen to PNGs in build/snapshots, then
# relaunches Clipback normally. Lets the UI be checked without clicking through by hand.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh > /dev/null
pkill -x Clipback 2>/dev/null || true
sleep 0.3
rm -rf build/snapshots
build/Clipback.app/Contents/MacOS/Clipback --ui-snapshots "$PWD/build/snapshots" 2>/dev/null | grep "scroll view" || true
# Made-up clips of every kind, in a throwaway vault, to check rendering beyond what the real vault has.
FIXTURES="$(mktemp -d)/vault"
build/Clipback.app/Contents/MacOS/Clipback --vault "$FIXTURES" --fixtures --ui-snapshots "$PWD/build/snapshots" >/dev/null 2>&1 || true
rm -rf "$(dirname "$FIXTURES")"
# The same screens in light mode, whatever the saved Appearance setting or macOS is using.
build/Clipback.app/Contents/MacOS/Clipback --appearance light --ui-snapshots "$PWD/build/snapshots/light" >/dev/null 2>&1 || true
ls build/snapshots
# Put back the copy used day to day; the development build only existed for the snapshots.
rm -rf build/Clipback.app
if [ -d /Applications/Clipback.app ]; then open /Applications/Clipback.app; fi
