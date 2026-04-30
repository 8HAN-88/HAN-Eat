# Обработка видео - Документация

## Обзор

Система обработки видео автоматически транскодирует загруженные видео в несколько форматов для оптимального воспроизведения на разных устройствах и соединениях.

## Архитектура

### Компоненты

1. **VideoProcessing Model** - модель для отслеживания статуса обработки
2. **VideoTranscodingService** - сервис для транскодинга с использованием FFmpeg
3. **VideoQueueService** - сервис для управления очередью задач (Redis)
4. **VideoWorker** - worker процесс для обработки задач из очереди

### Процесс обработки

1. Пользователь загружает видео через presigned URL в S3
2. После загрузки вызывается `/api/v1/media/complete` с `file_type=video`
3. Создается запись `VideoProcessing` в БД со статусом `pending`
4. Задача добавляется в очередь Redis (`video:processing:queue`)
5. VideoWorker получает задачу из очереди и обрабатывает:
   - Скачивает исходный файл из S3
   - Транскодирует в форматы:
     - MP4 720p (для качественного воспроизведения)
     - MP4 480p (для медленных соединений)
     - HLS (для адаптивного стриминга)
   - Генерирует thumbnail (кадр на 1 секунде)
   - Загружает результаты обратно в S3
6. Статус обновляется на `completed` с URL всех форматов

## Форматы вывода

### MP4 720p
- Разрешение: 1280x720
- Битрейт видео: 2500k
- Битрейт аудио: 128k
- Кодек: H.264 (libx264) + AAC

### MP4 480p
- Разрешение: 854x480
- Битрейт видео: 1000k
- Битрейт аудио: 128k
- Кодек: H.264 (libx264) + AAC

### HLS (Adaptive Streaming)
- Мастер-плейлист с тремя вариантами качества:
  - 720p (2500k)
  - 480p (1000k)
  - 360p (500k)
- Сегменты по 10 секунд
- Формат: `.m3u8` плейлисты + `.ts` сегменты

### Thumbnail
- Кадр на 1 секунде видео
- Формат: JPEG
- Ширина: 640px (высота автоматически)

## API Endpoints

### POST /api/v1/media/complete

Завершение загрузки видео и запуск обработки.

**Request:**
```json
{
  "upload_id": "uuid",
  "file_key": "uploads/user_123/2025/01/uuid.mp4",
  "file_type": "video"
}
```

**Response:**
```json
{
  "status": "processing",
  "url": "https://cdn.../uuid.mp4",
  "processing": true,
  "upload_id": "uuid",
  "processing_id": 123
}
```

### GET /api/v1/media/status/{upload_id}

Получить статус обработки видео.

**Response:**
```json
{
  "status": "processing" | "completed" | "failed",
  "progress": 0.0-100.0,
  "url": "https://cdn.../uuid_720p.mp4",
  "mp4_720p_url": "https://cdn.../uuid_720p.mp4",
  "mp4_480p_url": "https://cdn.../uuid_480p.mp4",
  "hls_url": "https://cdn.../uuid_hls/playlist.m3u8",
  "thumbnail_url": "https://cdn.../uuid_thumb.jpg",
  "error_message": null
}
```

## Запуск Worker

### Требования

1. **FFmpeg** должен быть установлен и доступен в PATH
   - Linux: `sudo apt-get install ffmpeg`
   - macOS: `brew install ffmpeg`
   - Windows: скачать с https://ffmpeg.org/download.html

2. **Redis** должен быть запущен

3. **PostgreSQL** должен быть доступен

### Запуск

```bash
cd backend
python -m app.workers.video_worker
```

Или через systemd/supervisor для продакшена:

```ini
[program:video_worker]
command=python -m app.workers.video_worker
directory=/path/to/backend
autostart=true
autorestart=true
stderr_logfile=/var/log/video_worker.err.log
stdout_logfile=/var/log/video_worker.out.log
```

### Переменные окружения

- `FFMPEG_PATH` - путь к FFmpeg (опционально, если в PATH)
- `DATABASE_URL` - URL базы данных
- `REDIS_URL` - URL Redis
- `S3_*` - настройки S3

## Мониторинг

### Статусы обработки

- `pending` - задача в очереди, ожидает обработки
- `processing` - видео обрабатывается
- `completed` - обработка завершена успешно
- `failed` - произошла ошибка (см. `error_message`)

### Redis ключи

- `video:processing:queue` - очередь задач (List)
- `video:status:{upload_id}` - статус обработки (TTL: 1 час)

## Обработка ошибок

При ошибке обработки:
1. Статус обновляется на `failed`
2. `error_message` содержит описание ошибки
3. Запись остается в БД для анализа

## Масштабирование

Для обработки больших объемов видео:

1. **Запустить несколько workers** на разных серверах
2. **Использовать RabbitMQ** вместо Redis для более надежной очереди
3. **Добавить приоритеты** для обработки (VIP пользователи, срочные задачи)
4. **Мониторинг** через Prometheus/Grafana

## Оптимизация

- Использовать GPU для транскодинга (NVENC, VideoToolbox)
- Параллельная обработка нескольких видео
- Кэширование результатов для одинаковых исходных файлов
- Предварительная обработка популярных форматов

