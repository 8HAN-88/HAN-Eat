import 'package:flutter/material.dart';

import '../../../models/post_model.dart';
import 'comments_screen.dart';

/// Instagram-style comments bottom sheet over the feed.
Future<void> showPostCommentsSheet(
  BuildContext context, {
  required int postId,
  PostModel? post,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height;
      final keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          height: height * 0.88,
          child: CommentsScreen(
            postId: postId,
            post: post,
            asSheet: true,
          ),
        ),
      );
    },
  );
}
