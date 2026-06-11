#!/usr/bin/env bash
# Вставьте в Timeweb → сервер haneat-api-01 → Консоль (терминал в браузере).
# Цель: починить SSH с Mac и проверить sshd.
set -euo pipefail

PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIR7s+y4H6czF/oOBpOW5bvd1LgCtPqoNEDBk/lloASU haneat-timeweb'

echo "== 1/5 sshd status =="
systemctl status ssh --no-pager 2>/dev/null || systemctl status sshd --no-pager 2>/dev/null || true

echo ""
echo "== 2/5 authorized_keys =="
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
if ! grep -qF 'haneat-timeweb' /root/.ssh/authorized_keys; then
  echo "$PUBKEY" >> /root/.ssh/authorized_keys
  echo "Added SSH key"
else
  echo "SSH key already present"
fi

echo ""
echo "== 3/5 fail2ban (разбанить IP если заблокирован) =="
if command -v fail2ban-client >/dev/null 2>&1; then
  fail2ban-client status sshd 2>/dev/null || fail2ban-client status 2>/dev/null || true
  fail2ban-client unban --all 2>/dev/null || true
  echo "fail2ban: unban --all done (if any)"
else
  echo "fail2ban not installed"
fi

echo ""
echo "== 4/5 sshd config sanity =="
if grep -q '^PermitRootLogin no' /etc/ssh/sshd_config 2>/dev/null; then
  sed -i 's/^PermitRootLogin no/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  echo "Set PermitRootLogin prohibit-password"
fi
if ! grep -q '^PasswordAuthentication' /etc/ssh/sshd_config 2>/dev/null; then
  echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
fi
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
sleep 1

echo ""
echo "== 5/5 listeners =="
ss -tlnp | grep ':22 ' || netstat -tlnp 2>/dev/null | grep ':22 ' || true

echo ""
echo "DONE. С Mac проверьте:"
echo "  ssh -i ~/.ssh/haneat_timeweb root@89.19.216.60 'echo ok'"
echo ""
echo "Если снова Connection closed:"
echo "  Timeweb → Сервер → Сеть / Firewall → разрешите входящий TCP 22"
echo "  Timeweb → SSH-ключи → добавьте тот же публичный ключ"
