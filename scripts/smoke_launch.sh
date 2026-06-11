#!/usr/bin/env bash
# Pre-launch smoke (backend должен быть запущен).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:-http://127.0.0.1:5001}"
export BASE_URL="$BASE"
python3 "$ROOT/backend/scripts/smoke_launch.py"
