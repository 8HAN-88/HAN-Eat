// Bottom sheet с настройками канала
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/channel_service.dart';

class ChannelSettingsBottomSheet extends StatefulWidget {
  final ChannelDetail channel;
  final int channelId;
  final VoidCallback? onShare;
  final VoidCallback? onCopyLink;
  final VoidCallback? onSearch;
  final VoidCallback? onManage;
  
  const ChannelSettingsBottomSheet({
    Key? key,
    required this.channel,
    required this.channelId,
    this.onShare,
    this.onCopyLink,
    this.onSearch,
    this.onManage,
  }) : super(key: key);
  
  @override
  State<ChannelSettingsBottomSheet> createState() => _ChannelSettingsBottomSheetState();
}

class _ChannelSettingsBottomSheetState extends State<ChannelSettingsBottomSheet> {
  bool _notificationsEnabled = true;
  bool _showInFeed = true;
  bool _isFavorite = false;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ручка
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Заголовок
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  widget.channel.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
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
          const Divider(),
          // Настройки
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Уведомления'),
            trailing: Switch(
              value: _notificationsEnabled,
              onChanged: (value) {
                setState(() => _notificationsEnabled = value);
                // TODO: Сохранить настройку
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.feed_outlined),
            title: const Text('Показ в разделе'),
            trailing: Switch(
              value: _showInFeed,
              onChanged: (value) {
                setState(() => _showInFeed = value);
                // TODO: Сохранить настройку
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: const Text('Добавить в избранное'),
            trailing: Icon(
              _isFavorite ? Icons.star : Icons.star_border,
              color: _isFavorite ? Colors.amber : null,
            ),
            onTap: () {
              setState(() => _isFavorite = !_isFavorite);
              // TODO: Сохранить в избранное
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Информация о канале'),
            onTap: () {
              Navigator.of(context).pop();
              // TODO: Показать информацию
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Пожаловаться'),
            onTap: () {
              Navigator.of(context).pop();
              // TODO: Показать форму жалобы
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
                      const SnackBar(content: Text('Вы отписались от канала')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
                  }
                }
              },
            ),
          ],
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

