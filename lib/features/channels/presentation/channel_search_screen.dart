// Экран поиска по каналу в стиле Telegram
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../../services/channel_service.dart';
import '../../../models/post_model.dart';
import 'channel_post_card.dart';
import 'channel_posts_screen.dart';

class ChannelSearchScreen extends ConsumerStatefulWidget {
  final int channelId;
  final String initialQuery;
  final ChannelDetail channel;
  
  const ChannelSearchScreen({
    Key? key,
    required this.channelId,
    required this.initialQuery,
    required this.channel,
  }) : super(key: key);
  
  @override
  ConsumerState<ChannelSearchScreen> createState() => _ChannelSearchScreenState();
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
          _error = e.toString();
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Поиск по каналу',
                  style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Введите запрос для поиска постов',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }
        
        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (_error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  'Ошибка поиска',
                  style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _performSearch,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          );
        }
        
        if (_posts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Ничего не найдено',
                  style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Попробуйте изменить запрос',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
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
                  onCommentTap: () {
                    // TODO: Navigate to comments
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
