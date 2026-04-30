// Экран настроек канала
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/channel_service.dart';

class ChannelSettingsScreen extends ConsumerStatefulWidget {
  final int channelId;
  final String channelName;
  
  const ChannelSettingsScreen({
    Key? key,
    required this.channelId,
    required this.channelName,
  }) : super(key: key);
  
  @override
  ConsumerState<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends ConsumerState<ChannelSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();
  bool _isLoading = false;
  bool _isPublic = true;
  
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
        _nameController.text = channel.name;
        _descriptionController.text = channel.description ?? '';
        _categoryController.text = channel.category ?? '';
        _isPublic = channel.isPublic;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки данных: $e')),
        );
      }
    }
  }
  
  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Генерируем slug из названия
      final slug = _nameController.text
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_')
          .replaceAll(RegExp(r'-+'), '_')
          .substring(0, _nameController.text.length > 50 ? 50 : _nameController.text.length);
      
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
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
              onPressed: _handleSave,
              child: const Text('Сохранить'),
            ),
        ],
      ),
      body: Form(
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
                  subtitle: const Text('Канал будет виден всем пользователям'),
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
                onPressed: () {
                  // TODO: Удаление канала
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Удалить канал?'),
                      content: const Text('Это действие нельзя отменить. Все посты и данные канала будут удалены.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () {
                            // TODO: Реализовать удаление
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Функционал удаления будет добавлен позже')),
                            );
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
                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                label: Text(
                  'Удалить канал',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

