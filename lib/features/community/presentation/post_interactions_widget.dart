import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../models/post.dart';

/// Legacy stub — лайк/комментарии через API ([PostCommentsRoute]).
@Deprecated('Use feed post card actions (LikeService, PostCommentsRoute)')
class PostInteractionsWidget extends StatelessWidget {
  const PostInteractionsWidget({
    super.key,
    required this.post,
  });

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.favorite_border,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text('${post.likesCount}'),
        const SizedBox(width: 16),
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline),
          onPressed: () => context.push(PostCommentsRoute.pathFor(post.id)),
          tooltip: 'Комментарии',
        ),
        Text('${post.commentsCount}'),
      ],
    );
  }
}
