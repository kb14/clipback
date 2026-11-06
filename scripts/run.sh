#!/bin/bash
# Rebuilds Clipback, quits any running copy and launches the fresh build.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh
pkill -x Clipback 2>/dev/null || true
sleep 0.3
open build/Clipback.app
