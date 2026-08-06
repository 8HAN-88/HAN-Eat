import 'package:flutter/material.dart';

import '../../../services/server_config.dart';
import '../data/story_models.dart';
import '../data/story_service.dart';
import 'story_camera_screen.dart';
import 'story_viewer_screen.dart';

/// Хаб Stories / Моментов.
class StoriesHubScreen extends StatefulWidget {
  const StoriesHubScreen({super.key});

  @override
  State<StoriesHubScreen> createState() => _StoriesHubScreenState();
}

class _StoriesHubScreenState extends State<StoriesHubScreen> {
  bool _loading = true;
  Object? _error;
  List<StoryGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  Future<void> _loadStories() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stories = await StoryService.fetchActiveStories();
      if (!mounted) return;
      setState(() {
        _groups = StoryService.groupByAuthor(stories);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createStory() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StoryCameraScreen()),
    );
    if (created == true) {
      await _loadStories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сторис опубликована')),
      );
    }
  }

  void _openGroup(StoryGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(
          stories: group.stories.map(_toViewerItem).toList(),
        ),
      ),
    );
  }

  StoryItem _toViewerItem(StoryDto story) => StoryItem(
        id: '${story.id}',
        mediaUrl: story.mediaUrl,
        authorId: story.author.id,
        authorName: story.author.name,
        authorAvatar: story.author.avatarUrl,
        isVideo: story.isVideo,
        viewsCount: story.viewsCount,
        myReaction: story.myReaction,
        reactions: story.reactions,
        duration: story.isVideo
            ? const Duration(seconds: 30)
            : const Duration(seconds: 5),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моменты'),
        actions: [
          IconButton(
            tooltip: 'Создать сторис',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _createStory,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createStory,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Сторис'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadStories,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.cloud_off_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Не удалось загрузить сторис',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Потяните вниз, чтобы повторить',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      );
    }
    if (_groups.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.auto_stories_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Пока нет активных моментов',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Опубликуйте фото или видео до 30 секунд. Сторис исчезнет через 24 часа.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: _groups.length,
      itemBuilder: (context, index) {
        final group = _groups[index];
        return _StoryGroupCard(
          group: group,
          onTap: () => _openGroup(group),
        );
      },
    );
  }
}

class _StoryGroupCard extends StatelessWidget {
  const _StoryGroupCard({
    required this.group,
    required this.onTap,
  });

  final StoryGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = group.latest;
    final previewUrl = latest.thumbnailUrl ?? latest.mediaUrl;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              ServerConfig.resolveMediaUrl(previewUrl),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: latest.author.avatarUrl == null
                        ? null
                        : NetworkImage(
                            ServerConfig.resolvePublisherAvatarUrl(
                              latest.author.avatarUrl!,
                            ),
                          ),
                    child: latest.author.avatarUrl == null
                        ? const Icon(Icons.person, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          latest.author.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${group.stories.length} ${_storyCountLabel(group.stories.length)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (latest.isVideo)
                    const Icon(Icons.play_circle_outline, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _storyCountLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'сторис';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'сторис';
    }
    return 'сторис';
  }
}
