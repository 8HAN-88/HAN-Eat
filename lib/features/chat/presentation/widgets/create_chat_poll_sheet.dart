import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../models/chat_poll.dart';
import '../../../subscription/creator_upsell.dart';

/// Черновик опроса для отправки в чат.
class ChatPollDraft {
  ChatPollDraft({
    required this.question,
    required this.description,
    required this.options,
    required this.settings,
  });

  final String question;
  final String description;
  final List<String> options;
  final ChatPollSettings settings;
}

class CreateChatPollSheet extends StatefulWidget {
  const CreateChatPollSheet({super.key});

  static const maxOptions = 12;

  static Future<ChatPollDraft?> show(BuildContext context) {
    return showModalBottomSheet<ChatPollDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateChatPollSheet(),
    );
  }

  @override
  State<CreateChatPollSheet> createState() => _CreateChatPollSheetState();
}

class _CreateChatPollSheetState extends State<CreateChatPollSheet> {
  final _questionController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _optionControllers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  ChatPollSettings _settings = const ChatPollSettings();

  /// Controller index of the correct quiz answer (Telegram: single).
  int? _correctControllerIndex;

  @override
  void dispose() {
    _questionController.dispose();
    _descriptionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSend {
    final q = _questionController.text.trim();
    if (q.isEmpty) return false;
    final opts = _optionControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (opts.length < 2) return false;
    if (_settings.quizMode) {
      final correct = resolveQuizCorrectIndices(
        rawOptionTexts:
            _optionControllers.map((c) => c.text).toList(growable: false),
        correctControllerIndex: _correctControllerIndex,
      );
      if (correct.isEmpty) return false;
    }
    return true;
  }

  int get _remainingOptions =>
      CreateChatPollSheet.maxOptions - _optionControllers.length;

  void _addOption() {
    if (_optionControllers.length >= CreateChatPollSheet.maxOptions) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers.removeAt(index).dispose();
      if (_correctControllerIndex != null) {
        if (_correctControllerIndex == index) {
          _correctControllerIndex = null;
        } else if (_correctControllerIndex! > index) {
          _correctControllerIndex = _correctControllerIndex! - 1;
        }
      }
    });
  }

  bool _allowPollPlus({required bool enabling}) {
    if (!enabling || hasFlexFeature('poll_quiz')) return true;
    showCreatorUpsell(context);
    return false;
  }

  void _setQuizMode(bool enabled) {
    setState(() {
      if (enabled) {
        _settings = _settings.copyWith(
          quizMode: true,
          multipleChoice: false,
          allowAddOptions: false,
          allowChangeVote: false,
        );
      } else {
        _settings = _settings.copyWith(
          quizMode: false,
          correctOptionIndices: const [],
        );
        _correctControllerIndex = null;
      }
    });
  }

  bool _settingsNeedPollPlus() {
    return !_settings.showVoterNames ||
        _settings.quizMode ||
        _settings.multipleChoice ||
        _settings.allowAddOptions ||
        _settings.hideResultsUntilClosed ||
        _settings.timeLimitEnabled ||
        _settings.randomOrder;
  }

  void _send() {
    if (!_canSend) return;
    if (_settingsNeedPollPlus() && !hasFlexFeature('poll_quiz')) {
      showCreatorUpsell(context);
      return;
    }
    final raw = _optionControllers.map((c) => c.text).toList(growable: false);
    final options = raw.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final correct = _settings.quizMode
        ? resolveQuizCorrectIndices(
            rawOptionTexts: raw,
            correctControllerIndex: _correctControllerIndex,
          )
        : const <int>[];
    Navigator.pop(
      context,
      ChatPollDraft(
        question: _questionController.text.trim(),
        description: _descriptionController.text.trim(),
        options: options,
        settings: _settings.copyWith(correctOptionIndices: correct),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sheetBg =
        isDark ? const Color(0xFF1C1C1E) : theme.colorScheme.surface;
    final groupBg = isDark
        ? const Color(0xFF2C2C2E)
        : theme.colorScheme.surfaceContainerHighest;
    final labelColor =
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: DraggableScrollableSheet(
        initialChildSize: keyboardInset > 0 ? 0.96 : 0.92,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) {
          return Material(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _Header(
                  canSend: _canSend,
                  onClose: () => Navigator.pop(context),
                  onSend: _send,
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _SectionLabel('ВОПРОС', color: labelColor),
                      const SizedBox(height: 8),
                      _GroupedCard(
                        color: groupBg,
                        children: [
                          _PollTextField(
                            controller: _questionController,
                            hint: 'Текст вопроса',
                            onChanged: (_) => setState(() {}),
                          ),
                          Divider(
                            height: 1,
                            color: theme.dividerColor.withValues(alpha: 0.25),
                          ),
                          _PollTextField(
                            controller: _descriptionController,
                            hint: _settings.quizMode
                                ? 'Пояснение после ответа (необязательно)'
                                : 'Описание (необязательно)',
                            trailing: Icon(
                              Icons.attach_file,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel('ВАРИАНТЫ ОТВЕТА', color: labelColor),
                      const SizedBox(height: 8),
                      _GroupedCard(
                        color: groupBg,
                        children: [
                          for (var i = 0;
                              i < _optionControllers.length;
                              i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                color:
                                    theme.dividerColor.withValues(alpha: 0.25),
                              ),
                            _PollTextField(
                              controller: _optionControllers[i],
                              hint: _settings.quizMode
                                  ? 'Ответ ${i + 1}'
                                  : 'Ответ',
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_settings.quizMode)
                                    IconButton(
                                      tooltip: 'Правильный ответ',
                                      icon: Icon(
                                        _correctControllerIndex == i
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 22,
                                        color: _correctControllerIndex == i
                                            ? const Color(0xFF34C759)
                                            : theme.colorScheme
                                                .onSurfaceVariant,
                                      ),
                                      onPressed: () => setState(
                                        () => _correctControllerIndex = i,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  if (_optionControllers.length > 2)
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => _removeOption(i),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                          Divider(
                            height: 1,
                            color: theme.dividerColor.withValues(alpha: 0.25),
                          ),
                          InkWell(
                            onTap: _remainingOptions > 0 ? _addOption : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.add,
                                    color: theme.colorScheme.primary,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Добавить ответ',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_remainingOptions > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 4),
                          child: Text(
                            'Можно добавить ещё $_remainingOptions ${_optionsWord(_remainingOptions)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: labelColor,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      _SectionLabel('НАСТРОЙКИ', color: labelColor),
                      const SizedBox(height: 8),
                      _GroupedCard(
                        color: groupBg,
                        children: [
                          _PollSettingTile(
                            icon: Icons.visibility_outlined,
                            iconColor: const Color(0xFF5AC8FA),
                            title: 'Имена участников',
                            subtitle:
                                'Рядом с ответами отображаются имена голосовавших',
                            value: _settings.showVoterNames,
                            locked: !hasFlexFeature('poll_quiz'),
                            onChanged: (v) {
                              if (!_allowPollPlus(enabling: !v)) return;
                              setState(
                                () => _settings = _settings.copyWith(
                                  showVoterNames: v,
                                ),
                              );
                            },
                          ),
                          _settingDivider(theme),
                          _PollSettingTile(
                            icon: Icons.check_circle_outline,
                            iconColor: const Color(0xFF34C759),
                            title: 'Викторина',
                            subtitle: _settings.quizMode
                                ? (_correctControllerIndex == null
                                    ? 'Отметьте правильный вариант галочкой у ответа'
                                    : 'Правильный ответ выбран')
                                : 'Один правильный ответ; участники видят результат после голосования',
                            value: _settings.quizMode,
                            locked: !hasFlexFeature('poll_quiz'),
                            onChanged: (v) {
                              if (!_allowPollPlus(enabling: v)) return;
                              _setQuizMode(v);
                            },
                          ),
                          if (!_settings.quizMode) ...[
                            _settingDivider(theme),
                            _PollSettingTile(
                              icon: Icons.fact_check_outlined,
                              iconColor: const Color(0xFFFF9500),
                              title: 'Несколько ответов',
                              subtitle:
                                  'Участники могут выбрать более одного варианта',
                              value: _settings.multipleChoice,
                              locked: !hasFlexFeature('poll_quiz'),
                              onChanged: (v) {
                                if (!_allowPollPlus(enabling: v)) return;
                                setState(
                                  () => _settings = _settings.copyWith(
                                    multipleChoice: v,
                                  ),
                                );
                              },
                            ),
                            _settingDivider(theme),
                            _PollSettingTile(
                              icon: Icons.add_circle_outline,
                              iconColor: const Color(0xFF64D2FF),
                              title: 'Добавление вариантов',
                              subtitle:
                                  'Участники могут предлагать новые варианты',
                              value: _settings.allowAddOptions,
                              locked: !hasFlexFeature('poll_quiz'),
                              onChanged: (v) {
                                if (!_allowPollPlus(enabling: v)) return;
                                setState(
                                  () => _settings = _settings.copyWith(
                                    allowAddOptions: v,
                                  ),
                                );
                              },
                            ),
                            _settingDivider(theme),
                            _PollSettingTile(
                              icon: Icons.change_circle_outlined,
                              iconColor: const Color(0xFFBF5AF2),
                              title: 'Изменение ответа',
                              subtitle:
                                  'Участники могут изменить выбранный ответ',
                              value: _settings.allowChangeVote,
                              onChanged: (v) => setState(
                                () => _settings = _settings.copyWith(
                                  allowChangeVote: v,
                                ),
                              ),
                            ),
                          ],
                          _settingDivider(theme),
                          _PollSettingTile(
                            icon: Icons.shuffle,
                            iconColor: const Color(0xFFFF2D55),
                            title: 'Случайный порядок',
                            subtitle:
                                'Ответы отображаются у всех участников в случайном порядке',
                            value: _settings.randomOrder,
                            locked: !hasFlexFeature('poll_quiz'),
                            onChanged: (v) {
                              if (!_allowPollPlus(enabling: v)) return;
                              setState(
                                () => _settings = _settings.copyWith(
                                  randomOrder: v,
                                ),
                              );
                            },
                          ),
                          _settingDivider(theme),
                          _PollSettingTile(
                            icon: Icons.timer_outlined,
                            iconColor: const Color(0xFFFF3B30),
                            title: 'Ограничение срока',
                            subtitle:
                                'Опрос автоматически завершится в заданное время',
                            value: _settings.timeLimitEnabled,
                            locked: !hasFlexFeature('poll_quiz'),
                            onChanged: (v) {
                              if (!_allowPollPlus(enabling: v)) return;
                              setState(
                                () => _settings = _settings.copyWith(
                                  timeLimitEnabled: v,
                                ),
                              );
                            },
                          ),
                          if (_settings.timeLimitEnabled) ...[
                            _settingDivider(theme),
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              title: const Text('Срок проведения'),
                              trailing: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _settings.durationHours,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 1,
                                      child: Text('1 час'),
                                    ),
                                    DropdownMenuItem(
                                      value: 8,
                                      child: Text('8 часов'),
                                    ),
                                    DropdownMenuItem(
                                      value: 24,
                                      child: Text('1 день'),
                                    ),
                                    DropdownMenuItem(
                                      value: 168,
                                      child: Text('7 дней'),
                                    ),
                                  ],
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(
                                      () => _settings = _settings.copyWith(
                                        durationHours: v,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                          _settingDivider(theme),
                          _PollSettingTile(
                            icon: Icons.visibility_off_outlined,
                            iconColor: const Color(0xFF8E8E93),
                            title: 'Скрыть результаты',
                            subtitle:
                                'Если включено, результаты будут скрыты до завершения опроса',
                            value: _settings.hideResultsUntilClosed,
                            locked: !hasFlexFeature('poll_quiz'),
                            onChanged: (v) {
                              if (!_allowPollPlus(enabling: v)) return;
                              setState(
                                () => _settings = _settings.copyWith(
                                  hideResultsUntilClosed: v,
                                ),
                              );
                            },
                          ),
                        ],
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

  Widget _settingDivider(ThemeData theme) {
    return Divider(
      height: 1,
      indent: 56,
      color: theme.dividerColor.withValues(alpha: 0.25),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.canSend,
    required this.onClose,
    required this.onSend,
  });

  final bool canSend;
  final VoidCallback onClose;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text(
              'Новый опрос',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: canSend ? onSend : null,
            style: FilledButton.styleFrom(
              backgroundColor: canSend
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: canSend
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.color, required this.children});

  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _PollTextField extends StatelessWidget {
  const _PollTextField({
    required this.controller,
    required this.hint,
    this.trailing,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _PollSettingTile extends StatelessWidget {
  const _PollSettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.locked = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(locked ? Icons.lock_outline : icon, size: 18, color: iconColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      trailing: CupertinoSwitch(
        value: value,
        activeTrackColor: const Color(0xFF34C759),
        onChanged: onChanged,
      ),
    );
  }
}

String _optionsWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'вариантов ответа';
  if (mod10 == 1) return 'вариант ответа';
  if (mod10 >= 2 && mod10 <= 4) return 'варианта ответа';
  return 'вариантов ответа';
}
