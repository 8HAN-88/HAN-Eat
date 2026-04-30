// Helper для работы с File на разных платформах
// Используем условный импорт для поддержки веб и мобильных платформ
export 'file_helper_stub.dart' if (dart.library.io) 'file_helper_io.dart';

