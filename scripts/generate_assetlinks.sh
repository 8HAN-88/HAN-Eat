#!/usr/bin/env bash
# Генерирует web/.well-known/assetlinks.json для Trusted Web Activity (Google Play).
#
# Использование:
#   ./scripts/generate_assetlinks.sh
#   ./scripts/generate_assetlinks.sh /path/to/upload-keystore.jks upload
#
# После генерации — деплой: ./scripts/build_web_release.sh && bash scripts/deploy_web_timeweb.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYSTORE="${1:-${ROOT}/android/upload-keystore.jks}"
ALIAS="${2:-upload}"
PACKAGE="${HAN_PACKAGE:-com.haneat.app}"
OUT="${ROOT}/web/.well-known/assetlinks.json"
STORE_PASS=""
KEY_PASS=""

if [[ -f "${ROOT}/android/key.properties" ]]; then
  STORE_PASS="$(grep '^storePassword=' "${ROOT}/android/key.properties" | cut -d= -f2-)"
  KEY_PASS="$(grep '^keyPassword=' "${ROOT}/android/key.properties" | cut -d= -f2-)"
  KEYSTORE_REL="$(grep '^storeFile=' "${ROOT}/android/key.properties" | cut -d= -f2-)"
  if [[ -n "$KEYSTORE_REL" ]]; then
    if [[ "$KEYSTORE_REL" == /* ]]; then
      KEYSTORE="$KEYSTORE_REL"
    elif [[ -f "${ROOT}/android/${KEYSTORE_REL}" ]]; then
      KEYSTORE="${ROOT}/android/${KEYSTORE_REL}"
    elif [[ -f "${ROOT}/android/app/${KEYSTORE_REL}" ]]; then
      KEYSTORE="${ROOT}/android/app/${KEYSTORE_REL}"
    fi
  fi
fi

KEYTOOL="${KEYTOOL:-}"
if [[ -z "$KEYTOOL" ]]; then
  for candidate in \
    "$(command -v keytool 2>/dev/null || true)" \
    "$HOME/Desktop/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      KEYTOOL="$candidate"
      break
    fi
  done
fi
if [[ -z "$KEYTOOL" ]]; then
  echo "keytool не найден — установите JDK или Android Studio"
  exit 1
fi

if [[ ! -f "$KEYSTORE" ]]; then
  echo "Keystore не найден: $KEYSTORE"
  exit 1
fi

echo "== SHA-256 fingerprints ($ALIAS) =="

if [[ -n "${STORE_PASS:-}" ]]; then
  SHA256="$("$KEYTOOL" -list -v -keystore "$KEYSTORE" -alias "$ALIAS" \
    -storepass "$STORE_PASS" -keypass "${KEY_PASS:-$STORE_PASS}" 2>/dev/null \
    | grep 'SHA256:' | head -1 | sed 's/.*SHA256: //' | tr -d ':' | tr '[:upper:]' '[:lower:]')"
else
  SHA256="$("$KEYTOOL" -list -v -keystore "$KEYSTORE" -alias "$ALIAS" 2>/dev/null \
    | grep 'SHA256:' | head -1 | sed 's/.*SHA256: //' | tr -d ':' | tr '[:upper:]' '[:lower:]')"
fi

if [[ -z "$SHA256" ]]; then
  echo "SHA256 не извлечён — проверьте key.properties или запустите keytool вручную"
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" << EOF
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "${PACKAGE}",
      "sha256_cert_fingerprints": [
        "${SHA256}"
      ]
    }
  }
]
EOF

echo ""
echo "✓ Записано: $OUT"
echo "  package: $PACKAGE"
echo "  sha256:  $SHA256"
echo ""
echo "Проверка после деплоя:"
echo "  curl -s https://haneat.app/.well-known/assetlinks.json | python3 -m json.tool"
