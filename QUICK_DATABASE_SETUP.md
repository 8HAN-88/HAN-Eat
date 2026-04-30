# ⚡ Быстрая настройка PostgreSQL и Redis

## 🎯 Самый простой способ - Docker

### Шаг 1: Установите Docker Desktop

🔗 **Скачать:** https://www.docker.com/products/docker-desktop

Установите и запустите Docker Desktop.

### Шаг 2: Запустите базы данных

В корне проекта уже есть файл `docker-compose.yml`. Просто запустите:

```cmd
docker-compose up -d
```

Это запустит:
- ✅ PostgreSQL на порту 5432
- ✅ Redis на порту 6379

### Шаг 3: Создайте базу данных

```cmd
docker exec -it haneat-postgres psql -U postgres -c "CREATE DATABASE haneat;"
```

### Шаг 4: Укажите в backend/.env

```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/haneat
REDIS_URL=redis://localhost:6379/0
```

**Готово!** 🎉

---

## 🔍 Проверка

### Проверить, что всё работает:

```cmd
# Проверить PostgreSQL
docker exec -it haneat-postgres psql -U postgres -c "SELECT version();"

# Проверить Redis
docker exec -it haneat-redis redis-cli ping
# Должно вернуть: PONG
```

---

## 🛑 Остановка

```cmd
docker-compose down
```

---

## 📝 Если Docker не подходит

См. подробную инструкцию: `DATABASE_REDIS_SETUP.md`

Там описаны:
- Локальная установка PostgreSQL
- Локальная установка Redis
- Облачные сервисы

