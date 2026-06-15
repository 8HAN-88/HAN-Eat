/// Предпочтение качества видео в рилсах и ленте.
enum VideoQualityPreference {
  /// HLS (адаптивный битрейт) или быстрый старт с 480p с догрузкой качества.
  auto,

  /// Не выше 480p — экономия трафика.
  dataSaver,

  /// Фиксированно 720p, если доступно.
  hd720,

  /// Фиксированно 1080p, если доступно.
  hd1080,

  /// Максимум: 1080p / оригинал / лучший доступный вариант.
  max,
}

extension VideoQualityPreferenceX on VideoQualityPreference {
  String get storageValue => name;

  String get labelRu => switch (this) {
        VideoQualityPreference.auto => 'Авто',
        VideoQualityPreference.dataSaver => 'Экономия трафика',
        VideoQualityPreference.hd720 => '720p HD',
        VideoQualityPreference.hd1080 => '1080p Full HD',
        VideoQualityPreference.max => 'Максимальное',
      };

  String get subtitleRu => switch (this) {
        VideoQualityPreference.auto =>
          'Быстрый старт, качество подстраивается под сеть',
        VideoQualityPreference.dataSaver => 'До 480p, минимум трафика',
        VideoQualityPreference.hd720 => 'Баланс качества и скорости',
        VideoQualityPreference.hd1080 => 'Высокое качество при хорошей сети',
        VideoQualityPreference.max => 'Лучшее доступное качество',
      };

  static VideoQualityPreference fromString(String? raw) {
    switch (raw) {
      case 'dataSaver':
        return VideoQualityPreference.dataSaver;
      case 'hd720':
        return VideoQualityPreference.hd720;
      case 'hd1080':
        return VideoQualityPreference.hd1080;
      case 'max':
        return VideoQualityPreference.max;
      case 'auto':
      default:
        return VideoQualityPreference.auto;
    }
  }
}
