import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/subscription_status_cache.dart';
import '../../subscription/creator_upsell.dart';
import '../data/story_service.dart';

/// Экран камеры для создания сторис (фото + видео).
/// Загружает выбранное медиа и создаёт сторис на backend.
class StoryCameraScreen extends StatefulWidget {
  const StoryCameraScreen({super.key});

  @override
  State<StoryCameraScreen> createState() => _StoryCameraScreenState();
}

class _StoryCameraScreenState extends State<StoryCameraScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedFile;
  bool _isVideo = false;
  bool _isPublishing = false;
  String _visibility = 'public';
  final _captionController = TextEditingController();

  static const _visibilityOptions = <(String, String, IconData)>[
    ('public', 'Все', Icons.public),
    ('followers', 'Подписчики', Icons.group_outlined),
    ('close_friends', 'Близкие', Icons.favorite_outline),
    ('private', 'Только я', Icons.lock_outline),
  ];

  Future<void> _takePhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      imageQuality: 92,
    );
    if (photo == null) return;

    setState(() {
      _selectedFile = photo;
      _isVideo = false;
    });
  }

  Future<void> _recordVideo() async {
    final XFile? video = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: Duration(
        seconds: hasFlexFeature('longer_stories') ? 60 : 30,
      ),
    );
    if (video == null) return;

    setState(() {
      _selectedFile = video;
      _isVideo = true;
    });

  }

  Future<void> _publish() async {
    if (_selectedFile == null) return;
    setState(() => _isPublishing = true);
    try {
      await StoryService.uploadAndCreateStory(
        file: _selectedFile!,
        isVideo: _isVideo,
        caption: _captionController.text.trim().isEmpty
            ? null
            : _captionController.text.trim(),
        visibility: _visibility,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось опубликовать сторис: $e')),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  void _retake() {
    setState(() {
      _selectedFile = null;
      _isVideo = false;
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedFile != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Предпросмотр', style: TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: _isVideo
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_outline,
                      color: Colors.white,
                      size: 88,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedFile!.name,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                )
              : FutureBuilder<List<int>>(
                  future: _selectedFile!.readAsBytes(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator(color: Colors.white);
                    }
                    return Image.memory(
                      Uint8List.fromList(snapshot.data!),
                      fit: BoxFit.contain,
                    );
                  },
                ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _captionController,
                  enabled: !_isPublishing,
                  maxLength: 500,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Добавить подпись',
                    hintStyle: TextStyle(color: Colors.white54),
                    counterStyle: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Кто увидит',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in _visibilityOptions)
                      ChoiceChip(
                        avatar: Icon(
                          option.$3,
                          size: 16,
                          color: _visibility == option.$1
                              ? Colors.black
                              : Colors.white70,
                        ),
                        label: Text(option.$2),
                        selected: _visibility == option.$1,
                        onSelected: _isPublishing
                            ? null
                            : (_) {
                                if (option.$1 == 'close_friends' &&
                                    SubscriptionStatusCache.peek()
                                            ?.hasFeature('story_close_friends') !=
                                        true) {
                                  showCreatorUpsell(context);
                                  return;
                                }
                                setState(() => _visibility = option.$1);
                              },
                        selectedColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _visibility == option.$1
                              ? Colors.black
                              : Colors.white,
                        ),
                        backgroundColor: Colors.white12,
                        side: BorderSide.none,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isPublishing ? null : _retake,
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        child: const Text('Переснять'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isPublishing ? null : _publish,
                        child: _isPublishing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Опубликовать'),
                      ),
                    ),
                  ],
                ),
                if (_isPublishing) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Загружаем сторис...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Камера / выбор
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Создать сторис', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt, size: 80, color: Colors.white54),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Сделать фото'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _recordVideo,
              icon: const Icon(Icons.videocam),
              label: Text(
                hasFlexFeature('longer_stories')
                    ? 'Записать видео (до 60 сек)'
                    : 'Записать видео (до 30 сек)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
