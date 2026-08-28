import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../services/auth_service.dart';
import '../../../../services/server_config.dart';
import '../../../stories/data/story_models.dart';
import '../../../stories/data/story_service.dart';
import '../../../stories/presentation/story_camera_screen.dart';
import '../../../stories/presentation/story_viewer_screen.dart';

/// Instagram-style horizontal stories row for the home feed.
class FeedStoriesStrip extends StatefulWidget {
  const FeedStoriesStrip({
    super.key,
    this.refreshToken = 0,
  });

  /// Bump from parent on pull-to-refresh to reload rings.
  final int refreshToken;

  @override
  State<FeedStoriesStrip> createState() => _FeedStoriesStripState();
}

class _FeedStoriesStripState extends State<FeedStoriesStrip> {
  bool _loading = true;
  List<StoryGroup> _groups = const [];
  final Set<int> _seenAuthorIds = <int>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant FeedStoriesStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final stories = await StoryService.fetchActiveStories(limit: 80);
      if (!mounted) return;
      setState(() {
        _groups = StoryService.groupByAuthor(stories);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _createStory() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StoryCameraScreen()),
    );
    if (created == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сторис опубликована')),
      );
    }
  }

  Future<void> _openGroup(StoryGroup group) async {
    setState(() => _seenAuthorIds.add(group.author.id));
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(
          stories: group.stories.map(_toViewerItem).toList(),
        ),
      ),
    );
    for (final story in group.stories) {
      try {
        await StoryService.markViewed(story.id);
      } catch (_) {
        // Best-effort view tracking.
      }
    }
  }

  StoryItem _toViewerItem(StoryDto story) => StoryItem(
        id: '${story.id}',
        mediaUrl: story.mediaUrl,
        authorId: story.author.id,
        authorName: story.author.name,
        authorAvatar: story.author.avatarUrl,
        thumbnailUrl: story.thumbnailUrl,
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
    final me = AuthService.instance.currentUser;
    StoryGroup? myGroup;
    final others = <StoryGroup>[];
    for (final group in _groups) {
      if (me != null && group.author.id == me.id) {
        myGroup = group;
      } else {
        others.add(group);
      }
    }

    if (!_loading && others.isEmpty && myGroup == null && me == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        children: [
          if (me != null)
            _StoryRing(
              label: 'Вы',
              avatarUrl: me.avatarUrl,
              initial: me.name.isNotEmpty ? me.name[0].toUpperCase() : '+',
              hasStory: myGroup != null,
              isOwn: true,
              unseen: myGroup != null && !_seenAuthorIds.contains(me.id),
              onTap: () {
                if (myGroup != null) {
                  unawaited(_openGroup(myGroup));
                } else {
                  unawaited(_createStory());
                }
              },
              onAdd: () => unawaited(_createStory()),
            ),
          if (_loading)
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 48,
                      height: 10,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              )
          else
            for (final group in others)
              _StoryRing(
                label: group.author.name,
                avatarUrl: group.author.avatarUrl,
                initial: group.author.name.isNotEmpty
                    ? group.author.name[0].toUpperCase()
                    : '?',
                hasStory: true,
                isOwn: false,
                unseen: !_seenAuthorIds.contains(group.author.id),
                onTap: () => unawaited(_openGroup(group)),
              ),
        ],
      ),
    );
  }
}

class _StoryRing extends StatelessWidget {
  const _StoryRing({
    required this.label,
    required this.initial,
    required this.hasStory,
    required this.isOwn,
    required this.unseen,
    required this.onTap,
    this.avatarUrl,
    this.onAdd,
  });

  final String label;
  final String? avatarUrl;
  final String initial;
  final bool hasStory;
  final bool isOwn;
  final bool unseen;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty
        ? ServerConfig.resolvePublisherAvatarUrl(avatarUrl!)
        : null;
    final ringColors = !hasStory
        ? [scheme.outlineVariant, scheme.outlineVariant]
        : unseen
            ? const [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)]
            : [scheme.outline, scheme.outline];

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: ringColors,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.surface,
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundImage: avatar != null
                              ? ResizeImage(
                                  CachedNetworkImageProvider(avatar),
                                  width: 112,
                                )
                              : null,
                          backgroundColor: scheme.surfaceContainerHighest,
                          child: avatar == null
                              ? Text(
                                  initial,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    if (isOwn)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Material(
                          color: scheme.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onAdd ?? onTap,
                            child: const SizedBox(
                              width: 22,
                              height: 22,
                              child: Icon(
                                Icons.add,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
