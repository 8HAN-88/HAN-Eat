// Экран управления каналом (для владельца и админов)
import 'dart:io';
import '../../../utils/api_error_parser.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/channel_service.dart';
import '../../../services/channel_cache_service.dart';
import '../../../services/media_upload_service.dart';
import '../../../app/app_router.dart';
import '../application/channels_list_refresh_provider.dart';
import '../../../core/layout/long_label_tab_bar.dart';
import '../../../widgets/app_avatar.dart';
import '../../chat/application/join_requests_bulk.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../../widgets/app_empty_state.dart';

const _permissionLabels = <String, (String, String)>{
  'manage_channel_settings': (
    'Настройки канала',
    'Название, описание, обложка, правила и настройки публикации',
  ),
  'manage_subscribers': (
    'Управление подписчиками',
    'Менять роли и удалять подписчиков из канала',
  ),
  'manage_join_requests': (
    'Заявки на подписку',
    'Одобрять и отклонять заявки в приватный канал',
  ),
  'create_posts': (
    'Публикация постов',
    'Создавать посты, медиа и рилсы в канале',
  ),
  'edit_any_post': (
    'Редактирование чужих постов',
    'Править публикации других авторов канала',
  ),
  'delete_any_post': (
    'Удаление чужих постов',
    'Удалять публикации других авторов канала',
  ),
};

class ChannelManagementScreen extends ConsumerStatefulWidget {
  final int channelId;

  const ChannelManagementScreen({
    super.key,
    required this.channelId,
  });

  @override
  ConsumerState<ChannelManagementScreen> createState() =>
      _ChannelManagementScreenState();
}

class _ChannelManagementScreenState
    extends ConsumerState<ChannelManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rulesController = TextEditingController();
  final _tagsController = TextEditingController();
  final _accentColorController = TextEditingController();

  ChannelDetail? _channel;
  Object? _channelLoadError;
  bool _isLoading = true;
  bool _isSaving = false;

  // Настройки
  bool _isPublic = true;
  bool _autoPublishToFeed = true;
  bool _autoPublishReels = true;
  bool _allowComments = true;
  bool _allowLikes = true;
  bool _allowReposts = true;
  Map<String, Map<String, bool>> _rolePermissions =
      defaultChannelRolePermissions();

  // Медиа
  final ImagePicker _imagePicker = ImagePicker();
  String? _newAvatarUrl;
  String? _newCoverUrl;
  XFile? _selectedAvatar;
  XFile? _selectedCover;
  Uint8List? _selectedAvatarBytes;

  // Подписчики
  List<Map<String, dynamic>> _members = [];
  bool _loadingMembers = false;
  List<ChannelJoinRequest> _joinRequests = [];
  bool _loadingJoinRequests = false;

  @override
  void initState() {
    super.initState();
    _loadChannel();
    _loadMembers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _descriptionController.dispose();
    _rulesController.dispose();
    _accentColorController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadChannel() async {
    setState(() {
      _isLoading = true;
      _channelLoadError = null;
    });

    try {
      final channel = await ChannelService.getChannel(widget.channelId);

      setState(() {
        _channel = channel;
        _channelLoadError = null;
        _nameController.text = channel.name;
        _slugController.text = channel.slug;
        _descriptionController.text = channel.description ?? '';
        _rulesController.text = channel.rules ?? '';
        _tagsController.text = channel.tags?.join(', ') ?? '';
        _accentColorController.text = channel.accentColor ?? '';
        _isPublic = channel.isPublic;
        _autoPublishToFeed = channel.autoPublishToFeed ?? true;
        _autoPublishReels = channel.autoPublishReels;
        _allowComments = channel.allowComments ?? true;
        _allowLikes = channel.allowLikes ?? true;
        _allowReposts = channel.allowReposts ?? true;
        _rolePermissions = _cloneRolePermissions(channel.rolePermissions);
      });
      await _loadJoinRequests();
    } catch (e) {
      if (mounted) {
        setState(() => _channelLoadError = e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadJoinRequests() async {
    setState(() => _loadingJoinRequests = true);
    try {
      if (_channel != null && !_channel!.canManageJoinRequests) {
        if (mounted) {
          setState(() => _joinRequests = []);
        }
        return;
      }
      final response = await ChannelService.getChannelJoinRequests(
        widget.channelId,
      );
      if (mounted) {
        setState(() => _joinRequests = response.items);
      }
    } catch (e) {
      if (mounted && _channel != null) {
        if (_channel!.canManageJoinRequests) {
          debugPrint('Join requests load: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _loadingJoinRequests = false);
    }
  }

  Future<void> _approveJoinRequest(ChannelJoinRequest request) async {
    try {
      await ChannelService.approveChannelJoinRequest(
        widget.channelId,
        request.userId,
      );
      await _loadJoinRequests();
      await _loadMembers();
      await _loadChannel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заявка одобрена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  Future<void> _rejectJoinRequest(ChannelJoinRequest request) async {
    try {
      await ChannelService.rejectChannelJoinRequest(
        widget.channelId,
        request.userId,
      );
      await _loadJoinRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заявка отклонена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  Future<void> _reviewAllJoinRequests({required bool approve}) async {
    final items = List<ChannelJoinRequest>.from(_joinRequests);
    if (items.isEmpty) return;
    if (!approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Отклонить все заявки?'),
          content: Text('Будет отклонено: ${items.length}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отклонить все'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final result = await reviewJoinRequestsBulk<ChannelJoinRequest>(
      items: items,
      review: (request) => approve
          ? ChannelService.approveChannelJoinRequest(
              widget.channelId,
              request.userId,
            )
          : ChannelService.rejectChannelJoinRequest(
              widget.channelId,
              request.userId,
            ),
    );
    if (!mounted) return;
    await _loadJoinRequests();
    if (approve) {
      await _loadMembers();
      await _loadChannel();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          joinRequestsBulkSnackMessage(approve: approve, result: result),
        ),
      ),
    );
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);

    try {
      final response = await ChannelService.getChannelMembers(
        channelId: widget.channelId,
        limit: 50,
      );

      setState(() {
        _members = (response['members'] as List<dynamic>?)
                ?.map((m) => m as Map<String, dynamic>)
                .toList() ??
            [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(userVisibleError(e,
                  fallback: 'Не удалось загрузить подписчиков'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMembers = false);
      }
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 90,
      );

      if (image != null) {
        // Для веб-платформы читаем байты
        Uint8List? bytes;
        if (kIsWeb) {
          bytes = await image.readAsBytes();
        }

        setState(() {
          _selectedAvatar = image;
          _selectedAvatarBytes = bytes;
        });
        // Загружаем сразу
        final response = await MediaUploadService.uploadMediaFile(
          file: image,
          fileType: 'image',
        );
        final url = response.url;
        if (url != null && url.isNotEmpty) {
          setState(() => _newAvatarUrl = url);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  userVisibleError(e, fallback: 'Не удалось выбрать аватар'))),
        );
      }
    }
  }

  Future<void> _pickCover() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() => _selectedCover = image);
        // Загружаем сразу
        final response = await MediaUploadService.uploadMediaFile(
          file: image,
          fileType: 'image',
        );
        final url = response.url;
        if (url != null) {
          setState(() => _newCoverUrl = url);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  userVisibleError(e, fallback: 'Не удалось выбрать обложку'))),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final tags = _tagsController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      await ChannelService.updateChannel(
        channelId: widget.channelId,
        name: _nameController.text.trim(),
        slug: _slugController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        coverUrl: _newCoverUrl,
        avatarUrl: _newAvatarUrl,
        isPublic: _isPublic,
        category: _channel?.category,
        tags: tags.isNotEmpty ? tags : null,
        rules: _rulesController.text.trim().isNotEmpty
            ? _rulesController.text.trim()
            : null,
        autoPublishToFeed: _autoPublishToFeed,
        autoPublishReels: _autoPublishReels,
        allowComments: _allowComments,
        allowLikes: _allowLikes,
        allowReposts: _allowReposts,
        rolePermissions: _channel?.isOwner == true ? _rolePermissions : null,
        accentColor: _accentColorController.text.trim().isNotEmpty
            ? _accentColorController.text.trim()
            : '',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки сохранены')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(userVisibleError(e, fallback: 'Не удалось сохранить'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Map<String, Map<String, bool>> _cloneRolePermissions(
    Map<String, Map<String, bool>> source,
  ) {
    return {
      for (final role in const ['admin', 'moderator'])
        role: {
          ...defaultChannelRolePermissions()[role]!,
          ...?source[role],
        },
    };
  }

  void _setRolePermission(String role, String permission, bool value) {
    setState(() {
      _rolePermissions = _cloneRolePermissions(_rolePermissions);
      _rolePermissions[role]![permission] = value;
    });
  }

  Future<void> _deleteChannel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить канал?'),
        content: const Text(
          'Это действие нельзя отменить. Все посты и данные канала будут удалены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ChannelService.deleteChannel(widget.channelId);
      await ChannelCacheService.invalidateChannelCache(widget.channelId);
      ref.read(channelsMainListRefreshProvider.notifier).state++;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Канал удален')),
        );
        context.go(ChatsRoute.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(userVisibleError(e, fallback: 'Не удалось удалить'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Управление каналом')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_channel == null) {
      if (_channelLoadError != null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Управление каналом')),
          body: AppEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Не удалось загрузить',
            subtitle: userVisibleError(
              _channelLoadError!,
              fallback: 'Проверьте сеть',
            ),
            action: FilledButton(
              onPressed: _loadChannel,
              child: const Text('Повторить'),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Управление каналом')),
        body: const AppEmptyState(
          icon: Icons.group_off_outlined,
          title: 'Канал не найден',
          subtitle: 'Возможно, он удалён или у вас нет доступа',
        ),
      );
    }

    final canOpenManagement = _channel!.canManageChannelSettings ||
        _channel!.canManageSubscribers ||
        _channel!.canManageJoinRequests;
    if (!canOpenManagement) {
      return Scaffold(
        appBar: AppBar(title: const Text('Управление каналом')),
        body: const Center(
          child: Text('У вас нет прав для управления этим каналом'),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Expanded(child: Text('Управление каналом')),
              if ((_channel?.pendingJoinRequestsCount ?? 0) > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_channel!.pendingJoinRequestsCount}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onError,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          bottom: longLabelTabBar(
            tabs: const [
              Tab(text: 'Основное'),
              Tab(text: 'Настройки'),
              Tab(text: 'Подписчики'),
            ],
          ),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _save,
                tooltip: 'Сохранить',
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: TabBarView(
            children: [
              _buildBasicTab(),
              _buildSettingsTab(),
              _buildMembersTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Аватар
        Center(
          child: Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage: _selectedAvatar != null
                    ? (kIsWeb && _selectedAvatarBytes != null
                        ? MemoryImage(_selectedAvatarBytes!) as ImageProvider
                        : !kIsWeb
                            ? FileImage(File(_selectedAvatar!.path))
                                as ImageProvider
                            : null)
                    : (_newAvatarUrl != null || _channel?.avatarUrl != null)
                        ? resolvedAvatarImage(
                            _newAvatarUrl ?? _channel?.avatarUrl,
                            decodeWidth: 200,
                          )
                        : null,
                child: (_selectedAvatar == null &&
                        _newAvatarUrl == null &&
                        _channel?.avatarUrl == null)
                    ? Text(
                        _channel?.name[0].toUpperCase() ?? '?',
                        style: const TextStyle(fontSize: 40),
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.camera_alt),
                  onPressed: _pickAvatar,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Название
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Название канала',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Введите название';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Slug
        TextFormField(
          controller: _slugController,
          decoration: const InputDecoration(
            labelText: 'URL-адрес (slug)',
            hintText: 'healthy_life',
            helperText: 'Используется в URL канала',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Введите slug';
            }
            if (!RegExp(r'^[a-z0-9_]+$').hasMatch(value.trim())) {
              return 'Только латинские буквы, цифры и подчеркивания';
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
            helperText: 'До 500 символов',
          ),
          maxLines: 5,
          maxLength: 500,
        ),
        const SizedBox(height: 16),

        // Правила канала
        TextFormField(
          controller: _rulesController,
          decoration: const InputDecoration(
            labelText: 'Правила канала',
            helperText: 'Правила для подписчиков',
          ),
          maxLines: 5,
        ),
        const SizedBox(height: 16),

        // Теги
        TextFormField(
          controller: _tagsController,
          decoration: const InputDecoration(
            labelText: 'Теги (через запятую)',
            hintText: 'выпечка, здоровое, завтрак',
          ),
        ),
        if (ref.watch(subscriptionStatusProvider).asData?.value?.hasCreator ??
            false) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _accentColorController,
            decoration: const InputDecoration(
              labelText: 'Цвет акцента канала',
              hintText: '#FF6B35',
              helperText: 'Оформление Creator: HEX-цвет бейджа и акцентов',
            ),
          ),
        ],
        const SizedBox(height: 24),

        // Публичность
        SwitchListTile(
          title: const Text('Публичный канал'),
          subtitle: const Text('Доступен для всех пользователей'),
          value: _isPublic,
          onChanged: (value) => setState(() => _isPublic = value),
        ),
      ],
    );
  }


  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Публикация',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Автоматически публиковать в общую ленту'),
          subtitle: const Text('Посты будут появляться в общей ленте'),
          value: _autoPublishToFeed,
          onChanged: (value) => setState(() => _autoPublishToFeed = value),
        ),
        SwitchListTile(
          title: const Text('Автоматически публиковать рилсы'),
          subtitle: const Text('Короткие видео сразу попадают в раздел Reels'),
          value: _autoPublishReels,
          onChanged: (value) => setState(() => _autoPublishReels = value),
        ),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Взаимодействие',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Разрешить комментарии'),
          value: _allowComments,
          onChanged: (value) => setState(() => _allowComments = value),
        ),
        SwitchListTile(
          title: const Text('Разрешить лайки'),
          value: _allowLikes,
          onChanged: (value) => setState(() => _allowLikes = value),
        ),
        SwitchListTile(
          title: const Text('Разрешить репосты'),
          value: _allowReposts,
          onChanged: (value) => setState(() => _allowReposts = value),
        ),
        if (_channel?.isOwner == true) ...[
          const Divider(),
          const SizedBox(height: 16),
          _buildRolePermissionsSection(),
        ],
        const Divider(),
        const SizedBox(height: 24),
        if (_channel!.isOwner)
          FilledButton.icon(
            onPressed: _deleteChannel,
            icon: const Icon(Icons.delete),
            label: const Text('Удалить канал'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }

  Widget _buildRolePermissionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Права ролей',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Владелец всегда имеет все права. Здесь можно ограничить админов и модераторов.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        _buildRolePermissionCard(
          role: 'admin',
          title: 'Админы',
          subtitle: 'По умолчанию могут управлять каналом и подписчиками.',
        ),
        const SizedBox(height: 12),
        _buildRolePermissionCard(
          role: 'moderator',
          title: 'Модераторы',
          subtitle: 'По умолчанию могут публиковать и модерировать посты.',
        ),
      ],
    );
  }

  Widget _buildRolePermissionCard({
    required String role,
    required String title,
    required String subtitle,
  }) {
    final permissions = _rolePermissions[role] ?? const <String, bool>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(title),
              subtitle: Text(subtitle),
            ),
            for (final item in _permissionLabels.entries)
              CheckboxListTile(
                dense: true,
                value: permissions[item.key] ?? false,
                onChanged: (value) =>
                    _setRolePermission(role, item.key, value ?? false),
                title: Text(item.value.$1),
                subtitle: Text(item.value.$2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersTab() {
    if (_loadingMembers && _loadingJoinRequests) {
      return const Center(child: CircularProgressIndicator());
    }

    final canManageJoinRequests = _channel?.canManageJoinRequests ?? false;
    final canManageSubscribers = _channel?.canManageSubscribers ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canManageJoinRequests && _joinRequests.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Заявки на подписку (${_joinRequests.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_joinRequests.length > 1) ...[
                TextButton(
                  onPressed: () => _reviewAllJoinRequests(approve: false),
                  child: const Text('Отклонить все'),
                ),
                FilledButton(
                  onPressed: () => _reviewAllJoinRequests(approve: true),
                  child: const Text('Принять все'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ..._joinRequests.map((request) {
            final user = request.user;
            final name = user?['name'] as String? ??
                user?['username'] as String? ??
                'Пользователь';
            final avatar = user?['avatar_url'] as String?;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: resolvedAvatarImage(avatar, decodeWidth: 96),
                  child: resolvedAvatarImage(avatar) == null
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                      : null,
                ),
                title: Text(name),
                subtitle: Text(user?['username'] as String? ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Одобрить',
                      icon: const Icon(Icons.check_circle_outline),
                      color: Colors.green,
                      onPressed: () => _approveJoinRequest(request),
                    ),
                    IconButton(
                      tooltip: 'Отклонить',
                      icon: const Icon(Icons.cancel_outlined),
                      color: Theme.of(context).colorScheme.error,
                      onPressed: () => _rejectJoinRequest(request),
                    ),
                  ],
                ),
              ),
            );
          }),
          const Divider(height: 32),
        ],
        Text(
          'Подписчики (${_members.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (_members.isEmpty)
          const AppEmptyState(
            icon: Icons.people_outline_rounded,
            title: 'Нет подписчиков',
            subtitle: 'Подписчики канала появятся здесь',
          )
        else
          ..._members.map((member) {
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: resolvedAvatarImage(
                  member['avatar_url'] as String?,
                  decodeWidth: 96,
                ),
                child: resolvedAvatarImage(member['avatar_url'] as String?) ==
                        null
                    ? Text(member['name']?[0] ?? '?')
                    : null,
              ),
              title: Text(member['name'] ?? 'Без имени'),
              subtitle: Text(member['username'] ?? ''),
              trailing: Chip(
                label: Text(member['role'] ?? 'member'),
              ),
              onTap: () {
                if (canManageSubscribers) {
                  _showMemberRoleMenu(member);
                }
              },
            );
          }),
      ],
    );
  }

  void _showMemberRoleMenu(Map<String, dynamic> member) {
    final currentRole = member['role'] as String? ?? 'member';
    final userId = member['user_id'] as int?;
    if (userId == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Управление подписчиком',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                title: const Text('Администратор'),
                subtitle: const Text(
                    'Права администратора настраиваются владельцем ниже'),
                trailing:
                    currentRole == 'admin' ? const Icon(Icons.check) : null,
                onTap: () async {
                  Navigator.pop(context);
                  await _updateMemberRole(userId, 'admin');
                },
              ),
              ListTile(
                title: const Text('Модератор'),
                subtitle: const Text(
                    'Права модератора настраиваются владельцем ниже'),
                trailing:
                    currentRole == 'moderator' ? const Icon(Icons.check) : null,
                onTap: () async {
                  Navigator.pop(context);
                  await _updateMemberRole(userId, 'moderator');
                },
              ),
              ListTile(
                title: const Text('Подписчик'),
                subtitle: const Text('Обычный подписчик'),
                trailing:
                    currentRole == 'member' ? const Icon(Icons.check) : null,
                onTap: () async {
                  Navigator.pop(context);
                  await _updateMemberRole(userId, 'member');
                },
              ),
              const Divider(),
              ListTile(
                title: Text(
                  'Удалить из канала',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                leading: Icon(
                  Icons.person_remove,
                  color: Theme.of(context).colorScheme.error,
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _removeMember(userId);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateMemberRole(int userId, String role) async {
    try {
      await ChannelService.updateChannelMemberRole(
        channelId: widget.channelId,
        userId: userId,
        role: role,
      );

      // Обновляем список подписчиков
      await _loadMembers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Роль обновлена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  userVisibleError(e, fallback: 'Не удалось обновить роль'))),
        );
      }
    }
  }

  Future<void> _removeMember(int userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить подписчика?'),
        content: const Text('Подписчик будет удален из канала'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ChannelService.removeChannelMember(
        channelId: widget.channelId,
        userId: userId,
      );

      await _loadMembers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Подписчик удален')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(userVisibleError(e, fallback: 'Не удалось удалить'))),
        );
      }
    }
  }
}
