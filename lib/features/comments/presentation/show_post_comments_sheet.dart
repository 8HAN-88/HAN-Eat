import 'package:flutter/material.dart';

import '../../../models/post_model.dart';
import 'comments_screen.dart';

/// Instagram-style comments bottom sheet over the current screen.
///
/// Full width on purpose: Material 3 defaults `maxWidth: 640`, and on iPhone
/// PWA a wrong CSS width would pin the sheet as a side panel over the reel.
Future<void> showPostCommentsSheet(
  BuildContext context, {
  required int postId,
  PostModel? post,
}) {
  final width = MediaQuery.sizeOf(context).width;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    constraints: BoxConstraints(minWidth: width, maxWidth: width),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height;
      final keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          width: width,
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
