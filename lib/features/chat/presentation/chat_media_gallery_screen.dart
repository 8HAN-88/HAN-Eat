import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/chat_models.dart';
import '../../../services/server_config.dart';
import '../../../utils/chat_time_format.dart';
import '../../../widgets/chat_link_preview.dart';
import '../../../widgets/fullscreen_image_viewer.dart';
import '../../../widgets/inline_video_player.dart';

enum _MediaFilter { all, photos, videos, files, links }

/// Медиа из сообщений чата с фильтрами по типу.
class ChatMediaGalleryScreen extends StatefulWidget {
  const ChatMediaGalleryScreen({
    super.key,
    required this.messages,
  });

  final List<ChatMessage> messages;

  @override
  State<ChatMediaGalleryScreen> createState() => _ChatMediaGalleryScreenState();
}

class _ChatMediaGalleryScreenState extends State<ChatMediaGalleryScreen> {
  _MediaFilter _filter = _MediaFilter.all;

  List<({ChatMessage message, String url})> get _allLinks {
    final items = <({ChatMessage message, String url})>[];
    for (final msg in widget.messages) {
      final url = extractFirstHttpUrl(msg.content);
      if (url == null || url.isEmpty) continue;
      items.add((message: msg, url: url));
    }
    items.sort((a, b) => b.message.createdAt.compareTo(a.message.createdAt));
    return items;
  }

  List<ChatMessage> get _allMedia {
    return widget.messages
        .where(
          (m) =>
              m.mediaUrl != null &&
              m.mediaUrl!.trim().isNotEmpty &&
              (m.type == 'image' ||
                  m.type == 'video' ||
                  m.type == 'video_note' ||
                  m.type == 'file'),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<ChatMessage> get _filtered {
    switch (_filter) {
      case _MediaFilter.photos:
        return _allMedia.where((m) => m.type == 'image').toList();
      case _MediaFilter.videos:
        return _allMedia
            .where((m) => m.type == 'video' || m.type == 'video_note')
            .toList();
      case _MediaFilter.files:
        return _allMedia.where((m) => m.type == 'file').toList();
      case _MediaFilter.links:
        return _allMedia;
      case _MediaFilter.all:
        return _allMedia;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final links = _allLinks;
    final imageItems =
        items.where((m) => m.type == 'image').toList(growable: false);
    final imageUrls =
        imageItems.map((m) => m.mediaUrl!).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text('Медиа (${items.length})')),
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
                ButtonSegment(value: _MediaFilter.links, label: Text('Ссылки')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: _filter == _MediaFilter.links
                ? links.isEmpty
                    ? const Center(child: Text('Пока нет ссылок в этом чате'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: links.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = links[index];
                          return ListTile(
                            leading: const Icon(Icons.link_outlined),
                            title: Text(
                              item.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              formatChatMessageTime(item.message.createdAt),
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
                : _filter == _MediaFilter.files
                    ? ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final msg = items[index];
                          return ListTile(
                            leading: const Icon(Icons.insert_drive_file_outlined),
                            title: Text(
                              msg.content.trim().isEmpty
                                  ? 'Файл'
                                  : msg.content.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              formatChatMessageTime(msg.createdAt),
                            ),
                            onTap: () {
                              final url = msg.mediaUrl?.trim();
                              if (url == null || url.isEmpty) return;
                              _openExternal(ServerConfig.resolveMediaUrl(url));
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
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final msg = items[index];
                          final url = msg.mediaUrl!;
                          if (msg.type == 'video' || msg.type == 'video_note') {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                GestureDetector(
                                  onTap: () => _openExternal(
                                    ServerConfig.resolveMediaUrl(url),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: InlineVideoPlayer(
                                      videoUrl: ServerConfig.resolveMediaUrl(url),
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
                                  builder: (_) => FullscreenImageViewer(
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
                                errorWidget: (_, __, ___) => ColoredBox(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          );
                        },
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
