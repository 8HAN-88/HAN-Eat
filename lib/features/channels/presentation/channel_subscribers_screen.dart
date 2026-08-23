import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/channel_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_avatar.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/highlighted_text.dart';

class ChannelSubscribersScreen extends StatefulWidget {
  const ChannelSubscribersScreen({
    super.key,
    required this.channelId,
    this.channelName,
  });

  final int channelId;
  final String? channelName;

  @override
  State<ChannelSubscribersScreen> createState() =>
      _ChannelSubscribersScreenState();
}

class _ChannelSubscribersScreenState extends State<ChannelSubscribersScreen> {
  static const _pageSize = 50;

  final _subscribers = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  Future<void> _load({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final data = await ChannelService.getChannelMembers(
        channelId: widget.channelId,
        limit: _pageSize,
        offset: refresh ? 0 : _subscribers.length,
      );
      final raw = data['members'] as List<dynamic>? ?? const [];
      final items = raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _subscribers
            ..clear()
            ..addAll(items);
        } else {
          _subscribers.addAll(items);
        }
        _total = data['total'] as int? ?? _subscribers.length;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _openProfile(Map<String, dynamic> subscriber) {
    final rawId = subscriber['user_id'] ?? subscriber['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId');
    if (id == null || id <= 0) return;
    context.push(ProfileRoute.withUserId(id));
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final subtitle = widget.channelName?.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подписчики'),
        bottom: subtitle != null && subtitle.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: HighlightedText(
                    text: subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ) ??
                        const TextStyle(fontSize: 12),
                  ),
                ),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : error != null && _subscribers.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      AppEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Не удалось загрузить подписчиков',
                        subtitle: userVisibleError(
                          error,
                          fallback: 'Проверьте подключение',
                        ),
                        action: FilledButton(
                          onPressed: () => _load(refresh: true),
                          child: const Text('Повторить'),
                        ),
                      ),
                    ],
                  )
                : _subscribers.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          AppEmptyState(
                            icon: Icons.people_outline_rounded,
                            title: 'Подписчиков пока нет',
                            subtitle:
                                'Когда пользователи подпишутся на канал, они появятся здесь.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        itemCount: _subscribers.length + 1,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == _subscribers.length) {
                            if (_subscribers.length >= _total) {
                              return Padding(
                                padding: const EdgeInsets.all(18),
                                child: Center(
                                  child: Text(
                                    'Всего подписчиков: $_total',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : OutlinedButton(
                                        onPressed: () => _load(refresh: false),
                                        child: const Text('Загрузить ещё'),
                                      ),
                              ),
                            );
                          }
                          final subscriber = _subscribers[index];
                          final name = subscriber['name'] as String? ??
                              subscriber['username'] as String? ??
                              'Пользователь';
                          final username = subscriber['username'] as String?;
                          final avatarUrl = subscriber['avatar_url'] as String?;
                          final role = subscriber['role'] as String?;
                          return ListTile(
                            onTap: () => _openProfile(subscriber),
                            leading: CircleAvatar(
                              backgroundImage: resolvedAvatarImage(
                                avatarUrl,
                                decodeWidth: 96,
                              ),
                              child: resolvedAvatarImage(avatarUrl) == null
                                  ? Text(name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?')
                                  : null,
                            ),
                            title: HighlightedText(
                              text: name,
                              style: Theme.of(context).textTheme.bodyLarge ??
                                  const TextStyle(fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: username != null && username.isNotEmpty
                                ? Text('@$username')
                                : null,
                            trailing: role == 'owner'
                                ? const Chip(label: Text('Владелец'))
                                : role == 'admin'
                                    ? const Chip(label: Text('Админ'))
                                    : role == 'moderator'
                                        ? const Chip(label: Text('Модератор'))
                                        : null,
                          );
                        },
                      ),
      ),
    );
  }
}
