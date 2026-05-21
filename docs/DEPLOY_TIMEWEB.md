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

5. Cloudflare: `A api → IP сервера` (**DNS only**, серое облако)

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

```bash
cd /root/HAN-Eat && git pull
cd backend && source venv/bin/activate && pip install -r requirements.txt
alembic upgrade head
systemctl restart haneat-api
```
