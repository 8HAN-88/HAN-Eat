#!/usr/bin/env bash
# Чеклист перед сборкой TestFlight / Play Internal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
warn=0

check() { echo "  OK $1"; }
warn_msg() { echo "  WARN $1"; warn=1; }
fail_msg() { echo "  FAIL $1"; fail=1; }

echo "== Pre-TestFlight / release check =="

echo ""
echo "-- Bundle ID --"
if grep -q 'com.haneat.app' ios/Runner.xcodeproj/project.pbxproj 2>/dev/null; then
  check "iOS bundle com.haneat.app"
else
  fail_msg "iOS bundle ID"
fi
if grep -q 'com.haneat.app' android/app/build.gradle* android/app/google-services.json 2>/dev/null; then
  check "Android package com.haneat.app"
else
  fail_msg "Android package"
fi

echo ""
echo "-- Version (pubspec.yaml) --"
if grep -qE '^version:' pubspec.yaml; then
  check "version: $(grep '^version:' pubspec.yaml)"
else
  warn_msg "Добавьте version: 1.0.0+1 в pubspec.yaml для App Store"
fi

echo ""
echo "-- Android signing --"
if [[ -f android/key.properties ]]; then
  check "android/key.properties"
else
  warn_msg "Нет android/key.properties — только debug-сборка"
fi

echo ""
echo "-- Client fonts (offline) --"
if [[ -f assets/fonts/Manrope-VariableFont.ttf ]]; then
  check "Manrope in assets/fonts"
else
  fail_msg "Скачайте Manrope: curl -L …/Manrope%5Bwght%5D.ttf → assets/fonts/Manrope-VariableFont.ttf"
fi

echo ""
echo "-- Google Sign-In --"
if python3 scripts/verify_google_signin.py; then
  :
else
  fail_msg "Google Sign-In (см. docs/GOOGLE_SIGNIN_SETUP.md)"
fi

echo ""
echo "-- Legal pages --"
if [[ -f static/legal/privacy.html && -f static/legal/terms.html ]]; then
  check "static/legal HTML"
else
  fail_msg "Нет static/legal/*.html"
fi

echo ""
echo "-- API smoke (optional) --"
if curl -sf http://127.0.0.1:5001/health >/dev/null 2>&1; then
  if ./scripts/verify_launch.sh http://127.0.0.1:5001; then
    check "launch verify"
  else
    fail_msg "launch verify"
  fi
else
  warn_msg "Backend не запущен — пропуск smoke (запустите uvicorn на :5001)"
fi

echo ""
if [[ $fail -ne 0 ]]; then
  echo "== NOT READY — исправьте FAIL =="
  exit 1
fi
if [[ $warn -ne 0 ]]; then
  echo "== READY with warnings =="
  exit 0
fi
echo "== READY for release build =="
echo ""
echo "iOS:     ./scripts/build_ios_release.sh https://api.haneat.app"
echo "Android: ./scripts/build_android_release.sh https://api.haneat.app"
echo "Smoke:   docs/STABILITY.md + ./scripts/smoke_launch.sh https://api.haneat.app"
echo "См.:    docs/TESTFLIGHT.md"
