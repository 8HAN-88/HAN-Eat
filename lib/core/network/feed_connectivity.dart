import '../../services/feed_sync_service.dart';

/// Онлайн по данным [FeedSyncService] (connectivity_plus). Если сервис не инициализирован — считаем онлайн.
bool feedDeviceOnline() {
  try {
    return FeedSyncService.instance.isOnline.value;
  } catch (_) {
    return true;
  }
}
