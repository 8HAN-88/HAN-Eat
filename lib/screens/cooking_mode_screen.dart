import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/recipe.dart';
import '../services/server_config.dart';

/// Полноэкранный пошаговый режим готовки: один шаг на экран, крупный текст.
class CookingModeScreen extends StatefulWidget {
  const CookingModeScreen({
    super.key,
    required this.recipe,
  });

  final Recipe recipe;

  @override
  State<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends State<CookingModeScreen> {
  late final List<Map<String, dynamic>> _steps;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _steps = widget.recipe.translatedSteps?.isNotEmpty == true
        ? List<Map<String, dynamic>>.from(widget.recipe.translatedSteps!)
        : List<Map<String, dynamic>>.from(widget.recipe.steps);
    if (_steps.isEmpty) {
      _steps.add({
        'number': 1,
        'step': 'Нет пошаговой инструкции для этого рецепта.',
        'image': null,
      });
    }
  }

  Map<String, dynamic> get _currentStep => _steps[_currentIndex];
  String get _stepText {
    final s = _currentStep;
    final t = s['step'] ?? s['text'] ?? s['instruction'];
    return t?.toString() ?? '';
  }

  String? get _stepImageUrl {
    final img = _currentStep['image'] ?? _currentStep['image_url'];
    if (img == null || img.toString().trim().isEmpty) return null;
    final url = img.toString().trim();
    if (url.startsWith('http')) return url;
    return ServerConfig.resolveRecipeImageUrl(url);
  }

  /// Извлекает время в минутах из текста шага (например "варить 10 минут", "15 мин").
  static int? _parseMinutesFromStep(String text) {
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    final patterns = [
      RegExp(r'(\d+)\s*(?:мин|минут|минуты|мин\.)', caseSensitive: false),
      RegExp(r'(\d+)\s*(?:min|minute|minutes)', caseSensitive: false),
      RegExp(r'(?:в течение|в течение|около|примерно|до)\s*(\d+)\s*(?:мин|минут|min)', caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(lower);
      if (m != null) {
        final n = int.tryParse(m.group(1) ?? '');
        if (n != null && n > 0 && n <= 300) return n;
      }
    }
    return null;
  }

  void _startTimer(int minutes) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TimerDialog(minutes: minutes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.recipe.translatedTitle ?? widget.recipe.title;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Индикатор шага
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Шаг ${_currentIndex + 1} из ${_steps.length}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _steps.length > 1
                          ? (_currentIndex + 1) / _steps.length
                          : 1.0,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            // Контент шага
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_stepImageUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: _stepImageUrl!,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            height: 220,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: 220,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_not_supported, size: 48),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      _stepText,
                      style: theme.textTheme.titleLarge?.copyWith(
                        height: 1.5,
                        fontSize: 22,
                      ),
                    ),
                    if (_parseMinutesFromStep(_stepText) != null) ...[
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: () => _startTimer(_parseMinutesFromStep(_stepText)!),
                        icon: const Icon(Icons.timer_outlined),
                        label: Text('Таймер ${_parseMinutesFromStep(_stepText)} мин'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Навигация
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_currentIndex > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() => _currentIndex--);
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Назад'),
                      ),
                    ),
                  if (_currentIndex > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: _currentIndex > 0 ? 1 : 2,
                    child: FilledButton.icon(
                      onPressed: _currentIndex < _steps.length - 1
                          ? () {
                              setState(() => _currentIndex++);
                            }
                          : () => Navigator.of(context).pop(),
                      icon: Icon(
                        _currentIndex < _steps.length - 1
                            ? Icons.arrow_forward
                            : Icons.done,
                      ),
                      label: Text(
                        _currentIndex < _steps.length - 1 ? 'Далее' : 'Готово',
                      ),
                    ),
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

class _TimerDialog extends StatefulWidget {
  const _TimerDialog({required this.minutes});

  final int minutes;

  @override
  State<_TimerDialog> createState() => _TimerDialogState();
}

class _TimerDialogState extends State<_TimerDialog> {
  int _remainingSeconds = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.minutes * 60;
    _tick();
  }

  void _tick() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        setState(() => _finished = true);
        return;
      }
      setState(() => _remainingSeconds--);
      _tick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mins = _remainingSeconds ~/ 60;
    final secs = _remainingSeconds % 60;
    final timeStr = '$mins:${secs.toString().padLeft(2, '0')}';
    final total = (widget.minutes * 60).clamp(1, 999999);
    final progress = _finished ? 1.0 : (_remainingSeconds / total).clamp(0.0, 1.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _finished ? Icons.check : Icons.timer_outlined,
                    size: 18,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _finished ? 'Готово!' : 'Таймер',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_finished)
              SizedBox(
                width: 116,
                height: 116,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                    Text(
                      timeStr,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Время вышло.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(_finished ? 'Отлично' : 'Закрыть'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
