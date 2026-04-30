# Миграции базы данных

## Создание новой миграции

```bash
alembic revision --autogenerate -m "Описание изменений"
```

## Применение миграций

```bash
# Применить все миграции
alembic upgrade head

# Применить до конкретной ревизии
alembic upgrade <revision>

# Откатить последнюю миграцию
alembic downgrade -1
```

## Просмотр истории

```bash
# Текущая версия
alembic current

# История миграций
alembic history
```

