import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

// Условный импорт: на веб используем заглушку, на других платформах - dart:io
import 'dart:io' if (dart.library.html) 'dart:html' as io;

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../app/app_router.dart';
import '../../../services/auth_service.dart';
import '../application/community_controller.dart';
import '../application/community_upload_controller.dart';

class CommunityUploadScreen extends ConsumerStatefulWidget {
  const CommunityUploadScreen({super.key});

  @override
  ConsumerState<CommunityUploadScreen> createState() =>
      _CommunityUploadScreenState();
}

class _CommunityUploadScreenState
    extends ConsumerState<CommunityUploadScreen> {
  final _titleCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController(text: 'боул,здоровье');
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  
  // Категории для видео Reels
  static const List<String> _videoCategories = [
    'ЗОЖ',
    'Рецепты',
    'Красота',
    'Юмор',
    'Образование',
    'Путешествия',
    'Спорт',
    'Музыка',
    'Другое',
  ];
  String? _selectedCategory;

  XFile? _thumbnailFile;
  Uint8List? _videoBytes;
  Uint8List? _thumbnailBytes;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  bool get _canSubmit =>
      _videoBytes != null &&
      _titleCtrl.text.trim().isNotEmpty &&
      _authorCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.currentUser;
    if (user != null) {
      final name = user.name.trim();
      _authorCtrl.text = name.isNotEmpty
          ? name
          : (user.username?.trim().isNotEmpty == true
              ? user.username!.trim()
              : user.email);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AuthService.instance.currentUser == null) {
        context.go(LoginRoute.path);
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _descriptionCtrl.dispose();
    _tagsCtrl.dispose();
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo({ImageSource? source}) async {
    final picked = await _picker.pickVideo(
      source: source ?? ImageSource.gallery,
      maxDuration: const Duration(minutes: 3), // До 3 минут как в TikTok
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _videoBytes = bytes;
    });
    // Для веб-платформы превью может не работать, но это нормально
    if (!kIsWeb) {
      try {
        if (picked.path.isNotEmpty) {
          await _initPreview(picked.path);
        }
      } catch (e) {
        debugPrint('Ошибка загрузки превью: $e');
        // Не показываем ошибку пользователю, просто не загружаем превью
        // Видео все равно можно загрузить
      }
    }
    // На веб-платформе превью видео может не работать из-за ограничений браузера
    // Но видео все равно можно загрузить
  }

  Future<void> _recordVideo() async {
    await _pickVideo(source: ImageSource.camera);
  }

  Future<void> _initPreview(String filePath) async {
    if (kIsWeb) return; // На веб не поддерживается
    
    try {
      _videoController?.dispose();
      _chewieController?.dispose();
      // На не-веб платформах File доступен из dart:io
      // На веб этот код не выполнится из-за проверки kIsWeb выше
      // ignore: avoid_dynamic_calls
      _videoController = VideoPlayerController.file((io.File as dynamic)(filePath));
      await _videoController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: false,
        looping: true,
        allowFullScreen: true,
        showControls: false, // Скрываем стандартные контролы для тапа на видео
        allowMuting: false, // Отключаем звук
        allowPlaybackSpeedChanging: false,
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      debugPrint('Ошибка инициализации превью видео: $e');
      // Не показываем ошибку пользователю, просто не загружаем превью
      // Пользователь все равно сможет загрузить видео
    }
  }

  Future<void> _pickThumbnail() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _thumbnailFile = picked;
      _thumbnailBytes = bytes;
    });
  }

  List<String> _parseTags() {
    return _tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((element) => element.isNotEmpty)
        .toList();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || !_canSubmit) return;
    final uploadController =
        ref.read(communityUploadControllerProvider.notifier);
      // Добавить категорию в теги, если выбрана
      final tags = _parseTags();
      if (_selectedCategory != null && !tags.contains(_selectedCategory)) {
        tags.add(_selectedCategory!);
      }
      
      final success = await uploadController.submit(
      title: _titleCtrl.text.trim(),
      author: _authorCtrl.text.trim(),
      description: _descriptionCtrl.text.trim(),
      tags: tags,
      videoBytes: _videoBytes!,
      thumbnailBytes: _thumbnailBytes,
    );
    final state = ref.read(communityUploadControllerProvider);
    if (!mounted) return;
    if (success) {
      ref.read(communityControllerProvider.notifier).load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Видео опубликовано!'),
        ),
      );
      Navigator.of(context).pop(true);
    } else if (state.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(communityUploadControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый рилс'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _VideoPicker(
              chewieController: _chewieController,
              videoBytesLength: _videoBytes?.length,
              onPickVideo: _pickVideo,
              onRecordVideo: _recordVideo,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Название',
                hintText: 'Например: Боул с киноа и нутом',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Введите название' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _authorCtrl,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Автор',
                helperText: 'Имя из вашего профиля',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Описание',
                hintText: 'Расскажите о рецепте, ингредиентах и лайфхаках',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tagsCtrl,
              decoration: const InputDecoration(
                labelText: 'Теги',
                helperText: 'Через запятую: боул, здоровое питание, кето',
              ),
            ),
            const SizedBox(height: 12),
            // Выбор категории
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Категория',
                helperText: 'Выберите категорию для вашего видео',
              ),
              items: _videoCategories.map((category) {
                return DropdownMenuItem(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value;
                });
              },
            ),
            const SizedBox(height: 16),
            _ThumbnailPicker(
              thumbnailFile: _thumbnailFile,
              onPick: _pickThumbnail,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _canSubmit && !uploadState.uploading ? _submit : null,
              icon: uploadState.uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(uploadState.uploading
                  ? 'Загружаем...'
                  : 'Отправить на модерацию'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPicker extends StatefulWidget {
  const _VideoPicker({
    required this.chewieController,
    this.videoBytesLength,
    required this.onPickVideo,
    this.onRecordVideo,
  });

  final ChewieController? chewieController;
  /// Когда видео выбрано, но превью нет (например на веб) — показываем "Видео выбрано"
  final int? videoBytesLength;
  final VoidCallback onPickVideo;
  final VoidCallback? onRecordVideo;

  @override
  State<_VideoPicker> createState() => _VideoPickerState();
}

class _VideoPickerState extends State<_VideoPicker> {
  bool _isPaused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Видео',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: widget.chewieController != null
              ? () {
                  // Тап на видео для паузы/плей
                  setState(() {
                    _isPaused = !_isPaused;
                  });
                  if (_isPaused) {
                    widget.chewieController!.pause();
                  } else {
                    widget.chewieController!.play();
                  }
                }
              : widget.onPickVideo,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: widget.chewieController != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Chewie(controller: widget.chewieController!),
                        ),
                        // Индикатор паузы
                        if (_isPaused)
                          IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.pause_circle_filled,
                                  color: Colors.white,
                                  size: 60,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : (widget.videoBytesLength != null && widget.videoBytesLength! > 0)
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, size: 48, color: Colors.green),
                              const SizedBox(height: 8),
                              Text(
                                'Видео выбрано (${(widget.videoBytesLength! / (1024 * 1024)).toStringAsFixed(1)} МБ)',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: widget.onPickVideo,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Выбрать другое'),
                              ),
                            ],
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.video_call_outlined, size: 48),
                              const SizedBox(height: 8),
                              const Text('Выберите ролик (до 3 минут)'),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: widget.onPickVideo,
                                    icon: const Icon(Icons.photo_library),
                                    label: const Text('Галерея'),
                                  ),
                                  const SizedBox(width: 12),
                                  if (widget.onRecordVideo != null)
                                    ElevatedButton.icon(
                                      onPressed: widget.onRecordVideo,
                                      icon: const Icon(Icons.videocam),
                                      label: const Text('Камера'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThumbnailPicker extends StatelessWidget {
  const _ThumbnailPicker({
    required this.thumbnailFile,
    required this.onPick,
  });

  final XFile? thumbnailFile;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Обложка (опционально)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onPick,
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: thumbnailFile != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: kIsWeb
                        ? FutureBuilder<Uint8List>(
                            future: thumbnailFile!.readAsBytes(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                );
                              }
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            },
                          )
                        : Image.file(
                            // ignore: avoid_dynamic_calls
                            (io.File as dynamic)(thumbnailFile!.path),
                            fit: BoxFit.cover,
                          ),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.photo_outlined),
                        SizedBox(height: 4),
                        Text('Добавьте превью'),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

