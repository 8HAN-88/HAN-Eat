// Экран создания рецепта в канале
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/channel_service.dart';
import '../../../services/media_upload_service.dart';

class CreateChannelRecipeScreen extends ConsumerStatefulWidget {
  final int channelId;
  final String channelName;
  
  const CreateChannelRecipeScreen({
    Key? key,
    required this.channelId,
    required this.channelName,
  }) : super(key: key);
  
  @override
  ConsumerState<CreateChannelRecipeScreen> createState() => _CreateChannelRecipeScreenState();
}

class _CreateChannelRecipeScreenState extends ConsumerState<CreateChannelRecipeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _ingredientController = TextEditingController();
  final _stepController = TextEditingController();
  final _prepTimeController = TextEditingController();
  final _cookTimeController = TextEditingController();
  final _servingsController = TextEditingController();
  final _caloriesController = TextEditingController();
  
  List<String> _ingredients = [];
  List<RecipeStep> _steps = [];
  List<String> _tags = [];
  String? _mainImageUrl;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  
  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _ingredientController.dispose();
    _stepController.dispose();
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _servingsController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }
  
  void _addIngredient() {
    final text = _ingredientController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _ingredients.add(text);
        _ingredientController.clear();
      });
    }
  }
  
  void _removeIngredient(int index) {
    setState(() {
      _ingredients.removeAt(index);
    });
  }
  
  void _addStep() {
    final text = _stepController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _steps.add(RecipeStep(
          number: _steps.length + 1,
          text: text,
          imageUrl: null,
        ));
        _stepController.clear();
      });
    }
  }
  
  void _removeStep(int index) {
    setState(() {
      _steps.removeAt(index);
      // Перенумеровываем шаги
      for (int i = 0; i < _steps.length; i++) {
        _steps[i] = RecipeStep(
          number: i + 1,
          text: _steps[i].text,
          imageUrl: _steps[i].imageUrl,
        );
      }
    });
  }
  
  Future<void> _pickMainImage() async {
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
          setState(() => _isLoading = true);
          try {
            // Загружаем изображение
            final uploadResult = await MediaUploadService.uploadMediaFile(
              file: image,
              fileType: 'image',
            );
            setState(() {
              _mainImageUrl = uploadResult.url;
              _isLoading = false;
            });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ошибка загрузки изображения: $e')),
            );
          }
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора изображения: $e')),
        );
      }
    }
  }
  
  Future<void> _addStepImage(int stepIndex) async {
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
          setState(() => _isLoading = true);
          try {
            final uploadResult = await MediaUploadService.uploadMediaFile(
              file: image,
              fileType: 'image',
            );
            setState(() {
              _steps[stepIndex] = RecipeStep(
                number: _steps[stepIndex].number,
                text: _steps[stepIndex].text,
                imageUrl: uploadResult.url,
              );
              _isLoading = false;
            });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ошибка загрузки изображения: $e')),
            );
          }
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора изображения: $e')),
        );
      }
    }
  }
  
  Future<void> _handlePublish() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы один ингредиент')),
      );
      return;
    }
    
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы один шаг')),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      // Формируем медиа
      List<Map<String, dynamic>> media = [];
      if (_mainImageUrl != null) {
        media.add({
          'type': 'image',
          'url': _mainImageUrl,
        });
      }
      
      // Формируем шаги
      List<Map<String, dynamic>> stepsData = _steps.map((step) => {
        'number': step.number,
        'text': step.text,
        if (step.imageUrl != null) 'image_url': step.imageUrl,
      }).toList();
      
      final result = await ChannelService.createChannelRecipe(
        channelId: widget.channelId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        ingredients: _ingredients,
        steps: stepsData,
        media: media.isNotEmpty ? media : null,
        prepTimeMin: _prepTimeController.text.trim().isEmpty
            ? null
            : int.tryParse(_prepTimeController.text.trim()),
        cookTimeMin: _cookTimeController.text.trim().isEmpty
            ? null
            : int.tryParse(_cookTimeController.text.trim()),
        servings: _servingsController.text.trim().isEmpty
            ? null
            : int.tryParse(_servingsController.text.trim()),
        calories: _caloriesController.text.trim().isEmpty
            ? null
            : int.tryParse(_caloriesController.text.trim()),
        tags: _tags.isNotEmpty ? _tags : null,
      );
      
      if (mounted) {
        context.pop(true); // Возвращаемся с успехом
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Рецепт опубликован')),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка публикации: $errorMessage'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
        debugPrint('Ошибка публикации рецепта: $e');
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
        title: Text('Новый рецепт в ${widget.channelName}'),
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
              onPressed: _handlePublish,
              child: const Text('Опубликовать'),
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
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Название рецепта *',
                  hintText: 'Например: Паста карбонара',
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
                  labelText: 'Описание (опционально)',
                  hintText: 'Расскажите о рецепте...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              
              // Главное изображение
              Card(
                child: InkWell(
                  onTap: _pickMainImage,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_mainImageUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _mainImageUrl!,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Icon(Icons.add_photo_alternate, size: 64, color: theme.colorScheme.primary),
                        const SizedBox(height: 8),
                        Text(
                          _mainImageUrl != null ? 'Изменить изображение' : 'Добавить главное изображение',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Ингредиенты
              Text('Ингредиенты *', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ingredientController,
                      decoration: const InputDecoration(
                        hintText: 'Добавить ингредиент',
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (_) => _addIngredient(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addIngredient,
                  ),
                ],
              ),
              if (_ingredients.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...List.generate(_ingredients.length, (index) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      title: Text(_ingredients[index]),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _removeIngredient(index),
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 16),
              
              // Шаги
              Text('Шаги приготовления *', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stepController,
                      decoration: const InputDecoration(
                        hintText: 'Добавить шаг',
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (_) => _addStep(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addStep,
                  ),
                ],
              ),
              if (_steps.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...List.generate(_steps.length, (index) {
                  final step = _steps[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text('${step.number}'),
                      ),
                      title: Text(step.text),
                      subtitle: step.imageUrl != null
                          ? Image.network(step.imageUrl!, height: 100, fit: BoxFit.cover)
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (step.imageUrl == null)
                            IconButton(
                              icon: const Icon(Icons.add_photo_alternate),
                              onPressed: () => _addStepImage(index),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => _removeStep(index),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 16),
              
              // Дополнительная информация
              Text('Дополнительная информация', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
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
                  const SizedBox(width: 8),
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
              const SizedBox(height: 8),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _caloriesController,
                      decoration: const InputDecoration(
                        labelText: 'Калории',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class RecipeStep {
  final int number;
  final String text;
  final String? imageUrl;
  
  RecipeStep({
    required this.number,
    required this.text,
    this.imageUrl,
  });
}

