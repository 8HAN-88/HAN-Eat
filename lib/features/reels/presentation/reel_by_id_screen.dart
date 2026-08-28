import 'package:flutter/material.dart';

import '../../../app/invalid_link_screen.dart';
import '../../../core/network/feed_load_helper.dart';
import '../../../models/post_model.dart';
import '../../../screens/post_by_id_screen.dart';
import '../../../services/api_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import 'reels_fullscreen_screen.dart';

/// Deep link `https://haneat.app/reel/28` — грузим пост и открываем плеер.
class ReelByIdScreen extends StatefulWidget {
  const ReelByIdScreen({super.key, required this.postId});

  final int postId;

  @override
  State<ReelByIdScreen> createState() => _ReelByIdScreenState();
}

class _ReelByIdScreenState extends State<ReelByIdScreen> {
  late Future<PostModel?> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant ReelByIdScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      _reload();
    }
  }

  void _reload() {
    setState(() {
      _future = ApiService.getPostById(widget.postId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PostModel?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }
        if (snapshot.hasError) {
          final err = snapshot.error!;
          final msg = FeedLoadHelper.isNetworkError(err)
              ? FeedLoadHelper.feedLoadErrorMessage(err)
              : userVisibleError(err, fallback: 'Не удалось открыть рилс');
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
            ),
            body: AppEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Не удалось открыть',
              subtitle: msg,
              action: FilledButton(
                onPressed: _reload,
                child: const Text('Повторить'),
              ),
            ),
          );
        }
        final post = snapshot.data;
        if (post == null) {
          return const InvalidLinkScreen(title: 'Рилс');
        }
        final isReel =
            post.type == 'reel' || post.reelVideoSources.isNotEmpty;
        if (!isReel) {
          return PostByIdScreen(postId: post.id);
        }
        return ReelsFullscreenScreen(initialPost: post);
      },
    );
  }
}
