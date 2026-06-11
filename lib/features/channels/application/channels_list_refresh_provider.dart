import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Увеличьте значение, чтобы [ChatsHubScreen] перезапросил каналы в inbox
/// (например после создания или удаления канала).
final channelsMainListRefreshProvider = StateProvider<int>((ref) => 0);

/// Увеличьте значение, чтобы обновить избранные каналы в [ChatsHubScreen].
final channelFavoritesRefreshProvider = StateProvider<int>((ref) => 0);
