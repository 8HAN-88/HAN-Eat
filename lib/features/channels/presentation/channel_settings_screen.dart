// Экран настроек канала
import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/channel_service.dart';
import '../../../services/channel_cache_service.dart';
import '../../../app/app_router.dart';
import '../application/channels_list_refresh_provider.dart';

class ChannelSettingsScreen extends ConsumerStatefulWidget {
  final int channelId;
  final String channelName;

  const ChannelSettingsScreen({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  ConsumerState<ChannelSettingsScreen> createState() =>
      _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends ConsumerState<ChannelSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();
  bool _isLoading = false;
  bool _isDeleting = false;
  bool _isPublic = true;

  /// Текущий slug с сервера — если название только кириллица, подставляем его (иначе slug из имени пустой).
  String _savedSlug = '';

  @override
  void initState() {
    super.initState();
    _loadChannelData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _loadChannelData() async {
    try {
      final channel = await ChannelService.getChannel(widget.channelId);
      setState(() {
        _savedSlug = channel.slug;
        _nameController.text = channel.name;
        _descriptionController.text = channel.description ?? '';
        _categoryController.text = channel.category ?? '';
        _isPublic = channel.isPublic;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить данные'))),
        );
      }
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Slug из латиницы/цифр в названии; длина — по результату (раньше брали длину названия → RangeError).
      // Кириллица в slug не попадает — оставляем прежний slug канала.
      final fromName = _slugFromChannelName(_nameController.text.trim());
      final slug =
          (fromName != null && fromName.isNotEmpty) ? fromName : _savedSlug;
      if (slug.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Укажите в названии латинские буквы или цифры для адреса канала, либо откройте редактирование в управлении каналом.',
              ),
            ),
          );
        }
        return;
      }

      await ChannelService.updateChannel(
        channelId: widget.channelId,
        name: _nameController.text.trim(),
        slug: slug,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        isPublic: _isPublic,
        category: _categoryController.text.trim().isEmpty
            ? null
            : _categoryController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки сохранены')),
        );
        context.pop(true); // Возвращаемся с успехом
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось сохранить'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmDeleteChannel() async {
    setState(() => _isDeleting = true);
    try {
      await ChannelService.deleteChannel(widget.channelId);
      await ChannelCacheService.invalidateChannelCache(widget.channelId);
      ref.read(channelsMainListRefreshProvider.notifier).state++;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Канал удалён')),
      );
      context.go(ChannelsListRoute.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось удалить канал'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  /// Латиница/цифры из названия; не длиннее 50. Пусто — если только кириллица и т.п.
  String? _slugFromChannelName(String name) {
    if (name.isEmpty) return null;
    var s = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'-+'), '_');
    while (s.contains('__')) {
      s = s.replaceAll('__', '_');
    }
    s = s.trim();
    if (s.startsWith('_')) s = s.substring(1);
    if (s.endsWith('_') && s.isNotEmpty) s = s.substring(0, s.length - 1);
    if (s.length > 50) s = s.substring(0, 50);
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Настройки: ${widget.channelName}'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _isDeleting ? null : _handleSave,
              child: const Text('Сохранить'),
            ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Название
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название канала',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Введите название';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Описание
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Описание',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                  ),
                  const SizedBox(height: 16),

                  // Категория
                  TextFormField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      labelText: 'Категория',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Публичность
                  Card(
                    child: SwitchListTile(
                      title: const Text('Публичный канал'),
                      subtitle:
                          const Text('Канал будет виден всем пользователям'),
                      value: _isPublic,
                      onChanged: (value) {
                        setState(() => _isPublic = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Раздел "Опасная зона"
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Опасная зона',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),

                  OutlinedButton.icon(
                    onPressed: _isDeleting
                        ? null
                        : () {
                            showDialog<void>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Удалить канал?'),
                                content: const Text(
                                  'Это действие нельзя отменить. Все посты и данные канала будут удалены.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: _isDeleting
                                        ? null
                                        : () =>
                                            Navigator.of(dialogContext).pop(),
                                    child: const Text('Отмена'),
                                  ),
                                  FilledButton(
                                    onPressed: _isDeleting
                                        ? null
                                        : () async {
                                            Navigator.of(dialogContext).pop();
                                            await _confirmDeleteChannel();
                                          },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: theme.colorScheme.error,
                                    ),
                                    child: const Text('Удалить'),
                                  ),
                                ],
                              ),
                            );
                          },
                    icon: Icon(Icons.delete_outline,
                        color: theme.colorScheme.error),
                    label: Text(
                      'Удалить канал',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isDeleting)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
