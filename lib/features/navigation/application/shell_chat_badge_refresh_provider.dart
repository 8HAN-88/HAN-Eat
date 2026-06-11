import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Инкремент — обновить badge непрочитанных на табе «Чаты» в shell.
final shellChatBadgeRefreshProvider = StateProvider<int>((ref) => 0);
