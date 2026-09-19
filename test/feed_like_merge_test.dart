import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/post_model.dart';

PostModel _post({
  required int id,
  required bool liked,
  int likes = 0,
  bool saved = false,
  bool reposted = false,
  int reposts = 0,
}) {
  return PostModel(
    id: id,
    type: 'post',
    status: 'published',
    createdAt: DateTime.utc(2024, 1, 1),
    userId: 1,
    likesCount: likes,
    commentsCount: 0,
    repostsCount: reposts,
    viewsCount: 0,
    isLiked: liked,
    isSaved: saved,
    isReposted: reposted,
  );
}

void main() {
  test('stale feed payload does not drop a local like', () {
    final local = _post(id: 7, liked: true, likes: 4);
    final incoming = _post(id: 7, liked: false, likes: 3);

    final merged = applyIncomingPostPreservingLocalPoll(local, incoming);

    expect(merged.isLiked, isTrue);
    expect(merged.likesCount, 4);
  });

  test('mergeIncomingFeedPosts keeps likes already shown in the list', () {
    final local = [_post(id: 1, liked: true, likes: 2), _post(id: 2, liked: false)];
    final incoming = [_post(id: 1, liked: false, likes: 1), _post(id: 2, liked: false)];

    final merged = mergeIncomingFeedPosts(local, incoming);

    expect(merged[0].isLiked, isTrue);
    expect(merged[0].likesCount, 2);
    expect(merged[1].isLiked, isFalse);
  });

  test('server like on a new post is kept', () {
    final local = [_post(id: 1, liked: false)];
    final incoming = [_post(id: 3, liked: true, likes: 9)];

    final merged = mergeIncomingFeedPosts(local, incoming);

    expect(merged.single.id, 3);
    expect(merged.single.isLiked, isTrue);
    expect(merged.single.likesCount, 9);
  });
}
