#!/usr/bin/env bash
# Сборка Trusted Web Activity (TWA) для Google Play.
#
# Требования: Node.js, @bubblewrap/cli, JDK, Android SDK
#
#   ./scripts/build_twa_release.sh setup   # один раз: конфиг + generate project
#   ./scripts/build_twa_release.sh build   # APK/AAB для Play
#   ./scripts/build_twa_release.sh update  # подтянуть изменения с haneat.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TWA_DIR="${ROOT}/android-twa"
MANIFEST_URL="${TWA_MANIFEST_URL:-https://haneat.app/manifest.json}"
KEYSTORE="${ROOT}/android/upload-keystore.jks"
JDK_PATH="${BUBBLEWRAP_JDK:-$HOME/Desktop/Android Studio.app/Contents/jbr/Contents/Home}"
ANDROID_SDK="${BUBBLEWRAP_ANDROID_SDK:-$HOME/Library/Android/sdk}"

ensure_bubblewrap() {
  if command -v bubblewrap >/dev/null 2>&1; then
    return 0
  fi
  echo "Установка @bubblewrap/cli..."
  npm install -g @bubblewrap/cli
}

read_key_password() {
  if [[ -f "${ROOT}/android/key.properties" ]]; then
    grep '^storePassword=' "${ROOT}/android/key.properties" | cut -d= -f2-
  fi
}

export_bubblewrap_secrets() {
  local pass
  pass="$(read_key_password)"
  if [[ -n "$pass" ]]; then
    export BUBBLEWRAP_KEYSTORE_PASSWORD="$pass"
    export BUBBLEWRAP_KEY_PASSWORD="$pass"
  fi
}

configure_bubblewrap() {
  ensure_bubblewrap
  if [[ ! -d "$JDK_PATH" ]]; then
    echo "JDK не найден: $JDK_PATH"
    echo "Задайте BUBBLEWRAP_JDK=/path/to/jdk"
    exit 1
  fi
  if [[ ! -d "$ANDROID_SDK" ]]; then
    echo "Android SDK не найден: $ANDROID_SDK"
    exit 1
  fi
  mkdir -p "${HOME}/.bubblewrap"
  cat > "${HOME}/.bubblewrap/config.json" << EOF
{
  "jdkPath": "${JDK_PATH}",
  "androidSdkPath": "${ANDROID_SDK}"
}
EOF
}

cmd="${1:-build}"

case "$cmd" in
  setup)
    configure_bubblewrap
    if [[ ! -f "$TWA_DIR/twa-manifest.json" ]]; then
      echo "Нет $TWA_DIR/twa-manifest.json"
      exit 1
    fi
    cd "$TWA_DIR"
    bubblewrap update \
      --manifest="$TWA_DIR/twa-manifest.json" \
      --appVersionName="1.0.0" \
      --skipVersionUpgrade
    echo ""
    echo "✓ TWA Android project сгенерирован в $TWA_DIR"
    echo "  Сборка: ./scripts/build_twa_release.sh build"
    ;;

  init)
    echo "init интерактивен — используйте готовый twa-manifest.json:"
    echo "  ./scripts/build_twa_release.sh setup"
    exit 1
    ;;

  build)
    configure_bubblewrap
    if [[ ! -f "$TWA_DIR/twa-manifest.json" ]]; then
      echo "Сначала: ./scripts/build_twa_release.sh setup"
      exit 1
    fi
    if [[ ! -f "$TWA_DIR/app/build.gradle" ]]; then
      echo "Проект не сгенерирован — запускаю setup..."
      "$0" setup
    fi

    cd "$TWA_DIR"
    chmod +x ./gradlew
    export JAVA_HOME="$JDK_PATH"

    echo "== Gradle bundleRelease (TWA) =="
    ./gradlew bundleRelease

    echo ""
    echo "✓ TWA AAB:"
    find "$TWA_DIR/app/build/outputs" -name '*.aab' -print 2>/dev/null
    echo ""
    echo "Play Console → Internal testing → загрузите AAB"
    ;;

  update)
    configure_bubblewrap
    cd "$TWA_DIR"
    bubblewrap update \
      --manifest="$TWA_DIR/twa-manifest.json" \
      --appVersionName="1.0.0" \
      --skipVersionUpgrade
    ;;

  *)
    echo "Usage: $0 {setup|build|update}"
    exit 1
    ;;
esac
