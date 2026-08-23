import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_router.dart';
import '../../../../services/like_service.dart';
import '../../../../utils/api_error_parser.dart';
import '../../../../widgets/app_avatar.dart';
import '../../../../widgets/highlighted_text.dart';

/// Instagram-style list of users who liked a post.
Future<void> showPostLikersSheet(
  BuildContext context, {
  required int postId,
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
    builder: (ctx) => _PostLikersSheet(postId: postId),
  );
}

class _PostLikersSheet extends StatefulWidget {
  const _PostLikersSheet({required this.postId});

  final int postId;

  @override
  State<_PostLikersSheet> createState() => _PostLikersSheetState();
}

class _PostLikersSheetState extends State<_PostLikersSheet> {
  final _scrollController = ScrollController();
  final _items = <PostLiker>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  int? _nextCursor;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _nextCursor == null) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) {
      _load(refresh: false);
    }
  }

  Future<void> _load({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_loadingMore || _nextCursor == null) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = await LikeService.listLikers(
        widget.postId,
        limit: 40,
        cursor: refresh ? null : _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _items
            ..clear()
            ..addAll(page.items);
        } else {
          final seen = _items.map((e) => e.id).toSet();
          for (final item in page.items) {
            if (seen.add(item.id)) _items.add(item);
          }
        }
        _total = page.total;
        _nextCursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = userVisibleError(
          e,
          fallback: 'Не удалось загрузить отметки «Нравится»',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height * 0.72,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _total > 0
                        ? 'Нравится ($_total)'
                        : 'Нравится',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          Center(
                            child: TextButton(
                              onPressed: () => _load(refresh: true),
                              child: const Text('Повторить'),
                            ),
                          ),
                        ],
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Text(
                              'Пока никто не отметил',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            itemCount: _items.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _items.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final user = _items[index];
                              return ListTile(
                                leading: AppUserAvatar(
                                  imageUrl: user.avatarUrl,
                                  displayName: user.name,
                                  radius: 22,
                                ),
                                title: HighlightedText(
                                  text: user.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: user.username != null &&
                                        user.username!.trim().isNotEmpty
                                    ? Text('@${user.username}')
                                    : null,
                                onTap: () {
                                  Navigator.of(context).maybePop();
                                  context.push(
                                    ProfileRoute.withUserId(user.id),
                                  );
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
