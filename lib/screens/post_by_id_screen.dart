import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/network/feed_load_helper.dart';
import '../features/feed/presentation/new_post_card.dart';
import '../models/post_model.dart';
import '../services/api_service.dart';
import '../utils/api_error_parser.dart';
import '../widgets/app_empty_state.dart';

class PostByIdScreen extends StatefulWidget {
  const PostByIdScreen({super.key, required this.postId});

  final int postId;

  @override
  State<PostByIdScreen> createState() => _PostByIdScreenState();
}

class _PostByIdScreenState extends State<PostByIdScreen> {
  late Future<PostModel?> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = ApiService.getPostById(widget.postId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пост'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _future;
        },
        child: FutureBuilder<PostModel?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 200),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }
            if (snapshot.hasError) {
              final err = snapshot.error!;
              final msg = FeedLoadHelper.isNetworkError(err)
                  ? FeedLoadHelper.feedLoadErrorMessage(err)
                  : userVisibleError(err, fallback: 'Не удалось загрузить пост');
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: AppEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Не удалось загрузить',
                      subtitle: msg,
                      action: FilledButton(
                        onPressed: _reload,
                        child: const Text('Повторить'),
                      ),
                    ),
                  ),
                ],
              );
            }
            final post = snapshot.data;
            if (post == null) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: AppEmptyState(
                      icon: Icons.article_outlined,
                      title: 'Пост не найден',
                      subtitle: 'Возможно, он удалён или недоступен',
                      action: TextButton(
                        onPressed: () {
                          if (context.canPop()) context.pop();
                        },
                        child: const Text('Назад'),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              children: [
                NewPostCard(
                  post: post,
                  onCommentTap: () =>
                      context.push('/post/${post.id}/comments'),
                  onPostDeleted: () {
                    if (context.canPop()) context.pop();
                  },
                  onAuthorTap: () {
                    if (post.communityId != null) {
                      context.push('/channel/${post.communityId}');
                    } else {
                      context.push('/profile?userId=${post.userId}');
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
