/// Чем заполнить стену канала, пока список ещё не готов.
enum ChannelPostsPhase { loading, empty, error, list }

/// Пустой кадр «нет постов» только когда загрузка уже закончилась без данных.
/// Иначе на iPhone мелькает заглушка, и Safari снимает её в snapshot свайпа назад.
ChannelPostsPhase channelPostsPhase({
  required bool hasPosts,
  required bool isLoading,
  Object? error,
}) {
  if (hasPosts) return ChannelPostsPhase.list;
  if (isLoading) return ChannelPostsPhase.loading;
  if (error != null) return ChannelPostsPhase.error;
  return ChannelPostsPhase.empty;
}
