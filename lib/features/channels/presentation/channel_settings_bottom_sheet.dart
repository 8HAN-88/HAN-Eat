// Bottom sheet с настройками канала
import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/channel_notification_prefs.dart';
import '../../../services/channel_service.dart';
import '../../../services/channel_sheet_prefs.dart';
import '../../../widgets/report_content_dialog.dart';

class ChannelSettingsBottomSheet extends StatefulWidget {
  final ChannelDetail channel;
  final int channelId;
  final VoidCallback? onShare;
  final VoidCallback? onCopyLink;
  final VoidCallback? onSearch;
  final VoidCallback? onManage;
  final VoidCallback? onAnalytics;

  const ChannelSettingsBottomSheet({
    super.key,
    required this.channel,
    required this.channelId,
    this.onShare,
    this.onCopyLink,
    this.onSearch,
    this.onManage,
    this.onAnalytics,
  });

  @override
  State<ChannelSettingsBottomSheet> createState() =>
      _ChannelSettingsBottomSheetState();
}

class _ChannelSettingsBottomSheetState
    extends State<ChannelSettingsBottomSheet> {
  bool _notificationsEnabled = true;
  bool _showInFeed = true;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final enabled = await ChannelNotificationPrefs.getNotificationsEnabled(
        widget.channelId,
      );
      final inFeed = await ChannelSheetPrefs.getShowInFeed(widget.channelId);
      final fav = await ChannelSheetPrefs.getFavorite(widget.channelId);
      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
          _showInFeed = inFeed;
          _isFavorite = fav;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxSheetHeight = mq.size.height * 0.92;
    final bottomInset = mq.padding.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Заголовок
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.channel.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(),
            // Основные функции
            if (widget.onSearch != null)
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Поиск по каналу'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onSearch?.call();
                },
              ),
            if (widget.onShare != null)
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Поделиться каналом'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onShare?.call();
                },
              ),
            if (widget.onCopyLink != null)
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Скопировать ссылку'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onCopyLink?.call();
                },
              ),
            if (widget.onManage != null)
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Управление каналом'),
                onTap: () {
                  widget.onManage?.call();
                },
              ),
            if (widget.onAnalytics != null)
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('Аналитика'),
                onTap: () {
                  widget.onAnalytics?.call();
                },
              ),
            if (widget.onManage != null)
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Инструменты автора'),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(CreatorToolsRoute.path);
                },
              ),
            const Divider(),
            // Настройки
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Уведомления'),
              trailing: Switch(
                value: _notificationsEnabled,
                onChanged: widget.channel.isMember
                    ? (value) async {
                        try {
                          await ChannelNotificationPrefs
                              .setNotificationsEnabled(
                            widget.channelId,
                            value,
                          );
                          if (mounted) {
                            setState(() => _notificationsEnabled = value);
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                    userVisibleError(
                                      e,
                                      fallback: 'Не удалось сохранить',
                                    ),
                                  )),
                            );
                          }
                        }
                      }
                    : null,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.feed_outlined),
              title: const Text('Показ в разделе'),
              trailing: Switch(
                value: _showInFeed,
                onChanged: (value) async {
                  try {
                    await ChannelSheetPrefs.setShowInFeed(
                        widget.channelId, value);
                    if (mounted) setState(() => _showInFeed = value);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось сохранить'))),
                      );
                    }
                  }
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: Text(_isFavorite ? 'В избранном' : 'Добавить в избранное'),
              trailing: Icon(
                _isFavorite ? Icons.star : Icons.star_border,
                color: _isFavorite ? Colors.amber : null,
              ),
              onTap: () async {
                final next = !_isFavorite;
                try {
                  await ChannelSheetPrefs.setFavorite(widget.channelId, next);
                  if (mounted) setState(() => _isFavorite = next);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось сохранить'))),
                    );
                  }
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Информация о канале'),
              onTap: () {
                final id = widget.channelId;
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                Future.microtask(
                  () => router.push(
                    ChannelDetailRoute.info(
                      id,
                      channelName: widget.channel.name,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Пожаловаться'),
              onTap: () {
                final id = widget.channelId;
                final parentContext = context;
                Navigator.of(context).pop();
                Future.microtask(
                  () => reportChannelWithDialog(parentContext, id),
                );
              },
            ),
            if (widget.channel.isMember) ...[
              const Divider(),
              ListTile(
                leading: Icon(Icons.exit_to_app, color: Colors.red),
                title: Text(
                  'Отписаться',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  try {
                    await ChannelService.leaveChannel(widget.channelId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Вы отписались от канала')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(userVisibleError(e))),
                      );
                    }
                  }
                },
              ),
            ],
            SizedBox(height: bottomInset > 0 ? bottomInset : 12),
          ],
        ),
      ),
    );
  }
}
