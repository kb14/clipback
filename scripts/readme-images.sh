#!/bin/bash
# Developer tool: renders the README screenshots in docs/images from made-up clips (Debug/Showcase.swift) in a
# throwaway vault, then relaunches Clipback normally. Usage: scripts/readme-images.sh [light|dark]
set -euo pipefail
cd "$(dirname "$0")/.."
APPEARANCE="${1:-light}"

./scripts/build.sh > /dev/null
pkill -x Clipback 2>/dev/null || true
sleep 0.3
VAULT="$(mktemp -d)/vault"
build/Clipback.app/Contents/MacOS/Clipback --vault "$VAULT" --showcase --appearance "$APPEARANCE" \
    --ui-snapshots "$PWD/docs/images" >/dev/null 2>&1 || true
rm -rf "$(dirname "$VAULT")"
ls -l docs/images
# Put back the copy used day to day; the development build only existed for the screenshots.
rm -rf build/Clipback.app
if [ -d /Applications/Clipback.app ]; then open /Applications/Clipback.app; fi
