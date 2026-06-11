import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/chat_models.dart';
import '../../../widgets/fullscreen_image_viewer.dart';

/// Фото из загруженных сообщений чата (без отдельного API).
class ChatMediaGalleryScreen extends StatelessWidget {
  const ChatMediaGalleryScreen({
    super.key,
    required this.messages,
  });

  final List<ChatMessage> messages;

  List<ChatMessage> get _images {
    final items = messages
        .where(
          (m) =>
              m.type == 'image' &&
              m.mediaUrl != null &&
              m.mediaUrl!.trim().isNotEmpty,
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    final urls = images.map((m) => m.mediaUrl!).toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: Text('Медиа (${images.length})')),
      body: images.isEmpty
          ? const Center(child: Text('Пока нет фото в этом чате'))
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: images.length,
              itemBuilder: (context, index) {
                final msg = images[index];
                final url = msg.mediaUrl!;
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => FullscreenImageViewer(
                          imageUrls: urls,
                          initialIndex: index,
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
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
