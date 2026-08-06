import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/utils/post_display_title.dart';

void main() {
  test('resolvePostDisplayTitle prefers post title then body fields', () {
    expect(
      resolvePostDisplayTitle(
        title: 'Салат',
        body: {'translated_title': 'Salad'},
      ),
      'Салат',
    );
    expect(
      resolvePostDisplayTitle(
        title: null,
        body: {
          'translated_title': 'Borscht',
          'recipe': {'title': 'Nested'},
        },
      ),
      'Borscht',
    );
    expect(
      resolvePostDisplayTitle(title: 'recipe', body: null),
      isNull,
    );
  });

  test('displayTitleForPost falls back for empty legacy body', () {
    final post = PostModel(
      id: 1,
      type: 'recipe',
      status: 'published',
      title: null,
      description: null,
      visibility: 'public',
      createdAt: DateTime.utc(2024, 1, 1),
      userId: 1,
      likesCount: 0,
      commentsCount: 0,
      repostsCount: 0,
      viewsCount: 0,
      isLiked: false,
      body: const {},
    );
    expect(displayTitleForPost(post), 'Пост');
  });
}
