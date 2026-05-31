// Экран создания канала
import 'dart:io';
import '../../../utils/api_error_parser.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/channel_service.dart';
import '../../../services/media_upload_service.dart';
import 'package:go_router/go_router.dart';

class CreateChannelScreen extends ConsumerStatefulWidget {
  const CreateChannelScreen({super.key});

  static const routeName = '/create-channel';

  @override
  ConsumerState<CreateChannelScreen> createState() =>
      _CreateChannelScreenState();
}

class _CreateChannelScreenState extends ConsumerState<CreateChannelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  late final TextEditingController _categoryController =
      TextEditingController();
  bool _isLoading = false;
  bool _isPublic = true;

  // Медиа
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedAvatar;
  String? _uploadedAvatarUrl;
  bool _isUploadingAvatar = false;
  Uint8List? _selectedAvatarBytes;

  // Популярные категории
  static const List<String> _categories = [
    'Итальянская',
    'Азиатская',
    'Веган',
    'Быстрое',
    'ЗОЖ',
    'Выпечка',
    'Десерты',
    'Супы',
    'Салаты',
    'Мясо',
    'Рыба',
    'Вегетарианская',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  String _generateSlug(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'-+'), '_')
        .substring(0, name.length > 50 ? 50 : name.length);
  }

  void _updateSlug() {
    if (_nameController.text.isNotEmpty) {
      _slugController.text = _generateSlug(_nameController.text);
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
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
          _isUploadingAvatar = true;
        });

        try {
          final response = await MediaUploadService.uploadMediaFile(
            file: image,
            fileType: 'image',
          );
          // Используем url из ответа, если нет - используем cdnUrl из initResponse
          final url = response.url;
          if (url == null) {
            throw Exception('Не удалось получить URL загруженного изображения');
          }
          setState(() {
            _uploadedAvatarUrl = url;
            _isUploadingAvatar = false;
          });
        } catch (e) {
          setState(() => _isUploadingAvatar = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить аватар'))),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось выбрать изображение'))),
        );
      }
    }
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isUploadingAvatar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Дождитесь завершения загрузки аватара')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final channel = await ChannelService.createChannel(
        name: _nameController.text.trim(),
        slug: _slugController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        avatarUrl: _uploadedAvatarUrl,
        isPublic: _isPublic,
        category: _categoryController.text.trim().isEmpty
            ? null
            : _categoryController.text.trim(),
      );

      if (mounted) {
        context.pop(channel.id); // Возвращаемся с ID созданного канала
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Канал создан')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось создать канал'))),
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                // Аватар
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[300],
                          backgroundImage: _selectedAvatar != null
                              ? (kIsWeb && _selectedAvatarBytes != null
                                  ? MemoryImage(_selectedAvatarBytes!)
                                      as ImageProvider
                                  : !kIsWeb
                                      ? FileImage(File(_selectedAvatar!.path))
                                          as ImageProvider
                                      : null)
                              : _uploadedAvatarUrl != null
                                  ? NetworkImage(_uploadedAvatarUrl!)
                                      as ImageProvider
                                  : null,
                          child: _selectedAvatar == null &&
                                  _uploadedAvatarUrl == null
                              ? const Icon(Icons.add_photo_alternate, size: 40)
                              : null,
                        ),
                        if (_isUploadingAvatar)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _pickAvatar,
                    child: const Text('Выбрать аватар'),
                  ),
                ),
                const SizedBox(height: 16),
                // Название
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Название канала',
                    hintText: 'Например: Веганские рецепты',
                    prefixIcon: Icon(Icons.tag),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _updateSlug(),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Введите название';
                    }
                    if (value.length < 3) {
                      return 'Минимум 3 символа';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Slug
                TextFormField(
                  controller: _slugController,
                  decoration: const InputDecoration(
                    labelText: 'URL идентификатор',
                    hintText: 'vegan_recipes',
                    prefixIcon: Icon(Icons.link),
                    border: OutlineInputBorder(),
                    helperText: 'Используется в URL канала',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Введите идентификатор';
                    }
                    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(value)) {
                      return 'Только латиница, цифры и подчеркивание';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Описание
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Описание (опционально)',
                    hintText: 'Расскажите о вашем канале...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  minLines: 3,
                ),
                const SizedBox(height: 16),
                // Категория
                Autocomplete<String>(
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return _categories;
                    }
                    return _categories.where((category) => category
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase()));
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                    // Синхронизируем внешний контроллер с внутренним
                    if (controller.text != _categoryController.text) {
                      _categoryController.text = controller.text;
                    }
                    controller.addListener(() {
                      _categoryController.text = controller.text;
                    });
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Категория (опционально)',
                        hintText: 'Выберите или введите категорию',
                        prefixIcon: Icon(Icons.category),
                        border: OutlineInputBorder(),
                        helperText: 'Например: Итальянская, Веган, Быстрое',
                      ),
                    );
                  },
                  onSelected: (value) {
                    _categoryController.text = value;
                  },
                ),
                const SizedBox(height: 24),
                // Публичность
                Card(
                  child: SwitchListTile(
                    title: const Text('Публичный канал'),
                    subtitle: Text(
                      _isPublic
                          ? 'Канал будет виден всем пользователям'
                          : 'Приватный канал — только для подписчиков',
                    ),
                    value: _isPublic,
                    onChanged: (value) {
                      setState(() => _isPublic = value);
                    },
                  ),
                ),
                if (!_isPublic) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Рецепты в приватном канале — индивидуальный контент: '
                              'они не попадают в общий Menu и доступны только здесь. '
                              'Публикация рецептов — с тарифом H.A.N. Creator или Pro.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                // Кнопка создания
                FilledButton(
                  onPressed: _isLoading ? null : _handleCreate,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Создать канал'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
