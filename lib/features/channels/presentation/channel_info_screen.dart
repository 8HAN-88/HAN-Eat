// Полноэкранная страница канала в духе Telegram: шапка, 4 кнопки, карточка ссылки/описания, вкладки (без ленты постов).
import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../services/channel_service.dart';
import '../../../services/channel_cache_service.dart';
import '../../../services/channel_notification_prefs.dart';
import 'channel_detail_screen.dart';
import 'channel_detail_screen_tabs.dart';
import 'channel_settings_bottom_sheet.dart';
import 'channel_search_screen.dart';
import '../../../app/app_router.dart';
import '../../../widgets/app_empty_state.dart';

class ChannelInfoScreen extends ConsumerStatefulWidget {
  final int channelId;

  const ChannelInfoScreen({
    super.key,
    required this.channelId,
  });

  @override
  ConsumerState<ChannelInfoScreen> createState() => _ChannelInfoScreenState();
}

class _ChannelInfoScreenState extends ConsumerState<ChannelInfoScreen>
    with SingleTickerProviderStateMixin {
  ChannelDetail? _channel;
  Object? _channelLoadError;
  bool _isLoading = true;
  bool _isJoining = false;
  bool _hasRecipes = false;
  TabController? _tabController;

  /// Локально, как переключатель «звук» в Telegram (UI + будущий API).
  bool _notificationsMuted = false;
  bool _descExpanded = false;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isLoading = true;
      _channelLoadError = null;
    });
    try {
      final channel = await ChannelCacheService.getChannel(
        widget.channelId,
        forceRefresh: true,
      );
      final recipeProbe = await ChannelService.getChannelPosts(
        channelId: widget.channelId,
        limit: 1,
        offset: 0,
        postType: 'recipe',
      );
      if (!mounted) return;
      final hasRecipes = recipeProbe.total > 0;
      var notificationsEnabled = true;
      if (channel.channelNotificationsEnabled != null) {
        notificationsEnabled = channel.channelNotificationsEnabled!;
        await ChannelNotificationPrefs.cacheFromServer(
          widget.channelId,
          notificationsEnabled,
        );
      } else {
        notificationsEnabled =
            await ChannelNotificationPrefs.getNotificationsEnabled(
          widget.channelId,
        );
      }
      _tabController?.dispose();
      _tabController = TabController(
        length: hasRecipes ? 3 : 2,
        vsync: this,
      );
      setState(() {
        _channel = channel;
        _hasRecipes = hasRecipes;
        _notificationsMuted = !notificationsEnabled;
        _isLoading = false;
        _channelLoadError = null;
      });
    } catch (e) {
      debugPrint('ChannelInfoScreen load error: $e');
      if (mounted) {
        setState(() {
          _channel = null;
          _channelLoadError = e;
          _isLoading = false;
        });
      }
    }
  }

  String _membersLabel(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return '$n подписчиков';
    if (mod10 == 1) return '$n подписчик';
    if (mod10 >= 2 && mod10 <= 4) return '$n подписчика';
    return '$n подписчиков';
  }

  String get _publicLink => 'https://han-eat.app/channel/${widget.channelId}';

  Future<void> _toggleSubscribe() async {
    if (_channel == null || _isJoining) return;
    setState(() => _isJoining = true);
    try {
      if (_channel!.isMember || _channel!.isPending) {
        await ChannelService.leaveChannel(widget.channelId);
      } else {
        final res = await ChannelService.joinChannel(widget.channelId);
        if (res.pending && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Заявка отправлена. Ожидайте одобрения модератора.',
              ),
            ),
          );
        }
      }
      final channel = await ChannelCacheService.getChannel(
        widget.channelId,
        forceRefresh: true,
      );
      if (mounted) setState(() => _channel = channel);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userVisibleError(e))));
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _onLeaveOrJoinTap() async {
    final c = _channel;
    if (c == null || _isJoining) return;
    if (c.isMember || c.isPending) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Покинуть канал?'),
          content: const Text(
            'Вы перестанете видеть публикации этого канала в ленте.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Покинуть'),
            ),
          ],
        ),
      );
      if (ok == true) await _toggleSubscribe();
    } else {
      await _toggleSubscribe();
    }
  }

  Future<void> _toggleSoundUi() async {
    if (_channel != null && !_channel!.isMember) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала вступите в канал')),
      );
      return;
    }
    final nextMuted = !_notificationsMuted;
    try {
      await ChannelNotificationPrefs.setNotificationsEnabled(
        widget.channelId,
        !nextMuted,
      );
      if (!mounted) return;
      setState(() => _notificationsMuted = nextMuted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextMuted
                ? 'Уведомления этого канала отключены'
                : 'Уведомления этого канала включены',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось сохранить'))),
        );
      }
    }
  }

  void _openSearch() {
    if (_channel == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => ChannelSearchScreen(
          channelId: widget.channelId,
          initialQuery: '',
          channel: _channel!,
        ),
      ),
    );
  }

  void _showSettings() {
    if (_channel == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      showDragHandle: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 320),
        reverseDuration: Duration(milliseconds: 260),
      ),
      builder: (ctx) => ChannelSettingsBottomSheet(
        channel: _channel!,
        channelId: widget.channelId,
        onShare: _shareChannel,
        onCopyLink: _copyChannelLink,
        onSearch: () {
          Navigator.of(ctx).pop();
          _openSearch();
        },
        onManage: (_channel!.isOwner ||
            _channel!.isAdmin ||
            _channel!.isModerator)
            ? () {
                Navigator.of(ctx).pop();
                context.push(ChannelDetailRoute.management(widget.channelId));
              }
            : null,
      ),
    );
  }

  Future<void> _shareChannel() async {
    await Clipboard.setData(ClipboardData(text: _publicLink));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка скопирована в буфер обмена')),
      );
    }
  }

  Future<void> _copyChannelLink() async {
    await Clipboard.setData(ClipboardData(text: _publicLink));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка скопирована')),
      );
    }
  }

  Widget _telegramActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _tabController == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Канал')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_channel == null) {
      if (_channelLoadError != null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Канал')),
          body: AppEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Не удалось загрузить',
            subtitle: userVisibleError(
              _channelLoadError!,
              fallback: 'Проверьте сеть',
            ),
            action: FilledButton(
              onPressed: _bootstrap,
              child: const Text('Повторить'),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Канал')),
        body: const AppEmptyState(
          icon: Icons.group_off_outlined,
          title: 'Канал не найден',
          subtitle: 'Возможно, он удалён или у вас нет доступа',
        ),
      );
    }

    final c = _channel!;
    final scheme = Theme.of(context).colorScheme;
    final desc = c.description?.trim() ?? '';
    final showDescToggle = desc.length > 140;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(ChannelsListRoute.path);
            }
          },
        ),
        title: const SizedBox.shrink(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundImage:
                      c.avatarUrl != null && c.avatarUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(c.avatarUrl!)
                          : null,
                  child: c.avatarUrl == null || c.avatarUrl!.isEmpty
                      ? Text(
                          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _membersLabel(c.membersCount),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _telegramActionTile(
                  icon: _notificationsMuted
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_outlined,
                  label: 'звук',
                  onTap: _toggleSoundUi,
                ),
                _telegramActionTile(
                  icon: Icons.search,
                  label: 'поиск',
                  onTap: _openSearch,
                ),
                _telegramActionTile(
                  icon: (c.isMember || c.isPending)
                      ? Icons.logout
                      : Icons.login,
                  label: c.isMember
                      ? 'покинуть'
                      : c.isPending
                          ? 'ожидание'
                          : (!c.isPublic ? 'запрос' : 'вступить'),
                  onTap: () {
                    if (_isJoining) return;
                    _onLeaveOrJoinTap();
                  },
                ),
                _telegramActionTile(
                  icon: Icons.more_horiz,
                  label: 'ещё',
                  onTap: _showSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ссылка',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.2,
                          ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _copyChannelLink,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _publicLink,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: scheme.primary,
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Скопировать',
                              icon: const Icon(Icons.qr_code_2, size: 22),
                              onPressed: _copyChannelLink,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'описание',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.2,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        desc,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: _descExpanded ? null : 4,
                        overflow: _descExpanded
                            ? TextOverflow.visible
                            : TextOverflow.fade,
                      ),
                      if (showDescToggle)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () {
                              setState(() => _descExpanded = !_descExpanded);
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _descExpanded ? 'свернуть' : 'ещё',
                              style: TextStyle(color: scheme.primary),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: TabBar(
              controller: _tabController!,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: scheme.surfaceContainerHigh,
              ),
              dividerColor: Colors.transparent,
              labelColor: scheme.onSurface,
              unselectedLabelColor: scheme.onSurfaceVariant,
              labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              unselectedLabelStyle:
                  Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
              tabs: [
                const Tab(text: 'Медиа'),
                if (_hasRecipes) const Tab(text: 'Рецепты'),
                const Tab(text: 'О канале'),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController!,
              children: [
                ChannelMediaList(channelId: widget.channelId),
                if (_hasRecipes)
                  ChannelPostsList(
                    channelId: widget.channelId,
                    channel: c,
                    postType: 'recipe',
                  ),
                ChannelAboutTab(channel: c, omitDescription: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
