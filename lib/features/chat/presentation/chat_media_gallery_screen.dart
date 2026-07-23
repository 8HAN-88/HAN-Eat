import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../services/server_config.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/chat_time_format.dart';
import '../../../widgets/chat_link_preview.dart';
import '../../../widgets/fullscreen_image_viewer.dart';
import '../../../widgets/inline_video_player.dart';

enum _MediaFilter { all, photos, videos, files, voices, links }

/// Медиа из сообщений чата с фильтрами по типу (полная история через API).
class ChatMediaGalleryScreen extends StatefulWidget {
  const ChatMediaGalleryScreen({
    super.key,
    required this.conversationId,
    this.seedMessages = const [],
  });

  final int conversationId;
  final List<ChatMessage> seedMessages;

  @override
  State<ChatMediaGalleryScreen> createState() => _ChatMediaGalleryScreenState();
}

class _ChatMediaGalleryScreenState extends State<ChatMediaGalleryScreen> {
  _MediaFilter _filter = _MediaFilter.all;
  final List<ChatMessage> _media = [];
  final List<({ChatMessage message, String url})> _links = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int? _cursor;
  String? _error;

  String get _kindParam {
    switch (_filter) {
      case _MediaFilter.photos:
        return 'photos';
      case _MediaFilter.videos:
        return 'videos';
      case _MediaFilter.files:
        return 'files';
      case _MediaFilter.voices:
        return 'voices';
      case _MediaFilter.links:
        return 'links';
      case _MediaFilter.all:
        return 'all';
    }
  }

  @override
  void initState() {
    super.initState();
    _seedFromLocal();
    unawaited(_reload());
  }

  void _seedFromLocal() {
    final media = <ChatMessage>[];
    final links = <({ChatMessage message, String url})>[];
    final seenMedia = <int>{};
    final seenLinks = <String>{};
    for (final msg in widget.seedMessages) {
      final mediaUrl = msg.mediaUrl?.trim();
      if (mediaUrl != null &&
          mediaUrl.isNotEmpty &&
          (msg.type == 'image' ||
              msg.type == 'video' ||
              msg.type == 'video_note' ||
              msg.type == 'file' ||
              msg.type == 'voice') &&
          seenMedia.add(msg.id)) {
        media.add(msg);
      }
      final url = extractFirstHttpUrl(msg.content);
      if (url != null && url.isNotEmpty && seenLinks.add(url)) {
        links.add((message: msg, url: url));
      }
    }
    media.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    links.sort((a, b) => b.message.createdAt.compareTo(a.message.createdAt));
    _media
      ..clear()
      ..addAll(media);
    _links
      ..clear()
      ..addAll(links);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
      _cursor = null;
      _loadingMore = false;
    });
    try {
      final page = await ChatService.listChatMedia(
        conversationId: widget.conversationId,
        kind: _kindParam,
        limit: 60,
      );
      if (!mounted) return;
      _applyPage(page.items, replace: true);
      setState(() {
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e, fallback: 'Не удалось загрузить медиа');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ChatService.listChatMedia(
        conversationId: widget.conversationId,
        kind: _kindParam,
        cursor: _cursor,
        limit: 60,
      );
      if (!mounted) return;
      _applyPage(page.items, replace: false);
      setState(() {
        _hasMore = page.hasMore;
        _cursor = page.nextCursor ?? _cursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _applyPage(List<ChatMessage> items, {required bool replace}) {
    if (replace) {
      if (_filter == _MediaFilter.links) {
        _links.clear();
      } else {
        _media.clear();
      }
    }
    final seenMedia = {for (final m in _media) m.id};
    final seenLinks = {for (final l in _links) l.url};
    if (_filter == _MediaFilter.links) {
      for (final msg in items) {
        final url = extractFirstHttpUrl(msg.content);
        if (url == null || url.isEmpty || !seenLinks.add(url)) continue;
        _links.add((message: msg, url: url));
      }
      _links.sort(
        (a, b) => b.message.createdAt.compareTo(a.message.createdAt),
      );
    } else {
      for (final msg in items) {
        final mediaUrl = msg.mediaUrl?.trim();
        if (mediaUrl == null || mediaUrl.isEmpty) continue;
        if (!seenMedia.add(msg.id)) continue;
        _media.add(msg);
      }
      _media.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
  }

  List<ChatMessage> get _filteredMedia {
    switch (_filter) {
      case _MediaFilter.photos:
        return _media.where((m) => m.type == 'image').toList();
      case _MediaFilter.videos:
        return _media
            .where((m) => m.type == 'video' || m.type == 'video_note')
            .toList();
      case _MediaFilter.files:
        return _media.where((m) => m.type == 'file').toList();
      case _MediaFilter.voices:
        return _media.where((m) => m.type == 'voice').toList();
      case _MediaFilter.links:
        return _media;
      case _MediaFilter.all:
        return _media
            .where(
              (m) =>
                  m.type == 'image' ||
                  m.type == 'video' ||
                  m.type == 'video_note' ||
                  m.type == 'file',
            )
            .toList();
    }
  }

  String _voiceDurationLabel(ChatMessage msg) {
    final sec = msg.voiceDurationSec;
    if (sec == null || sec <= 0) {
      final parsed = int.tryParse(msg.content.trim());
      if (parsed == null || parsed <= 0) return 'Голосовое';
      return _formatDuration(parsed);
    }
    return _formatDuration(sec);
  }

  String _formatDuration(int totalSec) {
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _onFilterChanged(_MediaFilter value) {
    if (_filter == value) return;
    setState(() => _filter = value);
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredMedia;
    final links = _links;
    final imageItems =
        items.where((m) => m.type == 'image').toList(growable: false);
    final imageUrls =
        imageItems.map((m) => m.mediaUrl!).toList(growable: false);
    final count = _filter == _MediaFilter.links ? links.length : items.length;

    return Scaffold(
      appBar: AppBar(title: Text('Медиа ($count)')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<_MediaFilter>(
              segments: const [
                ButtonSegment(value: _MediaFilter.all, label: Text('Все')),
                ButtonSegment(value: _MediaFilter.photos, label: Text('Фото')),
                ButtonSegment(
                  value: _MediaFilter.videos,
                  label: Text('Видео'),
                ),
                ButtonSegment(value: _MediaFilter.files, label: Text('Файлы')),
                ButtonSegment(
                  value: _MediaFilter.voices,
                  label: Text('Голос'),
                ),
                ButtonSegment(value: _MediaFilter.links, label: Text('Ссылки')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => _onFilterChanged(s.first),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
                  unawaited(_loadMore());
                }
                return false;
              },
              child: _loading && count == 0
                  ? const Center(child: CircularProgressIndicator())
                  : _filter == _MediaFilter.links
                      ? links.isEmpty
                          ? const Center(
                              child: Text('Пока нет ссылок в этом чате'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: links.length + (_loadingMore ? 1 : 0),
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                if (index >= links.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                final item = links[index];
                                return ListTile(
                                  leading: const Icon(Icons.link_outlined),
                                  title: Text(
                                    item.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    formatChatMessageTime(
                                      item.message.createdAt,
                                    ),
                                  ),
                                  onTap: () => _openExternal(item.url),
                                );
                              },
                            )
                      : items.isEmpty
                          ? Center(
                              child: Text(
                                _filter == _MediaFilter.all
                                    ? 'Пока нет медиа в этом чате'
                                    : 'Ничего не найдено',
                              ),
                            )
                          : (_filter == _MediaFilter.files ||
                                  _filter == _MediaFilter.voices)
                              ? ListView.separated(
                                  padding: const EdgeInsets.all(8),
                                  itemCount:
                                      items.length + (_loadingMore ? 1 : 0),
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    if (index >= items.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }
                                    final msg = items[index];
                                    final isVoice =
                                        _filter == _MediaFilter.voices ||
                                            msg.type == 'voice';
                                    return ListTile(
                                      leading: Icon(
                                        isVoice
                                            ? Icons.mic_none_rounded
                                            : Icons.insert_drive_file_outlined,
                                      ),
                                      title: Text(
                                        isVoice
                                            ? _voiceDurationLabel(msg)
                                            : (msg.content.trim().isEmpty
                                                ? 'Файл'
                                                : msg.content.trim()),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        formatChatMessageTime(msg.createdAt),
                                      ),
                                      onTap: () {
                                        final url = msg.mediaUrl?.trim();
                                        if (url == null || url.isEmpty) return;
                                        _openExternal(
                                          ServerConfig.resolveMediaUrl(url),
                                        );
                                      },
                                    );
                                  },
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.all(4),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 4,
                                    mainAxisSpacing: 4,
                                  ),
                                  itemCount:
                                      items.length + (_loadingMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index >= items.length) {
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    }
                                    final msg = items[index];
                                    final url = msg.mediaUrl!;
                                    if (msg.type == 'video' ||
                                        msg.type == 'video_note') {
                                      return Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          GestureDetector(
                                            onTap: () => _openExternal(
                                              ServerConfig.resolveMediaUrl(url),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: InlineVideoPlayer(
                                                videoUrl: ServerConfig
                                                    .resolveMediaUrl(url),
                                                onTap: () {},
                                              ),
                                            ),
                                          ),
                                          const IgnorePointer(
                                            child: Align(
                                              alignment: Alignment.center,
                                              child: Icon(
                                                Icons.play_circle_outline,
                                                color: Colors.white,
                                                size: 36,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                    final imageIndex = imageItems.indexOf(msg);
                                    return GestureDetector(
                                      onTap: () {
                                        if (imageIndex < 0) return;
                                        Navigator.of(context).push<void>(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                FullscreenImageViewer(
                                              imageUrls: imageUrls,
                                              initialIndex: imageIndex,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Hero(
                                        tag: 'chat_media_${msg.id}_$url',
                                        child: CachedNetworkImage(
                                          imageUrl: url,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) =>
                                              ColoredBox(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            child: const Icon(
                                              Icons.broken_image_outlined,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternal(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
