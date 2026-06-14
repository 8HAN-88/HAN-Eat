import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/chat_models.dart';
import '../../../utils/chat_time_format.dart';
import '../../../widgets/fullscreen_image_viewer.dart';
import '../../../widgets/inline_video_player.dart';

enum _MediaFilter { all, photos, videos, files }

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

  List<ChatMessage> get _allMedia {
    return widget.messages
        .where(
          (m) =>
              m.mediaUrl != null &&
              m.mediaUrl!.trim().isNotEmpty &&
              (m.type == 'image' || m.type == 'video' || m.type == 'file'),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<ChatMessage> get _filtered {
    switch (_filter) {
      case _MediaFilter.photos:
        return _allMedia.where((m) => m.type == 'image').toList();
      case _MediaFilter.videos:
        return _allMedia.where((m) => m.type == 'video').toList();
      case _MediaFilter.files:
        return _allMedia.where((m) => m.type == 'file').toList();
      case _MediaFilter.all:
        return _allMedia;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
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
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: items.isEmpty
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
                          if (msg.type == 'video') {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: InlineVideoPlayer(
                                    videoUrl: url,
                                    onTap: () {},
                                  ),
                                ),
                                const Align(
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.play_circle_outline,
                                    color: Colors.white,
                                    size: 36,
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
}
