#!/usr/bin/env bash
# Открыть проект в Xcode для первой установки на iPhone.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/ios_fix_team.sh 2>/dev/null || true
open ios/Runner.xcworkspace
echo ""
echo "В Xcode:"
echo "  Settings (⌘,) → Accounts → Apple ID (airat8446@gmail.com)"
echo "  Runner → Signing → Team: Airat Hadiev (94NCHYWGB8) → ▶ Run на iPhone (USB)"
