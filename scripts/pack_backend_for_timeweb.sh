#!/usr/bin/env bash
# Упаковать backend для загрузки на сервер без SSH (через панель Timeweb / SFTP).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/haneat-backend.tgz}"

cd "$ROOT"
tar czf "$OUT" \
  --exclude='backend/.env' \
  --exclude='backend/venv' \
  --exclude='backend/uploads' \
  --exclude='backend/__pycache__' \
  --exclude='backend/**/__pycache__' \
  --exclude='backend/dev.db' \
  backend/

ls -lh "$OUT"
echo ""
echo "Архив: $OUT"
echo ""
echo "Дальше (если SSH с Mac не работает):"
echo "  1) Timeweb → сервер → загрузите $OUT на сервер (SFTP/файлы), например в /root/"
echo "  2) Timeweb → Консоль:"
echo "       cd /root/HAN-Eat && tar xzf /root/haneat-backend.tgz"
echo "       bash /root/HAN-Eat/scripts/deploy_on_server_console.sh"
echo ""
echo "Или почините SSH: bash scripts/fix_ssh_timeweb_console.sh (вставить в консоль Timeweb)"
