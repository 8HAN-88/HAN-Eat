// Экран управления каналом (для владельца и админов)
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/channel_service.dart';
import '../../../services/media_upload_service.dart';

class ChannelManagementScreen extends ConsumerStatefulWidget {
  final int channelId;

  const ChannelManagementScreen({
    Key? key,
    required this.channelId,
  }) : super(key: key);

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

  ChannelDetail? _channel;
  bool _isLoading = true;
  bool _isSaving = false;

  // Настройки
  bool _isPublic = true;
  bool _autoPublishToFeed = true;
  bool _autoPublishToMenu = true;
  bool _autoPublishReels = true;
  bool _allowComments = true;
  bool _allowLikes = true;
  bool _allowReposts = true;

  // Медиа
  final ImagePicker _imagePicker = ImagePicker();
  String? _newAvatarUrl;
  String? _newCoverUrl;
  XFile? _selectedAvatar;
  XFile? _selectedCover;
  Uint8List? _selectedAvatarBytes;

  // Участники
  List<Map<String, dynamic>> _members = [];
  bool _loadingMembers = false;

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
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadChannel() async {
    setState(() => _isLoading = true);

    try {
      final channel = await ChannelService.getChannel(widget.channelId);

      setState(() {
        _channel = channel;
        _nameController.text = channel.name;
        _slugController.text = channel.slug;
        _descriptionController.text = channel.description ?? '';
        _rulesController.text = channel.rules ?? '';
        _tagsController.text = channel.tags?.join(', ') ?? '';
        _isPublic = channel.isPublic;
        _autoPublishToFeed = channel.autoPublishToFeed ?? true;
        _autoPublishToMenu = channel.autoPublishToMenu ?? true;
        _autoPublishReels = channel.autoPublishReels;
        _allowComments = channel.allowComments ?? true;
        _allowLikes = channel.allowLikes ?? true;
        _allowReposts = channel.allowReposts ?? true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки канала: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
          SnackBar(content: Text('Ошибка загрузки участников: $e')),
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
          SnackBar(content: Text('Ошибка выбора аватара: $e')),
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
          SnackBar(content: Text('Ошибка выбора обложки: $e')),
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
        autoPublishToMenu: _autoPublishToMenu,
        autoPublishReels: _autoPublishReels,
        allowComments: _allowComments,
        allowLikes: _allowLikes,
        allowReposts: _allowReposts,
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
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
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
              backgroundColor: Colors.red,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ChannelService.deleteChannel(widget.channelId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Канал удален')),
        );
        context.go('/channels');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: $e')),
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
      return Scaffold(
        appBar: AppBar(title: const Text('Управление каналом')),
        body: const Center(child: Text('Канал не найден')),
      );
    }

    // Проверяем права доступа
    if (!_channel!.isOwner && !_channel!.isAdmin) {
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
          title: const Text('Управление каналом'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Основное'),
              Tab(text: 'Настройки'),
              Tab(text: 'Участники'),
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
                        ? NetworkImage(_newAvatarUrl ?? _channel!.avatarUrl!)
                            as ImageProvider
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

        // Slug
        TextFormField(
          controller: _slugController,
          decoration: const InputDecoration(
            labelText: 'URL-адрес (slug)',
            hintText: 'healthy_life',
            border: OutlineInputBorder(),
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
            border: OutlineInputBorder(),
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
            border: OutlineInputBorder(),
            helperText: 'Правила для участников',
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
            border: OutlineInputBorder(),
          ),
        ),
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
          title: const Text('Автоматически публиковать рецепты в Menu'),
          subtitle: const Text('Рецепты будут доступны в разделе Menu'),
          value: _autoPublishToMenu,
          onChanged: (value) => setState(() => _autoPublishToMenu = value),
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
        const Divider(),
        const SizedBox(height: 24),
        if (_channel!.isOwner)
          FilledButton.icon(
            onPressed: _deleteChannel,
            icon: const Icon(Icons.delete),
            label: const Text('Удалить канал'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
          ),
      ],
    );
  }

  Widget _buildMembersTab() {
    if (_loadingMembers) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Участники (${_members.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        ..._members.map((member) {
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: member['avatar_url'] != null
                  ? NetworkImage(member['avatar_url'])
                  : null,
              child: member['avatar_url'] == null
                  ? Text(member['name']?[0] ?? '?')
                  : null,
            ),
            title: Text(member['name'] ?? 'Без имени'),
            subtitle: Text(member['username'] ?? ''),
            trailing: Chip(
              label: Text(member['role'] ?? 'member'),
            ),
            onTap: () {
              if (_channel!.isOwner) {
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
                  'Управление участником',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                title: const Text('Администратор'),
                subtitle:
                    const Text('Может создавать посты и управлять участниками'),
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
                    'Может создавать посты и модерировать комментарии'),
                trailing:
                    currentRole == 'moderator' ? const Icon(Icons.check) : null,
                onTap: () async {
                  Navigator.pop(context);
                  await _updateMemberRole(userId, 'moderator');
                },
              ),
              ListTile(
                title: const Text('Участник'),
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
                title: const Text('Удалить из канала',
                    style: TextStyle(color: Colors.red)),
                leading: const Icon(Icons.person_remove, color: Colors.red),
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

      // Обновляем список участников
      await _loadMembers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Роль обновлена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления роли: $e')),
        );
      }
    }
  }

  Future<void> _removeMember(int userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: const Text('Участник будет удален из канала'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
          const SnackBar(content: Text('Участник удален')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: $e')),
        );
      }
    }
  }
}
