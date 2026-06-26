#!/usr/bin/env bash
# Local/CI release gate for critical HAN Eat flows.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Flutter analyze =="
flutter analyze

echo ""
echo "== Flutter tests =="
flutter test --no-fatal-warnings

echo ""
echo "== Backend tests =="
PYTHONPATH=backend python -m pytest backend/tests

if [[ -d build/web ]]; then
  echo ""
  echo "== Web build artifact check =="
  HANEAT_API_BASE="${HANEAT_API_BASE:-https://haneat.app}" \
    python3 scripts/check_web_build_artifacts.py
fi

echo ""
echo "Release quality gate passed."
