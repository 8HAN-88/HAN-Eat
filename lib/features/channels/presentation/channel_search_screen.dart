// Экран поиска по каналу в стиле Telegram
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../../services/channel_service.dart';
import '../../../models/post_model.dart';
import '../../../app/app_router.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import 'channel_post_card.dart';

class ChannelSearchScreen extends ConsumerStatefulWidget {
  final int channelId;
  final String initialQuery;
  final ChannelDetail channel;

  const ChannelSearchScreen({
    super.key,
    required this.channelId,
    required this.initialQuery,
    required this.channel,
  });

  @override
  ConsumerState<ChannelSearchScreen> createState() =>
      _ChannelSearchScreenState();
}

class _ChannelSearchScreenState extends ConsumerState<ChannelSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<PostModel> _posts = [];
  bool _isLoading = false;
  String? _error;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    if (widget.initialQuery.isNotEmpty) {
      _performSearch();
    }

    // Слушаем изменения в поле поиска для поиска в реальном времени
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // Отменяем предыдущий таймер
    _searchDebounce?.cancel();

    // Если поле пустое, очищаем результаты
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _posts = [];
        _error = null;
        _isLoading = false;
      });
      return;
    }

    // Устанавливаем новый таймер для поиска с задержкой (debounce)
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _posts = [];
        _error = null;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ChannelService.getChannelPosts(
        channelId: widget.channelId,
        limit: 100,
        offset: 0,
        search: query,
      );

      if (mounted) {
        setState(() {
          _posts = response.posts.map((p) => PostModel.fromJson(p)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userVisibleError(e, fallback: 'Не удалось выполнить поиск');
          _isLoading = false;
        });
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _posts = [];
      _error = null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Поиск по каналу...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey[600]),
          ),
          style: const TextStyle(fontSize: 16),
          textInputAction: TextInputAction.search,
        ),
        actions: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, child) {
              if (value.text.isNotEmpty) {
                return IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _clearSearch,
                  tooltip: 'Очистить',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Используем ValueListenableBuilder для отслеживания изменений в поле поиска
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchController,
      builder: (context, value, child) {
        final query = value.text.trim();

        // Если поле поиска пустое, показываем подсказку
        if (query.isEmpty) {
          return const AppEmptyState(
            icon: Icons.search_rounded,
            title: 'Поиск по каналу',
            subtitle: 'Введите запрос для поиска постов',
          );
        }

        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_error != null) {
          return AppEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Ошибка поиска',
            subtitle: _error,
            action: FilledButton(
              onPressed: _performSearch,
              child: const Text('Повторить'),
            ),
          );
        }

        if (_posts.isEmpty) {
          return const AppEmptyState(
            icon: Icons.search_off_rounded,
            title: 'Ничего не найдено',
            subtitle: 'Попробуйте изменить запрос',
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _posts.length,
          itemBuilder: (context, index) {
            final post = _posts[index];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ChannelPostCard(
                  post: post,
                  channelId: widget.channelId,
                  channel: widget.channel,
                  onCommentTap: () =>
                      context.push(PostCommentsRoute.pathFor(post.id)),
                  onCardTap: () {
                    context.push(
                      ChannelDetailRoute.post(widget.channelId, post.id),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
