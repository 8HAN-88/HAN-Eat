// Экран создания поста
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/app/app_variant.dart';
import '../../../../core/recipe/recipe_nutrition_input.dart';
import '../../../../widgets/app_gradient_background.dart';
import '../../../../features/settings/application/subscription_status_provider.dart';
import '../../../../services/post_service.dart';
import '../../../../utils/api_error_parser.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/channel_service.dart';
import '../../../../services/feed_api_cache.dart';
import '../../../../services/media_upload_service.dart';
import '../../../../utils/file_helper.dart';
import '../../../../widgets/app_avatar.dart';
import '../../../../widgets/recipe_nutrition_form_section.dart';
import '../../../../widgets/recipe_visibility_selector.dart';
import '../../../../widgets/recipe_origin_country_field.dart';
import '../../../../widgets/telegram_photo_grid.dart';
import '../../../../widgets/create_poll_form_section.dart';
import '../../../../utils/url_validator.dart';
import '../../reels/application/reels_feed_refresh_provider.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({
    super.key,
    this.initialType = 'text',
    this.recipeOnly = false,
  });

  static const routeName = '/create-post';

  final String initialType;
  final bool recipeOnly;

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late String _selectedType;
  bool _isLoading = false;
  String? _loadingStatus;
  int? _selectedChannelId;
  final List<Channel> _userChannels = [];
  String _recipeVisibility = 'public';
  String? _channelVisibilityMode;
  String? _originCountryCode;
  bool _isPaidContent = false;

  // Медиа файлы
  final ImagePicker _imagePicker = ImagePicker();
  final List<XFile> _selectedImages =
      []; // Список выбранных изображений (как в Telegram)
  XFile? _selectedVideo;
  double _uploadProgress = 0.0;
  bool _isUploading = false;
  List<String> _uploadedMediaUrls = [];

  // Для рецепта
  final List<TextEditingController> _ingredientControllers = [];
  final List<TextEditingController> _stepControllers = [];
  final List<XFile?> _stepImages = [];
  final _prepTimeController = TextEditingController();
  final _cookTimeController = TextEditingController();
  final _servingsController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  final _fiberController = TextEditingController();
  final _tagsController = TextEditingController();
  final _linkUrlController = TextEditingController();
  final _linkPreviewController = TextEditingController();
  final _priceStarsController = TextEditingController(text: '50');
  final _pollQuestionController = TextEditingController();
  final List<TextEditingController> _pollOptionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  bool get _isPollMode => _selectedType == 'poll';
  bool get _isLinkMode => _selectedType == 'link';
  bool get _recipeComposerEnabled =>
      widget.recipeOnly || AppVariant.current.isKitchen;
  int get _paidPriceStars => _isPaidContent
      ? (int.tryParse(_priceStarsController.text.trim()) ?? 0)
      : 0;
  Timer? _linkPreviewDebounce;
  bool _isLoadingLinkPreview = false;
  Map<String, dynamic>? _linkPreviewMeta;
  bool _linkPreviewFailed = false;

  @override
  void initState() {
    super.initState();
    final wantsRecipe = widget.recipeOnly || widget.initialType == 'recipe';
    // В social recipe запрещён
    _selectedType =
        wantsRecipe && AppVariant.current.isKitchen ? 'recipe' : 'text';
    _linkUrlController.addListener(_scheduleLinkPreviewLoad);
    _linkPreviewController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    // Добавляем начальные поля для рецепта, если это рецепт
    if (_selectedType == 'recipe') {
      _addIngredientField();
      _addStepField();
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
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _fiberController.dispose();
    _tagsController.dispose();
    _linkPreviewDebounce?.cancel();
    _linkUrlController.removeListener(_scheduleLinkPreviewLoad);
    _linkUrlController.dispose();
    _linkPreviewController.dispose();
    _priceStarsController.dispose();
    _pollQuestionController.dispose();
    for (var ctrl in _pollOptionControllers) {
      ctrl.dispose();
    }
    for (var ctrl in _ingredientControllers) {
      ctrl.dispose();
    }
    for (var ctrl in _stepControllers) {
      ctrl.dispose();
    }
    super.dispose();
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
          SnackBar(
              content: Text(userVisibleError(e,
                  fallback: 'Не удалось выбрать изображение'))),
        );
      }
    }
  }

  /// Helper метод для отображения изображения (поддержка веб и мобильных)
  Widget _buildImageWidget(XFile imageFile,
      {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (kIsWeb) {
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
      final file = getFileFromPath(imageFile.path);
      if (file == null) {
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

  Future<void> _pickImage() async {
    try {
      // Позволяем выбрать несколько изображений (как в Telegram)
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        setState(() {
          _preparePlainComposerForMediaSelection();
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
            _preparePlainComposerForMediaSelection();
            if (_selectedImages.length < 10) {
              _selectedImages.add(image);
            }
            _selectedVideo = null;
          });
        }
      } catch (e2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(userVisibleError(e,
                    fallback: 'Не удалось выбрать изображение'))),
          );
        }
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 2), // Максимум 2 минуты для рилсов
      );

      if (video != null) {
        setState(() {
          _preparePlainComposerForMediaSelection();
          _selectedVideo = video; // Используем XFile напрямую
          _selectedImages.clear(); // Сбрасываем изображения, если выбрано видео
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  userVisibleError(e, fallback: 'Не удалось выбрать видео'))),
        );
      }
    }
  }

  void _disposeRecipeDraftFields() {
    for (final ctrl in _ingredientControllers) {
      ctrl.dispose();
    }
    for (final ctrl in _stepControllers) {
      ctrl.dispose();
    }
    _ingredientControllers.clear();
    _stepControllers.clear();
    _stepImages.clear();
  }

  void _clearLinkDraft() {
    _linkPreviewDebounce?.cancel();
    _linkPreviewMeta = null;
    _isLoadingLinkPreview = false;
    _linkPreviewFailed = false;
  }

  void _preparePlainComposerForMediaSelection() {
    if (_selectedType == 'recipe') {
      _disposeRecipeDraftFields();
    }
    _clearLinkDraft();
    _selectedType = 'text';
  }

  Future<String?> _uploadImageFile(XFile file) async {
    final response = await MediaUploadService.uploadMediaFile(
      file: file,
      fileType: 'image',
    );
    final url = response.url;
    if (url == null || url.isEmpty) return null;
    return url;
  }

  Future<List<String>> _uploadImagesParallel(List<XFile> files) async {
    if (files.isEmpty) return [];
    var completed = 0;
    final urls = await Future.wait(
      files.map((file) async {
        final url = await _uploadImageFile(file);
        completed++;
        if (mounted) {
          setState(() {
            _loadingStatus = 'Загрузка фото $completed/${files.length}…';
          });
        }
        return url;
      }),
    );
    return urls.whereType<String>().toList();
  }

  Future<void> _loadChannelVisibilityMode(int? channelId) async {
    if (channelId == null) {
      setState(() {
        _channelVisibilityMode = null;
        _recipeVisibility = 'public';
      });
      return;
    }
    try {
      final channel = await ChannelService.getChannel(channelId);
      if (!mounted) return;
      final hasCreator =
          ref.read(subscriptionStatusProvider).asData?.value?.hasCreator ??
              false;
      setState(() {
        _channelVisibilityMode = channel.recipeVisibilityMode;
        _recipeVisibility = RecipeVisibilitySelector.defaultForChannel(
          _channelVisibilityMode,
          hasCreator: hasCreator,
        );
      });
    } catch (_) {}
  }

  Future<void> _uploadMedia() async {
    if (_selectedImages.isEmpty && _selectedVideo == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
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
            setState(() => _uploadProgress = (i / _selectedImages.length) +
                (progress / _selectedImages.length));
          },
        );
        final url = response.url;
        if (url != null && url.isNotEmpty) urls.add(url);
      }

      if (_selectedVideo != null) {
        final response = await MediaUploadService.uploadMediaFile(
          file: _selectedVideo!,
          fileType: 'video',
          onProgress: (progress) {
            setState(() => _uploadProgress = progress);
          },
        );
        final url = response.url;
        if (url != null && url.isNotEmpty) urls.add(url);
      }

      setState(() {
        _uploadedMediaUrls = urls;
        _isUploading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  userVisibleError(e, fallback: 'Не удалось загрузить медиа'))),
        );
      }
    }
  }

  void _scheduleLinkPreviewLoad() {
    if (!_isLinkMode) return;
    _linkPreviewDebounce?.cancel();
    _linkPreviewDebounce = Timer(const Duration(milliseconds: 550), () {
      _loadLinkPreview();
    });
  }

  Future<void> _loadLinkPreview() async {
    final normalized = normalizeHttpUrl(_linkUrlController.text);
    if (normalized == null) {
      if (mounted) {
        setState(() {
          _linkPreviewMeta = null;
          _isLoadingLinkPreview = false;
          _linkPreviewFailed = false;
        });
      }
      return;
    }
    setState(() => _isLoadingLinkPreview = true);
    try {
      final meta = await PostService.fetchLinkPreview(normalized);
      if (!mounted) return;
      setState(() {
        _linkPreviewMeta = meta;
        _linkPreviewFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _linkPreviewMeta = null;
        _linkPreviewFailed = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingLinkPreview = false);
      }
    }
  }

  Widget _buildLinkLivePreviewCard() {
    final meta = _linkPreviewMeta;
    final title = _linkPreviewController.text.trim().isNotEmpty
        ? _linkPreviewController.text.trim()
        : (meta?['title']?.toString());
    final description = meta?['description']?.toString();
    final image = meta?['image']?.toString();
    final domain = meta?['domain']?.toString();
    final url = _linkUrlController.text.trim();

    if (_isLoadingLinkPreview) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (title == null &&
        (description == null || description.isEmpty) &&
        (image == null || image.isEmpty) &&
        url.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image != null && image.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  image,
                  height: 130,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            if (image != null && image.isNotEmpty) const SizedBox(height: 8),
            Text(
              title ?? url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (description != null && description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (domain != null && domain.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  domain,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            if (_linkPreviewFailed && url.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Не удалось получить превью, ссылка всё равно будет сохранена.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePublish() async {
    if (!_formKey.currentState!.validate()) return;

    // Валидация только для рецепта
    if (_selectedType == 'recipe') {
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
    } else if (!_isPollMode && !_isLinkMode) {
      final hasText = _descriptionController.text.trim().isNotEmpty ||
          _titleController.text.trim().isNotEmpty;
      final hasMedia = _selectedImages.isNotEmpty || _selectedVideo != null;
      if (!hasText && !hasMedia) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Напишите текст или добавьте медиа')),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _loadingStatus = 'Публикация…';
    });

    try {
      // Сохраняем информацию о видео ДО загрузки
      final wasVideoSelected = _selectedVideo != null;

      if (_isPollMode) {
        final question = _pollQuestionController.text.trim();
        if (question.isEmpty) {
          throw Exception('Введите вопрос опроса');
        }
        final options =
            CreatePollFormSection.collectOptions(_pollOptionControllers);
        if (options == null) {
          throw Exception('Добавьте минимум 2 варианта ответа');
        }
        await PostService.createPoll(
          question: question,
          options: options,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          channelId: _selectedChannelId,
        );
      } else if (_isLinkMode) {
        final linkUrl = normalizeHttpUrl(_linkUrlController.text);
        if (linkUrl == null) {
          throw Exception('Введите корректную ссылку (http:// или https://)');
        }
        final linkPreview = _linkPreviewController.text.trim().isEmpty
            ? (_linkPreviewMeta?['title'])?.toString()
            : _linkPreviewController.text.trim();
        await PostService.createPost(
          type: 'link',
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          channelId: _selectedChannelId,
          linkUrl: linkUrl,
          linkPreview: linkPreview,
          isPaid: _isPaidContent,
          priceStars: _paidPriceStars,
        );
      } else if (_selectedType == 'recipe') {
        final ingredients = _ingredientControllers
            .map((c) => c.text.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        final stepImageUrls =
            List<String?>.filled(_stepControllers.length, null);
        final stepUploads = <Future<void>>[];
        for (var i = 0; i < _stepImages.length; i++) {
          final file = _stepImages[i];
          if (file == null) continue;
          final index = i;
          stepUploads.add(() async {
            try {
              stepImageUrls[index] = await _uploadImageFile(file);
            } catch (e) {
              debugPrint('Ошибка загрузки фото шага ${index + 1}: $e');
            }
          }());
        }

        final mainUpload = _selectedImages.isEmpty
            ? Future<List<String>>.value([])
            : _uploadImagesParallel(_selectedImages);

        await Future.wait([mainUpload, ...stepUploads]);
        final mainUrls = await mainUpload;

        final steps = <Map<String, dynamic>>[];
        for (var i = 0; i < _stepControllers.length; i++) {
          final text = _stepControllers[i].text.trim();
          if (text.isEmpty) continue;
          final stepData = <String, dynamic>{
            'number': steps.length + 1,
            'text': text,
            'step': text,
          };
          final imageUrl = i < stepImageUrls.length ? stepImageUrls[i] : null;
          if (imageUrl != null && imageUrl.isNotEmpty) {
            stepData['image'] = imageUrl;
            stepData['image_url'] = imageUrl;
          }
          steps.add(stepData);
        }

        List<Map<String, dynamic>>? media;
        if (mainUrls.isNotEmpty) {
          media = mainUrls.map((url) => {'type': 'image', 'url': url}).toList();
        }

        final tags = _tagsController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        if (mounted) {
          setState(() => _loadingStatus = 'Сохранение рецепта…');
        }

        await PostService.createRecipe(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          ingredients: ingredients,
          steps: steps,
          media: media,
          prepTimeMin: parseIntField(_prepTimeController.text),
          cookTimeMin: parseIntField(_cookTimeController.text),
          servings: parseIntField(_servingsController.text),
          calories: parseIntField(_caloriesController.text),
          proteinG: parseDoubleField(_proteinController.text),
          carbsG: parseDoubleField(_carbsController.text),
          fatG: parseDoubleField(_fatController.text),
          fiberG: parseDoubleField(_fiberController.text),
          tags: tags.isNotEmpty ? tags : null,
          visibility: _recipeVisibility,
          channelId: _selectedChannelId,
          originCountryCode: _originCountryCode,
          isPaid: _isPaidContent,
          priceStars: _paidPriceStars,
        );
      } else {
        if ((_selectedImages.isNotEmpty || _selectedVideo != null) &&
            _uploadedMediaUrls.isEmpty) {
          await _uploadMedia();
        }
        // Создаем обычный пост
        // Автоматически определяем тип поста на основе загруженного медиа
        String finalType = 'text';
        bool hasVideo = false;

        List<Map<String, dynamic>>? media;
        if (_uploadedMediaUrls.isNotEmpty) {
          // Проверяем, есть ли видео в загруженных медиа
          // Используем сохраненную информацию о видео (из области видимости выше)
          hasVideo = wasVideoSelected;

          if (hasVideo) {
            finalType = 'reel';
          } else {
            finalType = 'photo';
          }

          media = _uploadedMediaUrls
              .map((url) => {
                    'type': hasVideo ? 'video' : 'image',
                    'url': url,
                  })
              .toList();
        }

        final tags = _tagsController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        // Преобразуем media в нужный формат
        List<Map<String, String>>? mediaForPost;
        if (media != null && media.isNotEmpty) {
          mediaForPost = media
              .map((item) => {
                    'type': item['type'] as String,
                    'url': item['url'] as String,
                  })
              .toList();
        }

        await PostService.createPost(
          type: finalType,
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          channelId: _selectedChannelId,
          media: mediaForPost,
          tags: tags.isNotEmpty ? tags : null,
          isPaid: _isPaidContent,
          priceStars: _paidPriceStars,
        );
        if (wasVideoSelected) {
          await FeedApiCache.clear('rec_reels');
          notifyReelsFeedRefresh(ref);
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true); // Возвращаемся с успехом
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.recipeOnly
                ? 'Рецепт опубликован'
                : wasVideoSelected
                    ? 'Рилс опубликован'
                    : 'Пост опубликован'),
          ),
        );
      }
    } on ApiClientException catch (e) {
      if (mounted) {
        final text = e.isContentBlocked
            ? 'Контент не прошёл модерацию и не будет опубликован.'
            : e.isRateLimited
                ? e.message
                : 'Ошибка публикации: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  userVisibleError(e, fallback: 'Не удалось опубликовать'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingStatus = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          titleSpacing: 8,
          title: TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          actions: [
            if (_isLoading && _loadingStatus != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _loadingStatus!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _isLoading ? null : _handlePublish,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: const StadiumBorder(),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.recipeOnly
                        ? 'Опубликовать рецепт'
                        : _selectedVideo != null
                            ? 'В рилсы'
                            : 'Опубликовать'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedType == 'recipe') ...[
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Название рецепта',
                        hintText: 'Например: Паста с креветками',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      validator: (value) {
                        if (_selectedType != 'recipe') return null;
                        if (value == null || value.trim().isEmpty) {
                          return 'Введите название рецепта';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_isPollMode) ...[
                    CreatePollFormSection(
                      questionController: _pollQuestionController,
                      optionControllers: _pollOptionControllers,
                      onAddOption: () {
                        setState(() {
                          _pollOptionControllers.add(TextEditingController());
                        });
                      },
                      onRemoveOption: (index) {
                        setState(() {
                          _pollOptionControllers[index].dispose();
                          _pollOptionControllers.removeAt(index);
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_isLinkMode) ...[
                    TextFormField(
                      controller: _linkUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Ссылка',
                        hintText: 'https://example.com',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      validator: (value) {
                        if (!_isLinkMode) return null;
                        return validateHttpUrl(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _linkPreviewController,
                      decoration: const InputDecoration(
                        labelText: 'Подпись к ссылке (необязательно)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    _buildLinkLivePreviewCard(),
                    const SizedBox(height: 16),
                  ],
                  _buildComposerTextField(),
                  const SizedBox(height: 16),

                  // Контент в зависимости от типа
                  if (_selectedType == 'recipe') _buildRecipeSection(),

                  // Кнопки для добавления медиа (не для рецепта и опроса)
                  if (_selectedType != 'recipe' &&
                      !_isPollMode &&
                      !_isLinkMode) ...[
                    // Превью выбранных изображений (как в Telegram)
                    if (_selectedImages.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _buildSelectedImagesPreview(),
                      ),
                    // Превью выбранного видео
                    if (_selectedVideo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.play_circle_filled,
                                  color: Colors.white,
                                  size: 64,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 10,
                              bottom: 10,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    'Будет опубликовано в рилсы',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _selectedVideo = null;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  _buildComposerToolbar(),

                  // Теги
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Теги (через запятую)',
                      hintText: 'выпечка, здоровое, завтрак',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _isPaidContent,
                            onChanged: (value) =>
                                setState(() => _isPaidContent = value),
                            title: const Text('Платный контент'),
                            subtitle: const Text(
                              'Показывать превью и открывать полный пост за звёзды',
                            ),
                            secondary: const Icon(Icons.lock_rounded),
                          ),
                          if (_isPaidContent) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _priceStarsController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Цена в звёздах',
                                prefixIcon: Icon(Icons.stars_rounded),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (!_isPaidContent) return null;
                                final price =
                                    int.tryParse((value ?? '').trim());
                                if (price == null || price <= 0) {
                                  return 'Укажите цену больше 0';
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Выбор канала (если есть доступные)
                  if (_userChannels.isNotEmpty) ...[
                    DropdownButtonFormField<int>(
                      initialValue: _selectedChannelId,
                      decoration: const InputDecoration(
                        labelText: 'Опубликовать от канала (опционально)',
                        prefixIcon: Icon(Icons.cable_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('От своего имени'),
                        ),
                        ..._userChannels.map((channel) {
                          return DropdownMenuItem<int>(
                            value: channel.id,
                            child: Text(channel.name),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedChannelId = value);
                        _loadChannelVisibilityMode(value);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedType == 'recipe') ...[
                    Builder(
                      builder: (context) {
                        final hasCreator = ref
                                .watch(subscriptionStatusProvider)
                                .asData
                                ?.value
                                ?.hasCreator ??
                            false;
                        return RecipeVisibilitySelector(
                          value: _recipeVisibility,
                          hasCreator: hasCreator,
                          channelMode: _channelVisibilityMode,
                          onChanged: (v) =>
                              setState(() => _recipeVisibility = v),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    RecipeOriginCountryField(
                      selectedCode: _originCountryCode,
                      onChanged: (code) =>
                          setState(() => _originCountryCode = code),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposerTextField() {
    final scheme = Theme.of(context).colorScheme;
    final isStructured =
        _selectedType == 'recipe' || _isPollMode || _isLinkMode;

    return FutureBuilder(
      future: AuthService.getCurrentUser(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final initial = (user?.name.isNotEmpty ?? false)
            ? user!.name[0].toUpperCase()
            : '?';

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundImage: resolvedAvatarImage(
                user?.avatarUrl,
                decodeWidth: 88,
              ),
              child: resolvedAvatarImage(user?.avatarUrl) == null
                  ? Text(initial)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _descriptionController,
                    autofocus: !isStructured,
                    decoration: InputDecoration(
                      hintText: isStructured
                          ? (_isPollMode
                              ? 'Комментарий к опросу'
                              : 'Добавьте описание')
                          : 'Что нового?',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      alignLabelWithHint: true,
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                    minLines: isStructured ? 3 : 8,
                    maxLines: null,
                    validator: (value) {
                      if (_selectedType == 'recipe' &&
                          (value == null || value.trim().isEmpty)) {
                        return 'Введите описание рецепта';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.public_rounded,
                        size: 17,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Отвечать могут все пользователи',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildComposerToolbar() {
    if (widget.recipeOnly || AppVariant.current.isKitchen) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            _ComposerToolButton(
              icon: Icons.image_outlined,
              tooltip: 'Фото',
              onTap: _isLoading ? null : _pickImage,
            ),
            _ComposerToolButton(
              icon: Icons.photo_camera_outlined,
              tooltip: 'Камера',
              onTap: _isLoading ? null : _pickImage,
            ),
            _ComposerToolButton(
              icon: Icons.video_library_outlined,
              tooltip: 'Видео в рилсы',
              onTap: _isLoading ? null : _pickVideo,
            ),
            _ComposerToolButton(
              icon: Icons.gif_box_outlined,
              tooltip: 'GIF',
              onTap: null,
            ),
            _ComposerToolButton(
              icon: Icons.format_quote_rounded,
              tooltip: 'Цитата',
              onTap: null,
            ),
            _ComposerToolButton(
              icon: Icons.poll_outlined,
              tooltip: 'Опрос',
              selected: _isPollMode,
              onTap: _isLoading
                  ? null
                  : () => _setContentType(_isPollMode ? 'text' : 'poll'),
            ),
            _ComposerToolButton(
              icon: Icons.link_rounded,
              tooltip: 'Ссылка',
              selected: _isLinkMode,
              onTap: _isLoading
                  ? null
                  : () => _setContentType(_isLinkMode ? 'text' : 'link'),
            ),
            if (_recipeComposerEnabled && !widget.recipeOnly)
              _ComposerToolButton(
                icon: Icons.restaurant_menu_rounded,
                tooltip: 'Рецепт',
                selected: _selectedType == 'recipe',
                onTap: _isLoading
                    ? null
                    : () => _setContentType(
                          _selectedType == 'recipe' ? 'text' : 'recipe',
                        ),
              ),
          ],
        ),
      ),
    );
  }

  void _setContentType(String type) {
    if (type == 'recipe' && !_recipeComposerEnabled) return;
    if (widget.recipeOnly && type != 'recipe') return;
    setState(() {
      if (_selectedType == 'recipe' && type != 'recipe') {
        _disposeRecipeDraftFields();
      }
      if (type != 'link') {
        _clearLinkDraft();
      }
      if (type == 'poll' || type == 'link') {
        _selectedImages.clear();
        _selectedVideo = null;
      }
      _selectedType = type;
      if (type == 'recipe') {
        _selectedVideo = null;
        if (_ingredientControllers.isEmpty) {
          _ingredientControllers.add(TextEditingController());
        }
        if (_stepControllers.isEmpty) {
          _stepControllers.add(TextEditingController());
          _stepImages.add(null);
        }
      }
    });
  }

  /// Виджет для отображения выбранных изображений (как в Telegram)
  Widget _buildSelectedImagesPreview() {
    if (_selectedImages.isEmpty) return const SizedBox.shrink();

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
        TextFormField(
          controller: _servingsController,
          decoration: const InputDecoration(
            labelText: 'Порций',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        RecipeNutritionFormSection(
          caloriesController: _caloriesController,
          proteinController: _proteinController,
          carbsController: _carbsController,
          fatController: _fatController,
          fiberController: _fiberController,
          getTitle: () => _titleController.text,
          getIngredients: () => _ingredientControllers
              .map((c) => c.text.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
          getStepTexts: () => _stepControllers
              .map((c) => c.text.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
          getServings: () => parseIntField(_servingsController.text),
          getDescription: () => _descriptionController.text,
        ),
      ],
    );
  }
}

class _ComposerToolButton extends StatelessWidget {
  const _ComposerToolButton({
    required this.icon,
    required this.tooltip,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected
        ? scheme.onPrimaryContainer
        : onTap == null
            ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
            : scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon),
          color: color,
          style: IconButton.styleFrom(
            backgroundColor:
                selected ? scheme.primaryContainer : Colors.transparent,
            minimumSize: const Size(38, 38),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}
