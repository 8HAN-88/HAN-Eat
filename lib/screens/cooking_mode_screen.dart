import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/subscription/recipe_translation_access.dart';
import '../core/theme/app_tokens.dart';
import '../core/theme/color_schemes.dart';
import '../features/settings/application/analysis_mode_controller.dart';
import '../models/recipe.dart';
import '../services/api_service.dart';
import '../services/server_config.dart';

/// Полноэкранный пошаговый режим готовки: один шаг на экран, крупный текст.
class CookingModeScreen extends ConsumerStatefulWidget {
  const CookingModeScreen({
    super.key,
    required this.recipe,
  });

  final Recipe recipe;

  @override
  ConsumerState<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends ConsumerState<CookingModeScreen> {
  List<Map<String, dynamic>> _steps = [];
  bool _loadingSteps = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveSteps());
  }

  List<Map<String, dynamic>> _pickSteps(Recipe recipe, String lang) {
    final useTranslated = recipe.translatedSteps != null &&
        recipe.translatedSteps!.isNotEmpty &&
        !RecipeTranslationAccess.stepsLookUntranslated(
          recipe.translatedSteps!,
          lang,
        );
    final raw = useTranslated ? recipe.translatedSteps! : recipe.steps;
    return List<Map<String, dynamic>>.from(raw);
  }

  Future<void> _resolveSteps() async {
    final lang = ref.read(analysisSettingsProvider).language;
    var steps = _pickSteps(widget.recipe, lang);

    final needsFetch = RecipeTranslationAccess.localeExpectsTranslation(lang) &&
        RecipeTranslationAccess.stepsLookUntranslated(steps, lang);

    if (needsFetch) {
      final numericId = int.tryParse(widget.recipe.id.toString());
      if (numericId != null) {
        final result =
            await ApiService.loadRecipeById(numericId, language: lang);
        final refreshed = result.recipe;
        if (refreshed != null) {
          final localized = _pickSteps(refreshed, lang);
          if (!RecipeTranslationAccess.stepsLookUntranslated(localized, lang)) {
            steps = localized;
          }
        }
      }
    }

    if (!mounted) return;
    if (steps.isEmpty) {
      steps = [
        {
          'number': 1,
          'step': 'Нет пошаговой инструкции для этого рецепта.',
          'image': null,
        },
      ];
    }
    setState(() {
      _steps = steps;
      _loadingSteps = false;
    });
  }

  Map<String, dynamic> get _currentStep => _steps[_currentIndex];
  String get _stepText {
    final s = _currentStep;
    final t = s['step'] ?? s['text'] ?? s['instruction'];
    return t?.toString().trim() ?? '';
  }

  String? get _stepImageUrl {
    final img = _currentStep['image'] ?? _currentStep['image_url'];
    if (img == null || img.toString().trim().isEmpty) return null;
    final url = img.toString().trim();
    if (url.startsWith('http')) return url;
    return ServerConfig.resolveRecipeImageUrl(url);
  }

  static int? _parseMinutesFromStep(String text) {
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    final patterns = [
      RegExp(r'(\d+)\s*(?:мин|минут|минуты|мин\.)', caseSensitive: false),
      RegExp(r'(\d+)\s*(?:min|minute|minutes)', caseSensitive: false),
      RegExp(
        r'(?:в течение|около|примерно|до)\s*(\d+)\s*(?:мин|минут|min)',
        caseSensitive: false,
      ),
      RegExp(r'parboil[^.]{0,40}?(\d+)\s*minutes?', caseSensitive: false),
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
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Таймер',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, _, __) => _CookingTimerSheet(minutes: minutes),
      transitionBuilder: (ctx, anim, _, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.recipe.translatedTitle ?? widget.recipe.title;
    final timerMinutes = _parseMinutesFromStep(_stepText);

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
        child: _loadingSteps
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'Шаг ${_currentIndex + 1} из ${_steps.length}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _steps.length > 1
                                  ? (_currentIndex + 1) / _steps.length
                                  : 1.0,
                              minHeight: 6,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  height: 220,
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.image_not_supported,
                                      size: 48),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          Text(
                            _stepText,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              height: 1.55,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (timerMinutes != null) ...[
                            const SizedBox(height: 24),
                            Material(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                onTap: () => _startTimer(timerMinutes),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              AppColors.gradientStart,
                                              AppColors.gradientEnd,
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.timer_outlined,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Запустить таймер',
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              '$timerMinutes мин',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.play_circle_fill,
                                        color: theme.colorScheme.primary,
                                        size: 32,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (_currentIndex > 0)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _currentIndex--),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Назад'),
                            ),
                          ),
                        if (_currentIndex > 0) const SizedBox(width: 12),
                        Expanded(
                          flex: _currentIndex > 0 ? 1 : 2,
                          child: FilledButton.icon(
                            onPressed: _currentIndex < _steps.length - 1
                                ? () => setState(() => _currentIndex++)
                                : () => Navigator.of(context).pop(),
                            icon: Icon(
                              _currentIndex < _steps.length - 1
                                  ? Icons.arrow_forward
                                  : Icons.done,
                            ),
                            label: Text(
                              _currentIndex < _steps.length - 1
                                  ? 'Далее'
                                  : 'Готово',
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

class _CookingTimerSheet extends StatefulWidget {
  const _CookingTimerSheet({required this.minutes});

  final int minutes;

  @override
  State<_CookingTimerSheet> createState() => _CookingTimerSheetState();
}

class _CookingTimerSheetState extends State<_CookingTimerSheet>
    with SingleTickerProviderStateMixin {
  late final int _totalSeconds;
  late DateTime _endAt;
  Timer? _tick;
  int _remainingSeconds = 0;
  bool _finished = false;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _totalSeconds = widget.minutes * 60;
    _remainingSeconds = _totalSeconds;
    _endAt = DateTime.now().add(Duration(seconds: _totalSeconds));
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted) return;
    final left = _endAt.difference(DateTime.now()).inSeconds;
    if (left <= 0) {
      _tick?.cancel();
      setState(() {
        _remainingSeconds = 0;
        _finished = true;
      });
      HapticFeedback.heavyImpact();
      _pulse.repeat(reverse: true);
      return;
    }
    setState(() => _remainingSeconds = left);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  String get _timeLabel {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final progress = _finished
        ? 1.0
        : (1 - _remainingSeconds / _totalSeconds).clamp(0.0, 1.0);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _finished ? 'Время вышло' : 'Таймер',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        final scale =
                            _finished ? 1.0 + _pulse.value * 0.04 : 1.0;
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: SizedBox(
                        width: 232,
                        height: 232,
                        child: CustomPaint(
                          painter: _TimerRingPainter(
                            progress: progress,
                            finished: _finished,
                          ),
                          child: Center(
                            child: Text(
                              _finished ? '00:00' : _timeLabel,
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontSize: 56,
                                fontWeight: FontWeight.w300,
                                letterSpacing: -1.5,
                                height: 1,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: _finished
                                    ? AppColors.primary
                                    : cs.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _finished
                          ? 'Можно продолжать готовку'
                          : 'из ${widget.minutes} мин',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(_finished ? 'Отлично' : 'Свернуть'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  _TimerRingPainter({required this.progress, required this.finished});

  final double progress;
  final bool finished;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const stroke = 10.0;

    final track = Paint()
      ..color = const Color(0xFFE8ECF2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * 3.14159265 * progress;

    final arc = Paint()
      ..shader = const SweepGradient(
        startAngle: -1.5708,
        endAngle: 4.71239,
        colors: [
          AppColors.gradientStart,
          AppColors.gradientEnd,
          AppColors.gradientStart
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -1.5708, sweep, false, arc);

    if (finished) {
      final glow = Paint()
        ..color = AppColors.primary.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawArc(rect, -1.5708, 2 * 3.14159265, false, glow);
    }
  }

  @override
  bool shouldRepaint(covariant _TimerRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.finished != finished;
  }
}
