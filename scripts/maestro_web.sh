#!/usr/bin/env bash
# Headless Maestro smoke against production PWA.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.maestro/bin:${PATH}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export PATH="${JAVA_HOME}/bin:${PATH}"
export MAESTRO_CLI_NO_ANALYTICS="${MAESTRO_CLI_NO_ANALYTICS:-1}"
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
BASE_URL="${MAESTRO_BASE_URL:-https://haneat.app}"

if ! command -v maestro >/dev/null; then
  echo "Maestro CLI not found. Install: curl -fsSL https://get.maestro.mobile.dev | bash"
  exit 1
fi

OUT="${MAESTRO_OUTPUT:-${ROOT}/build/maestro}"
mkdir -p "$OUT"

echo "== Maestro $(maestro --version) =="
echo "Base: $BASE_URL"
echo "Flows: ${ROOT}/.maestro"
echo

maestro test "${ROOT}/.maestro" \
  --headless \
  --screen-size=390x844 \
  --format JUNIT \
  --output "${OUT}/junit.xml" \
  --debug-output "${OUT}/debug" \
  "$@"
