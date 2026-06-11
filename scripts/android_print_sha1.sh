#!/usr/bin/env bash
# SHA-1 для Firebase / Google Sign-In (debug и release, если key.properties настроен).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/android"

# macOS: /usr/bin/keytool — заглушка без Java; приоритет — JBR Android Studio.
AS_KEYTOOL="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
if [[ -x "$AS_KEYTOOL" ]]; then
  KEYTOOL="$AS_KEYTOOL"
elif command -v keytool >/dev/null 2>&1 && keytool -help >/dev/null 2>&1; then
  KEYTOOL="keytool"
else
  echo "FAIL: keytool не найден. Установите Android Studio или: brew install openjdk@17"
  exit 1
fi

echo "=== Debug keystore (keytool: $KEYTOOL) ==="
DEBUG_KS="$HOME/.android/debug.keystore"
if [[ ! -f "$DEBUG_KS" ]]; then
  echo "  Файл $DEBUG_KS не найден."
  echo "  Создайте его (каждая команда — отдельной строкой):"
  echo "    mkdir -p ~/.android"
  echo "    \"$KEYTOOL\" -genkey -v -keystore ~/.android/debug.keystore -storepass android \\"
  echo "      -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 \\"
  echo "      -dname \"CN=Android Debug,O=Android,C=US\""
  echo "  Или: flutter run -d <android-устройство>"
else
  "$KEYTOOL" -list -v -keystore "$DEBUG_KS" \
    -alias androiddebugkey -storepass android -keypass android 2>/dev/null | grep -E 'SHA1:|SHA256:' || {
    echo "  keytool не вывел отпечатки"
  }
fi

if [[ -f "$ANDROID_DIR/key.properties" ]]; then
  echo ""
  echo "=== Release keystore (из key.properties) ==="
  # shellcheck disable=SC1091
  source <(grep -E '^(storeFile|storePassword|keyAlias|keyPassword)=' "$ANDROID_DIR/key.properties" | sed 's/^/export /')
  STORE="${storeFile/#~\//$HOME/}"
  "$KEYTOOL" -list -v -keystore "$STORE" -alias "$keyAlias" \
    -storepass "$storePassword" -keypass "$keyPassword" 2>/dev/null | grep -E 'SHA1:|SHA256:' || true
else
  echo ""
  echo "Release: создайте android/key.properties из key.properties.example"
fi
