// Редактирование поста в профиле (лента без канала)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/recipe/recipe_nutrition_input.dart';
import '../../../models/post_model.dart';
import '../../../services/api_service.dart';
import '../../../services/feed_cache_service.dart';
import '../../../services/post_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/url_validator.dart';
import '../../../widgets/recipe_nutrition_form_section.dart';
import '../../../widgets/create_poll_form_section.dart';
import '../../../widgets/app_empty_state.dart';

class EditProfilePostScreen extends ConsumerStatefulWidget {
  final int postId;

  const EditProfilePostScreen({super.key, required this.postId});

  @override
  ConsumerState<EditProfilePostScreen> createState() =>
      _EditProfilePostScreenState();
}

class _EditProfilePostScreenState extends ConsumerState<EditProfilePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _linkUrlController = TextEditingController();
  final _linkPreviewController = TextEditingController();
  final _prepTimeController = TextEditingController();
  final _cookTimeController = TextEditingController();
  final _servingsController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  final _fiberController = TextEditingController();
  final List<TextEditingController> _ingredientControllers = [];
  final List<TextEditingController> _stepControllers = [];
  final _pollQuestionController = TextEditingController();
  final List<TextEditingController> _pollOptionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  PostModel? _post;
  Timer? _linkPreviewDebounce;
  bool _isLoadingLinkPreview = false;
  Map<String, dynamic>? _linkPreviewMeta;
  bool _linkPreviewFailed = false;

  bool get _isLink => _post?.type == 'link';
  bool get _isRecipe => _post?.type == 'recipe';
  bool get _isPoll => _post?.type == 'poll';

  int get _pollTotalVotes {
    final poll = _post?.poll;
    if (poll == null) return 0;
    return poll.options.fold<int>(0, (sum, o) => sum + o.votes);
  }

  bool get _canEditPollContent =>
      _isPoll && !(_post?.poll?.isClosed ?? false) && _pollTotalVotes == 0;

  @override
  void initState() {
    super.initState();
    _linkUrlController.addListener(_scheduleLinkPreviewLoad);
    _loadPost();
  }

  @override
  void dispose() {
    _linkPreviewDebounce?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _linkUrlController.dispose();
    _linkPreviewController.dispose();
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _servingsController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _fiberController.dispose();
    for (final c in _ingredientControllers) {
      c.dispose();
    }
    for (final c in _stepControllers) {
      c.dispose();
    }
    _pollQuestionController.dispose();
    for (final c in _pollOptionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addPollOption() {
    if (_pollOptionControllers.length >= 10) return;
    setState(() {
      _pollOptionControllers.add(TextEditingController());
    });
  }

  void _removePollOption(int index) {
    if (_pollOptionControllers.length <= 2) return;
    setState(() {
      _pollOptionControllers[index].dispose();
      _pollOptionControllers.removeAt(index);
    });
  }

  Future<void> _loadPost() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final post = await ApiService.getPostById(widget.postId);
      if (!mounted) return;
      if (post == null) {
        setState(() {
          _loadError = 'Пост не найден';
          _isLoading = false;
        });
        return;
      }
      if (post.communityId != null) {
        setState(() {
          _loadError = 'Редактируйте пост в настройках канала';
          _isLoading = false;
        });
        return;
      }
      _post = post;
      _titleController.text = post.title ?? '';
      _descriptionController.text = post.description ?? '';
      final body = post.body;
      if (_isLink && body != null) {
        _linkUrlController.text = post.linkUrl ?? '';
        _linkPreviewController.text = post.linkPreview ?? '';
        final meta = post.linkMeta;
        if (meta != null) _linkPreviewMeta = meta;
      }
      if (_isRecipe && body != null) {
        _prepTimeController.text = (body['prep_time_min'] ?? '').toString();
        _cookTimeController.text = (body['cook_time_min'] ?? '').toString();
        _servingsController.text = (body['servings'] ?? '').toString();
        _caloriesController.text = (body['calories'] ?? '').toString();
        _proteinController.text = _nutritionText(body, 'protein');
        _carbsController.text = _nutritionText(body, 'carbs');
        _fatController.text = _nutritionText(body, 'fat');
        _fiberController.text = _nutritionText(body, 'fiber');
        final ingredients = body['ingredients'] as List<dynamic>?;
        if (ingredients != null && ingredients.isNotEmpty) {
          for (final ing in ingredients) {
            _ingredientControllers
                .add(TextEditingController(text: ing.toString()));
          }
        } else {
          _ingredientControllers.add(TextEditingController());
        }
        final steps = body['steps'] as List<dynamic>?;
        if (steps != null && steps.isNotEmpty) {
          for (final step in steps) {
            if (step is Map<String, dynamic>) {
              _stepControllers.add(TextEditingController(
                  text: step['text'] ?? step['step'] ?? ''));
            } else {
              _stepControllers.add(TextEditingController(text: step.toString()));
            }
          }
        } else {
          _stepControllers.add(TextEditingController());
        }
      }
      if (_isPoll) {
        final poll = post.poll;
        final rawPoll = body?['poll'];
        _pollQuestionController.text = poll?.question ??
            (rawPoll is Map ? rawPoll['question']?.toString() : null) ??
            '';
        for (final c in _pollOptionControllers) {
          c.dispose();
        }
        _pollOptionControllers.clear();
        if (poll != null && poll.options.isNotEmpty) {
          for (final option in poll.options) {
            _pollOptionControllers
                .add(TextEditingController(text: option.text));
          }
        } else if (rawPoll is Map) {
          final rawOpts = rawPoll['options'] as List<dynamic>?;
          if (rawOpts != null && rawOpts.isNotEmpty) {
            for (final item in rawOpts) {
              if (item is Map<String, dynamic>) {
                _pollOptionControllers.add(TextEditingController(
                  text: item['text']?.toString() ?? '',
                ));
              }
            }
          }
        }
        if (_pollOptionControllers.isEmpty) {
          _pollOptionControllers.addAll([
            TextEditingController(),
            TextEditingController(),
          ]);
        }
      }
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = userVisibleError(e, fallback: 'Не удалось загрузить пост');
        _isLoading = false;
      });
    }
  }

  String _nutritionText(Map<String, dynamic> body, String kind) {
    final nut = body['nutrition'];
    Object? v;
    switch (kind) {
      case 'protein':
        v = body['protein_g'] ?? (nut is Map ? nut['protein_g'] ?? nut['protein'] : null);
      case 'carbs':
        v = body['carbs_g'] ??
            (nut is Map ? nut['carbs_g'] ?? nut['carbohydrates'] : null);
      case 'fat':
        v = body['fat_g'] ?? (nut is Map ? nut['fat_g'] ?? nut['fat'] : null);
      case 'fiber':
        v = body['fiber_g'] ?? (nut is Map ? nut['fiber_g'] ?? nut['fiber'] : null);
      default:
        return '';
    }
    return v == null ? '' : v.toString();
  }

  void _scheduleLinkPreviewLoad() {
    if (!_isLink) return;
    _linkPreviewDebounce?.cancel();
    _linkPreviewDebounce = Timer(const Duration(milliseconds: 550), _loadLinkPreview);
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
      if (mounted) setState(() => _isLoadingLinkPreview = false);
    }
  }

  Future<void> _save() async {
    if (_post == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      if (_isPoll) {
        final description = _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim();
        if (_canEditPollContent) {
          final question = _pollQuestionController.text.trim();
          if (question.isEmpty) {
            throw Exception('Введите вопрос опроса');
          }
          final options =
              CreatePollFormSection.collectOptions(_pollOptionControllers);
          if (options == null) {
            throw Exception('Добавьте минимум 2 варианта ответа');
          }
          await PostService.updatePost(
            postId: widget.postId,
            description: description,
            pollQuestion: question,
            pollOptions: options,
          );
        } else {
          await PostService.updatePost(
            postId: widget.postId,
            description: description,
          );
        }
      } else if (_isLink) {
        final linkUrl = normalizeHttpUrl(_linkUrlController.text);
        if (linkUrl == null) {
          throw Exception('Введите корректную ссылку (http:// или https://)');
        }
        final linkPreview = _linkPreviewController.text.trim().isEmpty
            ? (_linkPreviewMeta?['title'])?.toString()
            : _linkPreviewController.text.trim();
        await PostService.updatePost(
          postId: widget.postId,
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          linkUrl: linkUrl,
          linkPreview: linkPreview,
        );
      } else if (_isRecipe) {
        final ingredients = _ingredientControllers
            .map((c) => c.text.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (ingredients.isEmpty) {
          throw Exception('Добавьте хотя бы один ингредиент');
        }
        final steps = <Map<String, dynamic>>[];
        for (var i = 0; i < _stepControllers.length; i++) {
          final text = _stepControllers[i].text.trim();
          if (text.isEmpty) continue;
          steps.add({
            'number': steps.length + 1,
            'text': text,
            'step': text,
          });
        }
        if (steps.isEmpty) {
          throw Exception('Добавьте хотя бы один шаг');
        }
        await PostService.updatePost(
          postId: widget.postId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          ingredients: ingredients,
          steps: steps,
          prepTimeMin: parseIntField(_prepTimeController.text),
          cookTimeMin: parseIntField(_cookTimeController.text),
          servings: parseIntField(_servingsController.text),
          calories: parseIntField(_caloriesController.text),
        );
      } else {
        await PostService.updatePost(
          postId: widget.postId,
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
        );
      }
      final refreshed = await ApiService.getPostById(widget.postId);
      if (refreshed != null) {
        try {
          await FeedCacheService.instance.upsertPostModelInCache(refreshed);
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пост обновлён')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiClientException
          ? e.message
          : e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать пост'),
        actions: [
          if (!_isLoading && _loadError == null)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Не удалось открыть пост',
        subtitle: _loadError,
        action: FilledButton(
          onPressed: _loadPost,
          child: const Text('Повторить'),
        ),
      );
    }
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isPoll && _canEditPollContent) ...[
            CreatePollFormSection(
              questionController: _pollQuestionController,
              optionControllers: _pollOptionControllers,
              onAddOption: _addPollOption,
              onRemoveOption: _removePollOption,
            ),
            const SizedBox(height: 16),
          ] else if (_isPoll) ...[
            Text(
              _post?.poll?.question ??
                  _post?.body?['poll']?['question']?.toString() ??
                  'Опрос',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              (_post?.poll?.isClosed ?? false)
                  ? 'Опрос закрыт — можно изменить только комментарий.'
                  : 'После первого голоса можно изменить только комментарий.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
          ],
          if (!_isLink && !_isPoll) ...[
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: _isRecipe ? 'Название рецепта *' : 'Заголовок',
              ),
              validator: _isRecipe
                  ? (v) =>
                      (v == null || v.trim().isEmpty) ? 'Введите название' : null
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: _isLink
                  ? 'Подпись'
                  : _isPoll
                      ? 'Комментарий к опросу'
                      : 'Описание',
            ),
            maxLines: 4,
          ),
          if (_isLink) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _linkUrlController,
              decoration: const InputDecoration(labelText: 'Ссылка *'),
              validator: (v) {
                if (normalizeHttpUrl(v ?? '') == null) {
                  return 'Введите корректный URL';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _linkPreviewController,
              decoration: const InputDecoration(labelText: 'Заголовок превью'),
            ),
            if (_isLoadingLinkPreview)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_linkPreviewFailed)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Не удалось загрузить превью — пост всё равно можно сохранить',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
          ],
          if (_isRecipe) ...[
            const SizedBox(height: 16),
            const Text('Ингредиенты', style: TextStyle(fontWeight: FontWeight.w600)),
            ..._ingredientControllers.asMap().entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: e.value,
                        decoration: InputDecoration(
                          labelText: 'Ингредиент ${e.key + 1}',
                        ),
                      ),
                    ),
                    if (_ingredientControllers.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          setState(() {
                            e.value.dispose();
                            _ingredientControllers.removeAt(e.key);
                          });
                        },
                      ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _ingredientControllers.add(TextEditingController());
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Добавить ингредиент'),
            ),
            const SizedBox(height: 8),
            const Text('Шаги', style: TextStyle(fontWeight: FontWeight.w600)),
            ..._stepControllers.asMap().entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: e.value,
                        decoration: InputDecoration(
                          labelText: 'Шаг ${e.key + 1}',
                        ),
                        maxLines: 3,
                      ),
                    ),
                    if (_stepControllers.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          setState(() {
                            e.value.dispose();
                            _stepControllers.removeAt(e.key);
                          });
                        },
                      ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _stepControllers.add(TextEditingController());
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Добавить шаг'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _prepTimeController,
                    decoration: const InputDecoration(labelText: 'Подготовка (мин)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _cookTimeController,
                    decoration: const InputDecoration(labelText: 'Готовка (мин)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _servingsController,
                    decoration: const InputDecoration(labelText: 'Порции'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
              getDescription: () => _descriptionController.text.trim(),
            ),
          ],
        ],
      ),
    );
  }
}
