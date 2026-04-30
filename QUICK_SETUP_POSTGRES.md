# 🚀 Быстрая установка PostgreSQL (без Docker)

## 📥 Шаг 1: Скачать и установить PostgreSQL

1. **Скачайте PostgreSQL 15:**
   - 🔗 **Прямая ссылка:** https://www.enterprisedb.com/downloads/postgres-postgresql-downloads
   - Выберите версию для Windows x86-64

2. **Установите:**
   - Запустите установщик
   - **ВАЖНО:** Запомните пароль для пользователя `postgres`!
   - Порт: оставьте **5432**
   - Все остальное - по умолчанию

---

## 🗄️ Шаг 2: Создать базу данных

После установки откройте PowerShell и выполните:

```powershell
# Подключиться к PostgreSQL
psql -U postgres

# Введите пароль, который указали при установке
# Затем выполните:
CREATE DATABASE haneat;
\q
```

---

## ⚙️ Шаг 3: Настроить backend/.env

Создайте файл `backend/.env` с таким содержимым:

```env
SECRET_KEY=BB2hzXR8k5ctP7nu5lzjYFW8dcVcYCC9qyo9jik1B3g
DATABASE_URL=postgresql://postgres:ВАШ_ПАРОЛЬ@localhost:5432/haneat
REDIS_URL=redis://localhost:6379/0
APP_ENV=development
DEBUG=true
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080,http://localhost:5000,http://127.0.0.1:5000
```

**⚠️ Замените `ВАШ_ПАРОЛЬ` на пароль, который указали при установке PostgreSQL!**

---

## ✅ Шаг 4: Проверить работу

```powershell
# Проверить подключение
psql -U postgres -d haneat

# Если подключилось - всё работает!
# Выйти: \q
```

---

## 🚀 Шаг 5: Запустить backend

```powershell
cd backend
python run.py
```

Backend должен подключиться к базе данных!

---

## 🆘 Если что-то не работает

### PostgreSQL не запускается:
1. Откройте "Службы" (Win + R → `services.msc`)
2. Найдите `postgresql-x64-15` (или вашу версию)
3. Запустите службу

### Забыли пароль:
См. подробную инструкцию в `INSTALL_POSTGRESQL_LOCAL.md`

---

## 📚 Подробная инструкция

См. файл: `INSTALL_POSTGRESQL_LOCAL.md`

---

**Готово! PostgreSQL работает локально! 🎉**


