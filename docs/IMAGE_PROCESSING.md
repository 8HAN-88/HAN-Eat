# Обработка изображений - Документация

## Обзор

Система автоматически оптимизирует загруженные изображения, создавая несколько размеров и форматов для оптимальной загрузки на разных устройствах и соединениях.

## Архитектура

### Компоненты

1. **ImageProcessing Model** - модель для отслеживания статуса обработки
2. **ImageProcessingService** - сервис для обработки изображений с использованием Pillow (PIL)
3. **ImageQueueService** - сервис для управления очередью задач (Redis)
4. **ImageWorker** - worker процесс для обработки задач из очереди

### Процесс обработки

1. Пользователь загружает изображение через presigned URL в S3
2. После загрузки вызывается `/api/v1/media/complete` с `file_type=image`
3. Создается запись `ImageProcessing` в БД со статусом `pending`
4. Задача добавляется в очередь Redis (`image:processing:queue`)
5. ImageWorker получает задачу из очереди и обрабатывает:
   - Скачивает исходный файл из S3
   - Обрабатывает изображение:
     - Автоматический поворот по EXIF
     - Создание нескольких размеров (large, medium, thumbnail)
     - Генерация WebP версий для лучшего сжатия
   - Загружает результаты обратно в S3
6. Статус обновляется на `completed` с URL всех вариантов

## Варианты размеров

### Large
- Максимальный размер: 1920x1920px
- Формат: JPEG (quality 85)
- Использование: Полноэкранный просмотр, детальные изображения

### Medium
- Максимальный размер: 800x800px
- Формат: JPEG (quality 85)
- Использование: Карточки постов, лента

### Thumbnail
- Размер: 320x320px (квадратное)
- Формат: JPEG (quality 85)
- Использование: Миниатюры, превью

### WebP версии
- Те же размеры, но в формате WebP
- Качество: 85
- Использование: Для браузеров с поддержкой WebP (меньший размер файла)

## Оптимизации

### Автоматические
- **EXIF поворот** - автоматический поворот по метаданным камеры
- **Progressive JPEG** - для лучшей загрузки (показывается постепенно)
- **Оптимизация** - сжатие без потери качества
- **Сохранение пропорций** - изображения не искажаются

### Форматы
- **JPEG** - основной формат, совместим со всеми устройствами
- **WebP** - современный формат с лучшим сжатием (30-50% меньше размер)

## API Endpoints

### POST /api/v1/media/complete

Завершение загрузки изображения и запуск обработки.

**Request:**
```json
{
  "upload_id": "uuid",
  "file_key": "uploads/user_123/2025/01/uuid.jpg",
  "file_type": "image"
}
```

**Response:**
```json
{
  "status": "processing",
  "url": "https://cdn.../uuid.jpg",
  "processing": true,
  "upload_id": "uuid",
  "processing_id": 123
}
```

### GET /api/v1/media/status/{upload_id}

Получить статус обработки изображения.

**Response:**
```json
{
  "status": "processing" | "completed" | "failed",
  "progress": 0.0-100.0,
  "url": "https://cdn.../uuid_large.jpg",
  "large_url": "https://cdn.../uuid_large.jpg",
  "medium_url": "https://cdn.../uuid_medium.jpg",
  "thumbnail_url": "https://cdn.../uuid_thumbnail.jpg",
  "large_webp_url": "https://cdn.../uuid_large.webp",
  "medium_webp_url": "https://cdn.../uuid_medium.webp",
  "thumbnail_webp_url": "https://cdn.../uuid_thumbnail.webp",
  "error_message": null
}
```

## Запуск Worker

### Требования

1. **Pillow (PIL)** должен быть установлен
   ```bash
   pip install Pillow
   ```

2. **Redis** должен быть запущен

3. **PostgreSQL** должен быть доступен

### Запуск

```bash
cd backend
python -m app.workers.image_worker
```

Или через systemd/supervisor для продакшена:

```ini
[program:image_worker]
command=python -m app.workers.image_worker
directory=/path/to/backend
autostart=true
autorestart=true
stderr_logfile=/var/log/image_worker.err.log
stdout_logfile=/var/log/image_worker.out.log
```

## Использование в Frontend

### Выбор размера

```dart
// Для миниатюр
String imageUrl = image.thumbnailUrl ?? image.mediumUrl ?? image.largeUrl;

// Для карточек постов
String imageUrl = image.mediumUrl ?? image.largeUrl;

// Для полноэкранного просмотра
String imageUrl = image.largeUrl;

// WebP версия (если поддерживается)
String imageUrl = image.thumbnailWebpUrl ?? image.thumbnailUrl;
```

### Проверка поддержки WebP

```dart
bool supportsWebP = await _checkWebPSupport();
String imageUrl = supportsWebP 
    ? (image.thumbnailWebpUrl ?? image.thumbnailUrl)
    : image.thumbnailUrl;
```

## Производительность

### Размеры файлов (примерно)

- **Original**: 5-10 MB (зависит от камеры)
- **Large (1920px)**: 500-800 KB
- **Medium (800px)**: 100-200 KB
- **Thumbnail (320px)**: 20-40 KB
- **WebP версии**: на 30-50% меньше

### Время обработки

- Thumbnail: ~0.5-1 секунда
- Medium: ~1-2 секунды
- Large: ~2-3 секунды
- WebP версии: +0.5-1 секунда каждая

**Итого**: ~5-8 секунд на изображение

## Мониторинг

### Статусы обработки

- `pending` - задача в очереди, ожидает обработки
- `processing` - изображение обрабатывается
- `completed` - обработка завершена успешно
- `failed` - произошла ошибка (см. `error_message`)

### Redis ключи

- `image:processing:queue` - очередь задач (List)
- `image:status:{upload_id}` - статус обработки (TTL: 1 час)

## Обработка ошибок

При ошибке обработки:
1. Статус обновляется на `failed`
2. `error_message` содержит описание ошибки
3. Запись остается в БД для анализа

## Масштабирование

Для обработки больших объемов изображений:

1. **Запустить несколько workers** на разных серверах
2. **Использовать RabbitMQ** вместо Redis для более надежной очереди
3. **Добавить приоритеты** для обработки
4. **Мониторинг** через Prometheus/Grafana

## Оптимизация

- Использовать GPU для обработки (если доступно)
- Параллельная обработка нескольких изображений
- Кэширование результатов для одинаковых исходных файлов
- Предварительная обработка популярных размеров

