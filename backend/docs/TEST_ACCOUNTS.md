# Тестовые аккаунты HAN Eat

**Пароль для всех:** `HANtest2026!`

Создать / обновить в БД:

```bash
cd backend
python3 scripts/create_all_test_accounts.py
```

Или по отдельности:

```bash
python3 scripts/create_test_accounts.py      # тарифы
python3 scripts/create_test_staff_accounts.py # модераторы и админы
```

---

## Тарифы (подписки)

| Тариф   | Email                         | Что доступно                          |
|---------|-------------------------------|---------------------------------------|
| Free    | `han.test.free@haneat.dev`    | Базовый функционал, без калорий/БЖУ   |
| AI      | `han.test.ai@haneat.dev`      | H.A.N. AI, калории, AI-скан, meal plan |
| Creator | `han.test.creator@haneat.dev` | Каналы, продвижение постов            |
| Pro     | `han.test.pro@haneat.dev`     | AI + Creator                          |

Подписки выдаются на **30 дней** (`payment_provider=dev_test`).

---

## Персонал (модерация и админка)

| Роль              | Email                              | admin | moderator | Подписка |
|-------------------|------------------------------------|-------|-----------|----------|
| Модератор         | `han.staff.moderator@haneat.dev`   | —     | да        | free     |
| Модератор + AI    | `han.staff.moderator.ai@haneat.dev`| —     | да        | AI       |
| Админ             | `han.staff.admin@haneat.dev`       | да    | —         | free     |
| Админ + Модер     | `han.staff.adminmod@haneat.dev`    | да    | да        | free     |
| Админ + Pro       | `han.staff.adminpro@haneat.dev`    | да    | —         | Pro      |
| Админ+Модер+Pro   | `han.staff.adminmod.pro@haneat.dev`| да    | да        | Pro      |

### В приложении

- **Модерация** — пользователи с `is_moderator` (Настройки → Модерация).
- **Возвраты подписок** — только `is_admin`.

---

## Назначить роли существующему email

```bash
python3 scripts/grant_admin.py user@example.com
```

Модератора — через БД или повторный запуск `create_test_staff_accounts.py` с нужным email в списке `STAFF`.

---

## Production (api.haneat.app)

Скрипты нужно запустить **на сервере** с тем же `DATABASE_URL`, что у API:

```bash
ssh user@89.19.216.60
cd /path/to/HAN-Eat/backend
source venv/bin/activate   # при необходимости
python3 scripts/create_all_test_accounts.py
```

После этого войти в приложении с `https://api.haneat.app`.
