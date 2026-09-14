import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/widgets/chat_reel_preview.dart';

PostModel _reel() {
  return PostModel(
    id: 28,
    type: 'reel',
    status: 'published',
    createdAt: DateTime(2026),
    userId: 4,
    likesCount: 0,
    commentsCount: 0,
    repostsCount: 0,
    viewsCount: 0,
    isLiked: false,
    author: PostAuthorModel(
      id: 4,
      name: 'lera.korsa',
      username: 'lera.korsa',
    ),
    body: {
      'video_thumbnail': 'https://cdn.example/thumb.jpg',
      'media': [
        {
          'type': 'video',
          'url': 'https://cdn.example/v.mp4',
          'thumbnail_url': 'https://cdn.example/thumb.jpg',
        },
      ],
    },
  );
}

PostModel _photo() {
  return PostModel(
    id: 29,
    type: 'photo',
    title: 'Команды для ракурсов',
    status: 'published',
    createdAt: DateTime(2026),
    userId: 3,
    likesCount: 0,
    commentsCount: 0,
    repostsCount: 0,
    viewsCount: 0,
    isLiked: false,
    author: PostAuthorModel(
      id: 3,
      name: 'lesha_akkerman',
      username: 'lesha_akkerman',
    ),
    body: {
      'media': [
        {'type': 'image', 'url': 'https://cdn.example/a.jpg'},
      ],
    },
  );
}

Future<void> _pumpCard(WidgetTester tester, SharedPostCard card) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: card,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('reel share shows author overlay, play and side actions',
      (tester) async {
    await _pumpCard(
      tester,
      SharedPostCard(
        postId: 28,
        url: 'https://haneat.app/reel/28',
        initialPost: _reel(),
      ),
    );

    expect(find.text('lera.korsa'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.send_outlined), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
  });

  testWidgets('photo share shows author caption under the frame', (tester) async {
    await _pumpCard(
      tester,
      SharedPostCard(
        postId: 29,
        url: 'https://haneat.app/post/29',
        initialPost: _photo(),
      ),
    );

    expect(find.textContaining('lesha_akkerman'), findsWidgets);
    expect(find.textContaining('Команды для ракурсов'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });
}
