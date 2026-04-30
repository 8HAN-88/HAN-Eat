import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../../models/post.dart';
import '../../../models/post_types.dart';
import '../../../services/post_publication_service.dart';
import '../../../services/auth_service.dart';

/// Экран создания поста
class CreatePostScreen extends StatefulWidget {
  final String? communityId;

  const CreatePostScreen({
    super.key,
    this.communityId,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _textController = TextEditingController();
  final _linkController = TextEditingController();
  List<File> _selectedImages = [];
  List<XFile> _selectedXFiles = [];
  List<Uint8List> _selectedImageBytes = [];
  PostType _selectedType = PostType.text;
  bool _isLoading = false;

  @override
  void dispose() {
    _textController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedXFiles = images;
        if (kIsWeb) {
          // На вебе загружаем bytes
          Future.wait(images.map((img) => img.readAsBytes())).then((bytesList) {
            setState(() {
              _selectedImageBytes = bytesList;
            });
          });
        } else {
          _selectedImages = images.map((img) => File(img.path)).toList();
        }
        _selectedType = images.length == 1 ? PostType.photo : PostType.photoGallery;
      });
    }
  }

  Future<void> _publishPost() async {
    if (_textController.text.isEmpty && 
        (kIsWeb ? _selectedImageBytes : _selectedImages).isEmpty && 
        _linkController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте текст, фото или ссылку')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // TODO: Загрузить изображения в Firebase Storage и получить URLs
      List<String>? photoUrls;
      if ((kIsWeb ? _selectedImageBytes : _selectedImages).isNotEmpty) {
        photoUrls = []; // TODO: Загрузить и получить URLs
      }

      await PostPublicationService.publishPost(
        communityId: widget.communityId,
        type: _selectedType,
        text: _textController.text.isEmpty ? null : _textController.text,
        photos: photoUrls,
        linkUrl: _linkController.text.isEmpty ? null : _linkController.text,
        tags: _extractTags(_textController.text),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
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

  List<String> _extractTags(String text) {
    final regex = RegExp(r'#\w+');
    return regex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Создать пост'),
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
              onPressed: _publishPost,
              child: const Text('Опубликовать'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _textController,
            decoration: const InputDecoration(
              hintText: 'Что у вас нового?',
              border: InputBorder.none,
            ),
            maxLines: null,
            minLines: 5,
          ),
          if ((_selectedImages.isNotEmpty || _selectedImageBytes.isNotEmpty))
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: kIsWeb ? _selectedImageBytes.length : _selectedImages.length,
                itemBuilder: (context, index) => Stack(
                  children: [
                    kIsWeb && _selectedImageBytes.isNotEmpty
                        ? Image.memory(
                            _selectedImageBytes[index],
                            width: 200,
                            fit: BoxFit.cover,
                          )
                        : _selectedImages.isNotEmpty
                            ? Image.file(
                                _selectedImages[index],
                                width: 200,
                                fit: BoxFit.cover,
                              )
                            : const SizedBox.shrink(),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            if (kIsWeb) {
                              _selectedImageBytes.removeAt(index);
                              _selectedXFiles.removeAt(index);
                            } else {
                              _selectedImages.removeAt(index);
                            }
                            if ((kIsWeb ? _selectedImageBytes : _selectedImages).isEmpty) {
                              _selectedType = PostType.text;
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: const Icon(Icons.photo_library),
                onPressed: _pickImages,
                tooltip: 'Фото',
              ),
              IconButton(
                icon: const Icon(Icons.link),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Добавить ссылку'),
                      content: TextField(
                        controller: _linkController,
                        decoration: const InputDecoration(hintText: 'URL'),
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            setState(() => _selectedType = PostType.link);
                          }
                        },
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Отмена'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() => _selectedType = PostType.link);
                          },
                          child: const Text('Добавить'),
                        ),
                      ],
                    ),
                  );
                },
                tooltip: 'Ссылка',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

