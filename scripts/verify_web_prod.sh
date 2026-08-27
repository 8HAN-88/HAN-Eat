#!/usr/bin/env bash
# Smoke-проверка production web (haneat.app) перед релизом / после деплоя.
set -euo pipefail

WEB_ORIGIN="${WEB_ORIGIN:-https://haneat.app}"
API_BASE="${API_BASE:-https://api.haneat.app}"
fail=0
warn=0

check() { echo "  OK $1"; }
warn_msg() { echo "  WARN $1"; warn=$((warn + 1)); }
fail_msg() { echo "  FAIL $1"; fail=$((fail + 1)); }

echo "== Web production smoke ($WEB_ORIGIN) =="

echo ""
echo "-- HTTP / SSL --"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$WEB_ORIGIN/")"
if [[ "$code" == "200" ]]; then
  check "GET / → $code"
else
  fail_msg "GET / → $code (ожидали 200)"
fi

www_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://www.haneat.app/")"
if [[ "$www_code" == "200" ]]; then
  check "GET www → $www_code"
else
  warn_msg "www.haneat.app → $www_code"
fi

echo ""
echo "-- PWA assets --"
for path in manifest.json flutter_service_worker.js flutter_bootstrap.js icons/Icon-192.png icons/Icon-maskable-512.png; do
  c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$WEB_ORIGIN/$path")"
  if [[ "$c" == "200" ]]; then
    check "$path"
  else
    fail_msg "$path → $c"
  fi
done

if curl -sf --max-time 10 "$WEB_ORIGIN/manifest.json" | python3 -c "
import json,sys
m=json.load(sys.stdin)
assert m.get('display')=='standalone', m.get('display')
assert m.get('start_url'), 'no start_url'
su = str(m.get('start_url') or '')
assert su.startswith('/app/'), su
print('standalone manifest OK', su)
" 2>/dev/null; then
  check "manifest display=standalone"
else
  fail_msg "manifest.json невалиден"
fi

echo ""
echo "-- Digital Asset Links (TWA) --"
if curl -sf --max-time 10 "$WEB_ORIGIN/.well-known/assetlinks.json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert isinstance(d,list) and d, 'empty'
t=d[0]['target']
assert t.get('package_name')=='com.haneat.app', t
assert t.get('sha256_cert_fingerprints'), 'no sha256'
print('assetlinks OK')
" 2>/dev/null; then
  check "assetlinks.json"
else
  warn_msg "assetlinks.json — нужен для TWA в Play"
fi

echo ""
echo "-- Legal --"
for path in privacy terms; do
  c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$WEB_ORIGIN/$path")"
  if [[ "$c" == "200" ]]; then
    check "/$path"
  else
    fail_msg "/$path → $c"
  fi
done

echo ""
echo "-- version.json --"
if curl -sf --max-time 10 "$WEB_ORIGIN/version.json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('build_number'), d
print('build', d['build_number'])
" 2>/dev/null; then
  check "version.json"
else
  fail_msg "version.json"
fi

echo ""
echo "-- API reachability --"
if curl -sf --max-time 10 "$API_BASE/health" | grep -q '"status"'; then
  check "$API_BASE/health"
else
  fail_msg "$API_BASE/health"
fi

echo ""
echo "-- SPA routing (refresh) --"
for path in /login /invite; do
  c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$WEB_ORIGIN$path")"
  if [[ "$c" == "200" ]]; then
    check "SPA $path"
  else
    fail_msg "SPA $path → $c (nginx try_files?)"
  fi
done

echo ""
if [[ "$fail" -gt 0 ]]; then
  echo "Итог: FAIL ($fail ошибок, $warn предупреждений)"
  exit 1
fi
echo "Итог: OK ($warn предупреждений)"
echo ""
echo "Ручной smoke: docs/LAUNCH_SMOKE.md → Web"
echo "  - Google Sign-In (OAuth origin $WEB_ORIGIN)"
echo "  - Установка на рабочий стол (Chrome / Safari)"
