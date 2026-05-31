import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Увеличьте значение, чтобы [ChannelsMainScreen] перезапросил подписки и рекомендации
/// (например после удаления канала).
final channelsMainListRefreshProvider = StateProvider<int>((ref) => 0);
