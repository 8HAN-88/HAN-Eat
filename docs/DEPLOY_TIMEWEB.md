# Деплой на Timeweb Cloud (Amsterdam)

## Быстрый способ (web-консоль Timeweb)

1. Timeweb → **haneat-api-01** → **Консоль**
2. Войти: `root` + пароль из вкладки **Доступ**
3. Вставить **одну команду**:

```bash
curl -fsSL https://raw.githubusercontent.com/8HAN-88/HAN-Eat/main/scripts/deploy_timeweb_server.sh | bash
```

> Если скрипта ещё нет на GitHub — скопируйте содержимое `scripts/deploy_timeweb_server.sh` вручную или с Mac:
> ```bash
> scp scripts/deploy_timeweb_server.sh root@89.19.216.60:/root/
> ssh root@89.19.216.60 'bash /root/deploy_timeweb_server.sh'
> ```

4. После скрипта — заполнить секреты:

```bash
nano /root/HAN-Eat/backend/.env
systemctl restart haneat-api
```

5. DNS у регистратора домена `haneat.app`:
   - `A api` → **IP сервера** (сейчас `89.19.216.60`)
   - Проверка с Mac: `dig +short api.haneat.app` должен вернуть IP сервера, не сторонний (например `15.197.x`)
   - Cloudflare (если используете): `A api → IP сервера` (**DNS only**, серое облако)

6. SSL:

```bash
certbot --nginx -d api.haneat.app
```

7. Проверка с Mac:

```bash
./scripts/verify_launch.sh https://api.haneat.app
```

## SSH с Mac

```bash
ssh -i ~/.ssh/haneat_timeweb root@YOUR_SERVER_IP
```

Скрипт автоматически добавляет ваш публичный ключ в `authorized_keys`.

## Firebase credentials

```bash
# с Mac
scp -i ~/.ssh/haneat_timeweb firebase-adminsdk.json root@IP:/etc/haneat/firebase-credentials.json
```

## Обновление

### Без Mac — только браузер Timeweb (рекомендуется, если SSH с Mac не работает)

**Где:** [Timeweb Cloud](https://timeweb.cloud) → сервер **haneat-api-01** → вкладка **Консоль**  
**Логин:** `root` + пароль из вкладки **Доступ** на карточке сервера.

#### Шаг 0 — код должен попасть на сервер

Выберите один способ:

| Способ | Когда использовать |
|--------|-------------------|
| **A. git pull** | Изменения уже **запушены** в GitHub `8HAN-88/HAN-Eat` |
| **B. архив backend** | Код ещё **не на GitHub** или нужно залить локальные правки без push |

**A — код на GitHub** (push можно сделать с Mac/Windows — это GitHub, не сервер):

```bash
git add backend/
git commit -m "Backend: chat folders and filters"
git push origin main
```

**B — архив без push:** на любом ПК, где есть репозиторий:

```bash
bash scripts/pack_backend_for_timeweb.sh
# создаст /tmp/haneat-backend.tgz
```

Загрузите `haneat-backend.tgz` на сервер через **SFTP / файловый менеджер Timeweb** в `/root/`.

#### Шаг 1 — деплой (вставить в консоль Timeweb)

**Если код на GitHub (способ A):**

```bash
cd /root/HAN-Eat && git pull origin main && bash scripts/deploy_on_server_console.sh
```

**Если загрузили архив (способ B):**

```bash
cd /root/HAN-Eat && tar xzf /root/haneat-backend.tgz && bash scripts/deploy_on_server_console.sh
```

Скрипт сам: `pip install`, `alembic upgrade head`, перезапуск `haneat-api` и video-worker, проверка `/health`.

#### Шаг 2 — проверка в той же консоли

```bash
curl -sf https://api.haneat.app/health && echo OK
curl -s -o /dev/null -w 'folders HTTP %{http_code}\n' \
  -H 'Authorization: Bearer ВАШ_ТОКЕН' \
  https://api.haneat.app/api/v1/chats/folders
```

Ожидаем: `health` → JSON с `"status":"ok"`, folders → **200** (не 404).

Проверка миграций:

```bash
cd /root/HAN-Eat/backend && source venv/bin/activate && alembic current
# должно быть не ниже 054_chat_folder_filters
```

#### Если что-то пошло не так

```bash
journalctl -u haneat-api -n 80 --no-pager
systemctl status haneat-api
```

Починить SSH (чтобы потом можно было с Mac): в консоли Timeweb:

```bash
bash /root/HAN-Eat/scripts/fix_ssh_timeweb_console.sh
```

---

### С Mac (если SSH работает)

```bash
bash scripts/update_production_timeweb.sh
```

Скрипт: `rsync` backend → сервер, `alembic upgrade head`, `systemctl restart haneat-api`, проверка `https://api.haneat.app`.

### На сервере вручную (без deploy-скрипта)

```bash
cd /root/HAN-Eat && git pull
cd backend && source venv/bin/activate && pip install -r requirements.txt
alembic upgrade head
python3 scripts/create_all_test_accounts.py
systemctl restart haneat-api
```

Актуальные миграции чатов: `053_chat_folders`, `054_chat_folder_filters`.

### Проверка, что новый API на проде

```bash
./scripts/verify_launch.sh https://api.haneat.app
# или вручную: в ответе GET /channels/{id} должны быть поля membership_status, can_view_posts
```

Приложение всегда смотрит на `https://api.haneat.app` (см. `.env` → `HANEAT_API_BASE`). Локальный `127.0.0.1:5001` — только для разработки.
