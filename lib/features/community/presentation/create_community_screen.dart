import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../../models/community.dart';
import '../../../services/community_management_service.dart';
import '../../../services/auth_service.dart';

/// Экран создания канала
class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _websiteController = TextEditingController();
  final _vkController = TextEditingController();
  final _instagramController = TextEditingController();
  final _telegramController = TextEditingController();
  final _youtubeController = TextEditingController();

  String? _selectedCategory;
  File? _avatarFile;
  File? _coverFile;
  XFile? _avatarXFile;
  XFile? _coverXFile;
  Uint8List? _avatarBytes;
  Uint8List? _coverBytes;
  bool _commentsEnabled = true;
  bool _messagesEnabled = true;
  bool _isLoading = false;

  final List<String> _foodCategories = [
    'Рецепты',
    'Выпечка',
    'Десерты',
    'Салаты',
    'Супы',
    'Горячие блюда',
    'Завтраки',
    'Напитки',
    'Веганская кухня',
    'Азиатская кухня',
    'Итальянская кухня',
    'Другое',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _websiteController.dispose();
    _vkController.dispose();
    _instagramController.dispose();
    _telegramController.dispose();
    _youtubeController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isAvatar) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        if (isAvatar) {
          _avatarXFile = image;
          if (kIsWeb) {
            // На вебе используем bytes
            image.readAsBytes().then((bytes) {
              setState(() => _avatarBytes = bytes);
            });
          } else {
            _avatarFile = File(image.path);
          }
        } else {
          _coverXFile = image;
          if (kIsWeb) {
            // На вебе используем bytes
            image.readAsBytes().then((bytes) {
              setState(() => _coverBytes = bytes);
            });
          } else {
            _coverFile = File(image.path);
          }
        }
      });
    }
  }

  Future<void> _createCommunity() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите тематику')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final settings = CommunitySettings(
        commentsEnabled: _commentsEnabled,
        messagesEnabled: _messagesEnabled,
        website: _websiteController.text.isEmpty ? null : _websiteController.text,
        vkLink: _vkController.text.isEmpty ? null : _vkController.text,
        instagramLink: _instagramController.text.isEmpty ? null : _instagramController.text,
        telegramLink: _telegramController.text.isEmpty ? null : _telegramController.text,
        youtubeLink: _youtubeController.text.isEmpty ? null : _youtubeController.text,
      );

      // Для веба используем bytes, для других платформ - path
      final community = await CommunityManagementService.createCommunity(
        name: _nameController.text,
        category: _selectedCategory!,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        avatarPath: kIsWeb ? null : _avatarFile?.path,
        coverPath: kIsWeb ? null : _coverFile?.path,
        avatarBytes: kIsWeb ? _avatarBytes : null,
        coverBytes: kIsWeb ? _coverBytes : null,
        settings: settings,
      );

      if (mounted) {
        Navigator.of(context).pop(community);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Создать канал'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _createCommunity,
              child: const Text('Создать'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Аватар и обложка
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickImage(true),
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: (_avatarFile != null || _avatarBytes != null)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: kIsWeb && _avatarBytes != null
                                  ? Image.memory(_avatarBytes!, fit: BoxFit.cover)
                                  : _avatarFile != null
                                      ? Image.file(_avatarFile!, fit: BoxFit.cover)
                                      : const Icon(Icons.add_photo_alternate, size: 40),
                            )
                          : const Icon(Icons.add_photo_alternate, size: 40),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => _pickImage(false),
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: (_coverFile != null || _coverBytes != null)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: kIsWeb && _coverBytes != null
                                  ? Image.memory(_coverBytes!, fit: BoxFit.cover)
                                  : _coverFile != null
                                      ? Image.file(_coverFile!, fit: BoxFit.cover)
                                      : const Icon(Icons.add_photo_alternate, size: 40),
                            )
                          : const Icon(Icons.add_photo_alternate, size: 40),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Название
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Название канала *',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value?.isEmpty ?? true ? 'Введите название' : null,
            ),
            const SizedBox(height: 16),

            // Тематика
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Тематика *',
                border: OutlineInputBorder(),
              ),
              items: _foodCategories.map((category) {
                return DropdownMenuItem(value: category, child: Text(category));
              }).toList(),
              onChanged: (value) => setState(() => _selectedCategory = value),
            ),
            const SizedBox(height: 16),

            // Описание
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Описание',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),

            // Ссылки
            TextFormField(
              controller: _websiteController,
              decoration: const InputDecoration(
                labelText: 'Сайт',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.language),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _vkController,
              decoration: const InputDecoration(
                labelText: 'VK',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _instagramController,
              decoration: const InputDecoration(
                labelText: 'Instagram',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _telegramController,
              decoration: const InputDecoration(
                labelText: 'Telegram',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _youtubeController,
              decoration: const InputDecoration(
                labelText: 'YouTube',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 16),

            // Настройки
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Комментарии'),
                    subtitle: const Text('Разрешить комментарии к постам'),
                    value: _commentsEnabled,
                    onChanged: (value) => setState(() => _commentsEnabled = value),
                  ),
                  SwitchListTile(
                    title: const Text('Сообщения'),
                    subtitle: const Text('Разрешить сообщения канала'),
                    value: _messagesEnabled,
                    onChanged: (value) => setState(() => _messagesEnabled = value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

