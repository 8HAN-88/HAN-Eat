import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';

/// Legacy Firestore comments — перенаправление на API-комментарии поста.
@Deprecated('Use CommentsScreen / PostCommentsRoute with numeric post id')
class PostCommentsPage extends StatelessWidget {
  const PostCommentsPage({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(postId);
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.push(PostCommentsRoute.pathFor(id));
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Комментарии')),
      body: const Center(
        child: Text('Комментарии доступны только для постов с числовым id.'),
      ),
    );
  }
}
