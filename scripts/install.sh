#!/bin/bash
# Builds an optimised Clipback and installs it as /Applications/Clipback.app, the copy to use day to day.
# Your clips live in ~/Clipback, not in the app, so reinstalling never touches them.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Release ./scripts/build.sh
pkill -x Clipback 2>/dev/null || true
sleep 0.5
rm -rf /Applications/Clipback.app
# Moved, not copied, so Spotlight and Launch Services only ever see the installed copy.
mv build/Clipback.app /Applications/Clipback.app
open /Applications/Clipback.app
echo "Installed /Applications/Clipback.app"
