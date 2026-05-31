import 'package:flutter/material.dart';
import '../../../../utils/api_error_parser.dart';
import '../../../../services/subscription_service.dart';
import '../../../../widgets/survey_section_card.dart';

/// Причина отмены подписки (id + подпись для тикета).
class SubscriptionCancelReason {
  const SubscriptionCancelReason(this.id, this.label);

  final String id;
  final String label;

  static const options = [
    SubscriptionCancelReason('too_expensive', 'Слишком дорого'),
    SubscriptionCancelReason('not_using', 'Редко пользуюсь приложением'),
    SubscriptionCancelReason('missing_features', 'Не хватает нужных функций'),
    SubscriptionCancelReason('bugs', 'Технические проблемы'),
    SubscriptionCancelReason('found_alternative', 'Нашёл другое приложение'),
    SubscriptionCancelReason('temporary', 'Нужна временная пауза'),
    SubscriptionCancelReason('other', 'Другое'),
  ];
}

/// Ответы опроса перед отменой подписки.
class SubscriptionCancelSurveyResult {
  const SubscriptionCancelSurveyResult({
    required this.reason,
    this.otherReasonDetail,
    this.improvementFeedback,
  });

  final SubscriptionCancelReason reason;
  final String? otherReasonDetail;
  final String? improvementFeedback;

  String get reasonLine {
    if (reason.id == 'other' &&
        otherReasonDetail != null &&
        otherReasonDetail!.trim().isNotEmpty) {
      return '${reason.label}: ${otherReasonDetail!.trim()}';
    }
    return reason.label;
  }
}

/// Опрос → подтверждение → запрос отмены. Возвращает true при успехе.
Future<bool> runSubscriptionCancelFlow(BuildContext context) async {
  final survey = await showSubscriptionCancelSurveySheet(context);
  if (survey == null || !context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Отменить подписку?'),
      content: const Text(
        'Ваш запрос будет отправлен в поддержку. '
        'Подписка останется активной до даты истечения после обработки.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Назад'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Отправить запрос'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    final response = await SubscriptionService.requestCancelSubscription(
      cancellationReason: survey.reasonLine,
      improvementFeedback: survey.improvementFeedback,
    );
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(response.message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
    return false;
  }
}

/// Опрос: причина отмены и что доработать.
Future<SubscriptionCancelSurveyResult?> showSubscriptionCancelSurveySheet(
  BuildContext context,
) {
  return showModalBottomSheet<SubscriptionCancelSurveyResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _SubscriptionCancelSurveySheet(),
  );
}

class _SubscriptionCancelSurveySheet extends StatefulWidget {
  const _SubscriptionCancelSurveySheet();

  @override
  State<_SubscriptionCancelSurveySheet> createState() =>
      _SubscriptionCancelSurveySheetState();
}

class _SubscriptionCancelSurveySheetState
    extends State<_SubscriptionCancelSurveySheet> {
  String? _selectedReasonId;
  final _otherReasonController = TextEditingController();
  final _improvementController = TextEditingController();

  @override
  void dispose() {
    _otherReasonController.dispose();
    _improvementController.dispose();
    super.dispose();
  }

  SubscriptionCancelReason? get _selectedReason {
    if (_selectedReasonId == null) return null;
    return SubscriptionCancelReason.options
        .firstWhere((r) => r.id == _selectedReasonId);
  }

  void _submit() {
    final reason = _selectedReason;
    if (reason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите причину отмены')),
      );
      return;
    }
    if (reason.id == 'other' &&
        _otherReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Уточните причину в поле «Другое»')),
      );
      return;
    }
    Navigator.of(context).pop(
      SubscriptionCancelSurveyResult(
        reason: reason,
        otherReasonDetail: reason.id == 'other'
            ? _otherReasonController.text.trim()
            : null,
        improvementFeedback: _improvementController.text.trim().isEmpty
            ? null
            : _improvementController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          final theme = Theme.of(context);
          return Material(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Отмена подписки',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      SurveySectionCard(
                        title: 'Почему отменяете подписку?',
                        subtitle: 'Выберите один вариант',
                        icon: Icons.help_outline,
                        child: Column(
                          children: [
                            ...SubscriptionCancelReason.options.map((reason) {
                              final selected = _selectedReasonId == reason.id;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Material(
                                  color: selected
                                      ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.35)
                                      : theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                  child: RadioListTile<String>(
                                    value: reason.id,
                                    groupValue: _selectedReasonId,
                                    onChanged: (value) {
                                      setState(() => _selectedReasonId = value);
                                    },
                                    title: Text(reason.label),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    dense: true,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              );
                            }),
                            if (_selectedReasonId == 'other') ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: _otherReasonController,
                                decoration: const InputDecoration(
                                  labelText: 'Уточните причину',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                maxLines: 2,
                                textInputAction: TextInputAction.next,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SurveySectionCard(
                        title: 'Что нам стоит доработать?',
                        subtitle: 'Необязательно — ваш отзыв поможет улучшить HAN Eat',
                        icon: Icons.edit_note_outlined,
                        child: TextField(
                          controller: _improvementController,
                          decoration: const InputDecoration(
                            hintText:
                                'Например: больше рецептов, удобнее план питания…',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          maxLines: 4,
                          textInputAction: TextInputAction.done,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: _submit,
                        child: const Text('Продолжить'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Не отменять'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
