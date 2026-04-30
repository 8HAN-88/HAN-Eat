// Экран создания поста в канале с выбором типа (текст, фото, рецепт, видео)
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../models/post_model.dart';
import '../../../services/channel_service.dart';
import '../../../services/media_upload_service.dart';
import '../../../utils/file_helper.dart';
import '../../../widgets/telegram_photo_grid.dart';

class CreateChannelPostScreen extends ConsumerStatefulWidget {
  final int channelId;
  final String postType;
  final int? postId; // Если указан, то режим редактирования
  final Map<String, dynamic>? postData; // Данные поста для редактирования

  const CreateChannelPostScreen({
    Key? key,
    required this.channelId,
    this.postType = 'text',
    this.postId,
    this.postData,
  }) : super(key: key);

  @override
  ConsumerState<CreateChannelPostScreen> createState() =>
      _CreateChannelPostScreenState();
}

class _CreateChannelPostScreenState
    extends ConsumerState<CreateChannelPostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Выбор типа поста
  String _selectedPostType = 'text'; // text, photo, recipe, reel

  // Медиа
  final ImagePicker _imagePicker = ImagePicker();
  List<XFile> _selectedImages =
      []; // Список выбранных изображений (как в Telegram)
  XFile? _selectedVideo;
  XFile? _thumbnailImage; // Для видео
  List<String> _uploadedMediaUrls = [];
  int? _selectedVideoBytes;
  bool _channelAutoPublishReels = true;
  bool _sendToReels = true;
  VideoPlayerController? _videoPreviewController;
  Future<void>? _videoPreviewFuture;
  bool _videoPreviewError = false;
  bool _isPreviewPlaying = false;
  String? _uploadedVideoThumbnailUrl;
  bool _videoProcessing = false;
  bool _isUploadingMedia = false;
  double _uploadProgress = 0.0;

  // Для рецепта
  final List<TextEditingController> _ingredientControllers = [];
  final List<TextEditingController> _stepControllers = [];
  final List<XFile?> _stepImages = [];
  final _prepTimeController = TextEditingController();
  final _cookTimeController = TextEditingController();
  final _servingsController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _tagsController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedPostType = widget.postType;
    _loadChannelSettings();
    // Если режим редактирования, загружаем данные поста
    if (widget.postId != null && widget.postData != null) {
      _loadPostData(widget.postData!);
    } else {
      // Добавляем начальные поля для рецепта, если это рецепт
      if (_selectedPostType == 'recipe') {
        _addIngredientField();
        _addStepField();
      }
    }
  }

  Future<void> _loadChannelSettings() async {
    try {
      final channel = await ChannelService.getChannel(widget.channelId);
      if (!mounted) return;
      setState(() {
        _channelAutoPublishReels = channel.autoPublishReels;
        if (widget.postId == null) {
          _sendToReels = _channelAutoPublishReels;
        }
      });
    } catch (e) {
      debugPrint('Ошибка загрузки настроек канала: $e');
    }
  }

  void _loadPostData(Map<String, dynamic> postData) {
    // Загружаем данные поста в поля формы
    _titleController.text = postData['title'] ?? '';
    _descriptionController.text = postData['description'] ?? '';

    final body = postData['body'] as Map<String, dynamic>?;
    if (body != null) {
      // Загружаем ингредиенты
      final ingredients = body['ingredients'] as List<dynamic>?;
      if (ingredients != null) {
        _ingredientControllers.clear();
        for (var ing in ingredients) {
          _ingredientControllers
              .add(TextEditingController(text: ing.toString()));
        }
      }

      // Загружаем шаги
      final steps = body['steps'] as List<dynamic>?;
      if (steps != null) {
        _stepControllers.clear();
        _stepImages.clear();
        for (var step in steps) {
          if (step is Map<String, dynamic>) {
            _stepControllers.add(TextEditingController(
                text: step['text'] ?? step['step'] ?? ''));
            // Сохраняем URL изображения шага, если оно есть (для отображения при редактировании)
            final stepImageUrl = step['image'] ?? step['image_url'];
            // Примечание: XFile используется только для новых выбранных файлов
            // Для существующих изображений из URL мы просто сохраняем URL
            _stepImages.add(null); // URL будет сохранен в шаге
          } else {
            _stepControllers.add(TextEditingController(text: step.toString()));
            _stepImages.add(null);
          }
        }
      }

      // Загружаем время приготовления
      _prepTimeController.text = (body['prep_time_min'] ?? '').toString();
      _cookTimeController.text = (body['cook_time_min'] ?? '').toString();
      _servingsController.text = (body['servings'] ?? '').toString();
      _caloriesController.text = (body['calories'] ?? '').toString();

      // Загружаем теги
      final tags = postData['tags'] as List<dynamic>?;
      if (tags != null) {
        _tagsController.text = tags.join(', ');
      }

      // Загружаем медиа
      final media = body['media'] as List<dynamic>?;
      if (media != null) {
        _uploadedMediaUrls = media
            .map((m) => m['url']?.toString() ?? '')
            .where((url) => url.isNotEmpty)
            .toList();
      }
    }

    // Определяем тип поста
    final type = postData['type'] as String?;
    if (type != null) {
      _selectedPostType = type;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _servingsController.dispose();
    _caloriesController.dispose();
    _tagsController.dispose();
    for (var ctrl in _ingredientControllers) ctrl.dispose();
    for (var ctrl in _stepControllers) ctrl.dispose();
    _videoPreviewController?.dispose();
    super.dispose();
  }

  /// Helper метод для отображения изображения (поддержка веб и мобильных)
  Widget _buildImageWidget(XFile imageFile,
      {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (kIsWeb) {
      // На веб используем Image.network с path из XFile (data URL или blob URL)
      return Image.network(
        imageFile.path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: width,
            height: height,
            color: Colors.grey[300],
            child: const Icon(Icons.error, color: Colors.red),
          );
        },
      );
    } else {
      // На мобильных используем Image.file через helper
      final file = getFileFromPath(imageFile.path);
      if (file == null) {
        // Fallback на network если File недоступен
        return Image.network(
          imageFile.path,
          width: width,
          height: height,
          fit: fit,
        );
      }
      return Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: width,
            height: height,
            color: Colors.grey[300],
            child: const Icon(Icons.error, color: Colors.red),
          );
        },
      );
    }
  }

  void _addIngredientField() {
    setState(() {
      _ingredientControllers.add(TextEditingController());
    });
  }

  void _removeIngredientField(int index) {
    if (_ingredientControllers.length > 1) {
      setState(() {
        _ingredientControllers[index].dispose();
        _ingredientControllers.removeAt(index);
      });
    }
  }

  void _addStepField() {
    setState(() {
      _stepControllers.add(TextEditingController());
      _stepImages.add(null);
    });
  }

  void _removeStepField(int index) {
    if (_stepControllers.length > 1) {
      setState(() {
        _stepControllers[index].dispose();
        _stepControllers.removeAt(index);
        _stepImages.removeAt(index);
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      // Позволяем выбрать несколько изображений (как в Telegram)
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        setState(() {
          // Добавляем новые изображения к существующим (максимум 10)
          final remainingSlots = 10 - _selectedImages.length;
          if (remainingSlots > 0) {
            _selectedImages.addAll(images.take(remainingSlots));
          }
          _selectedVideo = null;
        });
      }
    } catch (e) {
      // Если pickMultiImage не поддерживается, используем pickImage
      try {
        final XFile? image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );

        if (image != null) {
          setState(() {
            if (_selectedImages.length < 10) {
              _selectedImages.add(image);
            }
            _selectedVideo = null;
          });
        }
      } catch (e2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка выбора изображения: $e2')),
          );
        }
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 2),
      );

      if (video != null) {
        await _setSelectedVideo(video);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора видео: $e')),
        );
      }
    }
  }

  Future<void> _pickThumbnail() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 720,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _thumbnailImage = image;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора обложки: $e')),
        );
      }
    }
  }

  Future<void> _setSelectedVideo(XFile video) async {
    _videoPreviewController?.pause();
    _videoPreviewController?.dispose();
    _videoPreviewController = null;
    _videoPreviewFuture = null;
    if (!mounted) return;
    setState(() {
      _selectedVideo = video;
      _thumbnailImage = null;
      _selectedImages.clear();
      _uploadedMediaUrls.clear();
      _uploadedVideoThumbnailUrl = null;
      _videoProcessing = false;
      _videoPreviewError = false;
      _isPreviewPlaying = false;
      _selectedVideoBytes = null;
      _sendToReels = _channelAutoPublishReels;
    });
    try {
      final length = await video.length();
      if (mounted) {
        setState(() => _selectedVideoBytes = length);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _selectedVideoBytes = null);
      }
    }
    await _initializeVideoPreview(video);
  }

  Future<void> _initializeVideoPreview(XFile video) async {
    if (!mounted || kIsWeb) return;
    try {
      final file = getFileFromPath(video.path);
      final controller = VideoPlayerController.file(file);
      setState(() {
        _videoPreviewController = controller;
        _videoPreviewFuture = controller.initialize();
        _videoPreviewError = false;
        _isPreviewPlaying = false;
      });
      await _videoPreviewFuture;
      if (!mounted) return;
      controller.setLooping(true);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _videoPreviewError = true);
    }
  }

  void _clearVideoSelection() {
    _videoPreviewController?.pause();
    _videoPreviewController?.dispose();
    _videoPreviewController = null;
    _videoPreviewFuture = null;
    if (!mounted) return;
    setState(() {
      _selectedVideo = null;
      _thumbnailImage = null;
      _uploadedMediaUrls.clear();
      _uploadedVideoThumbnailUrl = null;
      _videoProcessing = false;
      _videoPreviewError = false;
      _isPreviewPlaying = false;
      _selectedVideoBytes = null;
      _sendToReels = _channelAutoPublishReels;
    });
  }

  void _togglePreviewPlayback() {
    final controller = _videoPreviewController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
      setState(() => _isPreviewPlaying = false);
    } else {
      controller.play();
      setState(() => _isPreviewPlaying = true);
    }
  }

  Future<void> _pickStepImage(int index) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _stepImages[index] = image;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора изображения: $e')),
        );
      }
    }
  }

  Future<void> _uploadMedia() async {
    if (_isUploadingMedia) return;
    if (_selectedImages.isEmpty && _selectedVideo == null) return;

    setState(() {
      _isUploadingMedia = true;
      _uploadProgress = 0.0;
      _videoProcessing = false;
      _uploadedVideoThumbnailUrl = null;
    });

    try {
      List<String> urls = [];

      // Загружаем все выбранные изображения (как в Telegram)
      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        final response = await MediaUploadService.uploadMediaFile(
          file: image,
          fileType: 'image',
          onProgress: (progress) {
            // Обновляем прогресс с учетом количества изображений
            final totalProgress = (i / _selectedImages.length) +
                (progress / _selectedImages.length);
            setState(() =>
                _uploadProgress = totalProgress.clamp(0.0, 1.0).toDouble());
          },
        );
        final url = response.url;
        if (url != null && url.isNotEmpty) urls.add(url);
      }

      if (_selectedVideo != null) {
        final videoResponse = await MediaUploadService.uploadMediaFile(
          file: _selectedVideo!,
          fileType: 'video',
          onProgress: (progress) {
            setState(
                () => _uploadProgress = progress.clamp(0.0, 1.0).toDouble());
          },
        );
        final url = videoResponse.url;
        if (url != null && url.isNotEmpty) {
          urls.add(url);
        }
        setState(() {
          _videoProcessing = videoResponse.processing;
        });
        if (videoResponse.processing && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Видео отправлено на обработку, оно появится через пару минут')),
          );
        }

        // Загружаем обложку для видео, если есть
        if (_thumbnailImage != null) {
          final thumbnailResponse = await MediaUploadService.uploadMediaFile(
            file: _thumbnailImage!,
            fileType: 'image',
            onProgress: (progress) {
              setState(() => _uploadProgress =
                  (0.8 + (progress * 0.2)).clamp(0.0, 1.0).toDouble());
            },
          );
          final thumbnailUrl = thumbnailResponse.url;
          if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
            _uploadedVideoThumbnailUrl = thumbnailUrl;
          }
        }
      }

      setState(() {
        _uploadedMediaUrls = urls;
        _isUploadingMedia = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
          _videoProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки медиа: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Валидация только для рецепта
    // Для обычных постов медиа опционально

    if (_selectedPostType == 'recipe') {
      // Валидация рецепта
      final ingredients = _ingredientControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (ingredients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Добавьте хотя бы один ингредиент')),
        );
        return;
      }

      final steps = _stepControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (steps.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Добавьте хотя бы один шаг')),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);
    final bool isEditing = widget.postId != null;
    Map<String, dynamic>? createdPostJson;

    try {
      // Сохраняем информацию о видео ДО загрузки
      final wasVideoSelected = _selectedVideo != null;

      // Загружаем медиа, если оно выбрано
      if ((_selectedImages.isNotEmpty || _selectedVideo != null) &&
          _uploadedMediaUrls.isEmpty) {
        await _uploadMedia();
      }

      if (_selectedPostType == 'recipe') {
        // Создаем рецепт
        final ingredients = _ingredientControllers
            .map((c) => c.text.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        // Загружаем изображения для шагов, если есть
        final steps = <Map<String, dynamic>>[];
        Map<String, dynamic>? body;
        if (widget.postId != null && widget.postData != null) {
          body = widget.postData!['body'] as Map<String, dynamic>?;
        }
        final existingSteps = body?['steps'] as List<dynamic>?;

        for (int i = 0; i < _stepControllers.length; i++) {
          final controller = _stepControllers[i];
          final text = controller.text.trim();
          if (text.isEmpty) continue;

          final stepData = <String, dynamic>{
            'number': steps.length + 1,
            'text': text,
            'step': text, // Дублируем для совместимости
          };

          // Проверяем, есть ли новое изображение для шага
          if (i < _stepImages.length && _stepImages[i] != null) {
            // Загружаем новое изображение
            try {
              final imageResponse = await MediaUploadService.uploadMediaFile(
                file: _stepImages[i]!,
                fileType: 'image',
                onProgress: (progress) {
                  // Можно добавить индикатор прогресса
                },
              );
              final imageUrl = imageResponse.url;
              if (imageUrl != null && imageUrl.isNotEmpty) {
                stepData['image'] = imageUrl;
                stepData['image_url'] = imageUrl; // Дублируем для совместимости
                debugPrint(
                    '✅ Изображение для шага ${steps.length + 1} загружено: $imageUrl');
              }
            } catch (e) {
              // Если не удалось загрузить изображение, продолжаем без него
              debugPrint('Ошибка загрузки изображения для шага ${i + 1}: $e');
            }
          } else if (widget.postId != null &&
              existingSteps != null &&
              i < existingSteps.length) {
            // При редактировании сохраняем существующее изображение, если оно есть
            final existingStep = existingSteps[i];
            if (existingStep is Map<String, dynamic>) {
              final existingImage =
                  existingStep['image'] ?? existingStep['image_url'];
              if (existingImage != null &&
                  existingImage.toString().isNotEmpty) {
                stepData['image'] = existingImage;
                stepData['image_url'] = existingImage;
              }
            }
          }

          steps.add(stepData);
          debugPrint(
              '📝 Шаг ${stepData['number']}: текст="${stepData['text']}", изображение=${stepData['image'] ?? stepData['image_url'] ?? "нет"}');
        }

        debugPrint('📤 Отправляем ${steps.length} шагов на сервер');

        // Загружаем все фотографии рецепта (как в Telegram)
        List<Map<String, dynamic>>? media;
        if (_selectedImages.isNotEmpty) {
          media = [];
          for (final image in _selectedImages) {
            final imageResponse = await MediaUploadService.uploadMediaFile(
              file: image,
              fileType: 'image',
            );
            final imageUrl = imageResponse.url;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              media.add({'type': 'image', 'url': imageUrl});
            }
          }
        }

        final tags = _tagsController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        if (widget.postId != null) {
          // Режим редактирования
          await ChannelService.updateChannelPost(
            channelId: widget.channelId,
            postId: widget.postId!,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            ingredients: ingredients,
            steps: steps,
            media: media,
            prepTimeMin: _prepTimeController.text.isNotEmpty
                ? int.tryParse(_prepTimeController.text)
                : null,
            cookTimeMin: _cookTimeController.text.isNotEmpty
                ? int.tryParse(_cookTimeController.text)
                : null,
            servings: _servingsController.text.isNotEmpty
                ? int.tryParse(_servingsController.text)
                : null,
            calories: _caloriesController.text.isNotEmpty
                ? int.tryParse(_caloriesController.text)
                : null,
            tags: tags.isNotEmpty ? tags : null,
          );
        } else {
          // Режим создания
          createdPostJson = await ChannelService.createChannelRecipe(
            channelId: widget.channelId,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            ingredients: ingredients,
            steps: steps,
            media: media,
            prepTimeMin: _prepTimeController.text.isNotEmpty
                ? int.tryParse(_prepTimeController.text)
                : null,
            cookTimeMin: _cookTimeController.text.isNotEmpty
                ? int.tryParse(_cookTimeController.text)
                : null,
            servings: _servingsController.text.isNotEmpty
                ? int.tryParse(_servingsController.text)
                : null,
            calories: _caloriesController.text.isNotEmpty
                ? int.tryParse(_caloriesController.text)
                : null,
            tags: tags.isNotEmpty ? tags : null,
          );
        }
      } else {
        // Создаем обычный пост
        // Автоматически определяем тип поста на основе загруженного медиа
        String finalType = 'text';
        bool hasVideo = false;

        List<Map<String, dynamic>>? media;
        bool? publishToReels;
        if (_uploadedMediaUrls.isNotEmpty) {
          hasVideo = wasVideoSelected;

          if (hasVideo) {
            finalType = 'reel';
            publishToReels = _sendToReels;
            media = [
              {
                'type': 'video',
                'url': _uploadedMediaUrls.first,
                if (_uploadedVideoThumbnailUrl != null)
                  'thumbnail_url': _uploadedVideoThumbnailUrl,
              },
            ];
          } else {
            finalType = 'photo';
            media = _uploadedMediaUrls
                .map((url) => {
                      'type': 'image',
                      'url': url,
                    })
                .toList();
          }
        }

        final tags = _tagsController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        if (widget.postId != null) {
          // Режим редактирования
          await ChannelService.updateChannelPost(
            channelId: widget.channelId,
            postId: widget.postId!,
            title: _titleController.text.trim().isNotEmpty
                ? _titleController.text.trim()
                : null,
            description: _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : null,
            media: media,
            tags: tags.isNotEmpty ? tags : null,
          );
        } else {
          // Режим создания
          createdPostJson = await ChannelService.createChannelPost(
            channelId: widget.channelId,
            type: finalType,
            title: _titleController.text.trim().isNotEmpty
                ? _titleController.text.trim()
                : null,
            description: _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : null,
            media: media,
            tags: tags.isNotEmpty ? tags : null,
            publishToReels: publishToReels,
          );
        }
      }

      final PostModel? createdPost =
          (!isEditing) ? _tryParsePost(createdPostJson) : null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(widget.postId != null
                  ? 'Пост обновлен успешно'
                  : 'Пост успешно создан')),
        );
        context.pop(createdPost ?? true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка создания поста: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пост'),
        actions: [
          if (_isSubmitting)
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
              onPressed: _submit,
              child: const Text('Опубликовать'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Выбор типа поста
            _buildPostTypeSelector(),
            const SizedBox(height: 24),

            // Заголовок
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Заголовок',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Введите заголовок';
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

            // Контент в зависимости от типа
            if (_selectedPostType == 'recipe') _buildRecipeSection(),

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
          ],
        ),
      ),
    );
  }

  Widget _buildPostTypeSelector() {
    // Убрали выбор типа поста - теперь единый "Пост" с опциональным рецептом
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Тип контента',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PostTypeChip(
              label: 'Рецепт',
              icon: Icons.restaurant_menu,
              isSelected: _selectedPostType == 'recipe',
              onTap: () => setState(() {
                _selectedPostType =
                    _selectedPostType == 'recipe' ? 'text' : 'recipe';
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Кнопки для добавления медиа (для всех типов постов)
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library),
              label: const Text('Добавить фото'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.video_library),
              label: const Text('Добавить видео'),
            ),
          ],
        ),
        // Превью выбранных изображений (как в Telegram)
        if (_selectedImages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _buildSelectedImagesPreview(),
          ),
      ],
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Изображения (${_selectedImages.length}/10)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_selectedImages.isNotEmpty)
              TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.add_photo_alternate, size: 18),
                label: const Text('Добавить еще'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_selectedImages.isNotEmpty)
          _buildSelectedImagesPreview()
        else
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Выбрать изображения'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
      ],
    );
  }

  /// Виджет для отображения выбранных изображений (как в Telegram)
  Widget _buildSelectedImagesPreview() {
    if (_selectedImages.isEmpty) return const SizedBox.shrink();

    // Используем TelegramPhotoGrid для предпросмотра
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Превью в стиле Telegram
        TelegramPhotoGrid(
          imageUrls: _selectedImages.map((img) => img.path).toList(),
          maxHeight: 300,
        ),
        const SizedBox(height: 8),
        // Список изображений с возможностью удаления
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _selectedImages.asMap().entries.map((entry) {
            final index = entry.key;
            final image = entry.value;
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildImageWidget(
                    image,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      padding: const EdgeInsets.all(4),
                      minimumSize: const Size(24, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedImages.removeAt(index);
                      });
                    },
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        if (_isUploadingMedia && _selectedVideo == null) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
              value: _uploadProgress.clamp(0.0, 1.0).toDouble()),
          const SizedBox(height: 4),
          Text(
            'Загрузка: ${(100 * _uploadProgress).clamp(0, 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  double _currentVideoAspectRatio() {
    final controller = _videoPreviewController;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.aspectRatio > 0) {
      return controller.value.aspectRatio;
    }
    return 9 / 16;
  }

  Widget _buildVideoPreview() {
    if (kIsWeb ||
        _videoPreviewController == null ||
        _videoPreviewFuture == null) {
      return _buildVideoPlaceholder(
        message: kIsWeb ? 'Предпросмотр недоступен в веб-версии' : null,
      );
    }
    return FutureBuilder<void>(
      future: _videoPreviewFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_videoPreviewError || snapshot.hasError) {
          return _buildVideoPlaceholder(
              message: 'Не удалось отобразить превью');
        }
        final controller = _videoPreviewController!;
        return Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black26],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: IconButton(
                  iconSize: 64,
                  color: Colors.white70,
                  icon: Icon(_isPreviewPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled),
                  onPressed: _togglePreviewPlayback,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVideoPlaceholder({String? message}) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_outline,
                size: 64, color: Colors.white70),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _videoDurationLabel() {
    final controller = _videoPreviewController;
    if (controller == null || !controller.value.isInitialized) return null;
    final duration = controller.value.duration;
    if (duration == Duration.zero) return null;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatFileSize(int bytes) {
    const units = ['Б', 'КБ', 'МБ', 'ГБ'];
    double size = bytes.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unitIndex]}';
  }

  PostModel? _tryParsePost(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      return PostModel.fromJson(json);
    } catch (e) {
      debugPrint('Failed to parse PostModel: $e');
      return null;
    }
  }

  Widget _buildVideoSection() {
    final durationLabel = _videoDurationLabel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Видео',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (_selectedVideo != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: _currentVideoAspectRatio(),
                  child: _buildVideoPreview(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        _selectedVideo!.name,
                        if (_selectedVideoBytes != null)
                          _formatFileSize(_selectedVideoBytes!),
                        if (durationLabel != null) durationLabel,
                      ].whereType<String>().join(' • '),
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: (_isUploadingMedia || _isSubmitting)
                        ? null
                        : _clearVideoSelection,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Удалить'),
                  ),
                ],
              ),
              if (_isUploadingMedia) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                    value: _uploadProgress.clamp(0.0, 1.0).toDouble()),
                const SizedBox(height: 4),
                Text(
                  'Загрузка: ${(100 * _uploadProgress).clamp(0, 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (_videoProcessing) ...[
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Icon(Icons.timelapse, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                        child: Text(
                            'Видео обрабатывается на сервере, оно появится через пару минут')),
                  ],
                ),
              ],
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: (_isUploadingMedia || _isSubmitting) ? null : _pickVideo,
            icon: const Icon(Icons.video_library),
            label: const Text('Выбрать видео'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        if (_selectedVideo != null && _selectedPostType == 'reel')
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Публиковать в Reels'),
            subtitle: Text(_channelAutoPublishReels
                ? 'Включено по умолчанию — можно отключить для этого поста'
                : 'По умолчанию выключено. Включите, чтобы отправить видео в Reels'),
            value: _sendToReels,
            onChanged: (_isUploadingMedia || _isSubmitting)
                ? null
                : (value) => setState(() => _sendToReels = value),
          ),
        const SizedBox(height: 16),
        Text(
          'Обложка видео',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (_thumbnailImage != null)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildImageWidget(
                  _thumbnailImage!,
                  width: double.infinity,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: (_isUploadingMedia || _isSubmitting)
                      ? null
                      : () => setState(() => _thumbnailImage = null),
                ),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed:
                (_isUploadingMedia || _isSubmitting) ? null : _pickThumbnail,
            icon: const Icon(Icons.image),
            label: const Text('Выбрать обложку'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
      ],
    );
  }

  Widget _buildRecipeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Фотографии рецепта (как в Telegram)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Фотографии рецепта (${_selectedImages.length}/10)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_selectedImages.isNotEmpty)
              TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.add_photo_alternate, size: 18),
                label: const Text('Добавить еще'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_selectedImages.isNotEmpty)
          _buildSelectedImagesPreview()
        else
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Выбрать фото'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        const SizedBox(height: 24),

        // Ингредиенты
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Ингредиенты',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addIngredientField,
            ),
          ],
        ),
        ..._ingredientControllers.asMap().entries.map((entry) {
          final index = entry.key;
          final controller = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'Ингредиент ${index + 1}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_ingredientControllers.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle),
                    onPressed: () => _removeIngredientField(index),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),

        // Шаги приготовления
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Шаги приготовления',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addStepField,
            ),
          ],
        ),
        ..._stepControllers.asMap().entries.map((entry) {
          final index = entry.key;
          final controller = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Шаг ${index + 1}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    if (_stepControllers.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle),
                        onPressed: () => _removeStepField(index),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'Описание шага',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                if (_stepImages[index] != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildImageWidget(
                          _stepImages[index]!,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          icon: const Icon(Icons.close,
                              size: 20, color: Colors.white),
                          onPressed: () =>
                              setState(() => _stepImages[index] = null),
                        ),
                      ),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _pickStepImage(index),
                    icon: const Icon(Icons.add_photo_alternate, size: 18),
                    label: const Text('Добавить фото'),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),

        // Дополнительная информация
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _prepTimeController,
                decoration: const InputDecoration(
                  labelText: 'Время подготовки (мин)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _cookTimeController,
                decoration: const InputDecoration(
                  labelText: 'Время готовки (мин)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _servingsController,
                decoration: const InputDecoration(
                  labelText: 'Порций',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _caloriesController,
                decoration: const InputDecoration(
                  labelText: 'Калорий',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PostTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PostTypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => onTap(),
    );
  }
}
