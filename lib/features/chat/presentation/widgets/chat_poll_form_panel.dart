import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/color_schemes.dart';
import '../../../../models/chat_poll.dart';
import 'create_chat_poll_sheet.dart';

class ChatPollFormPanel extends StatefulWidget {
  const ChatPollFormPanel({
    super.key,
    required this.scrollController,
    this.onValidityChanged,
  });

  static const maxOptions = 12;

  final ScrollController scrollController;
  final ValueChanged<bool>? onValidityChanged;

  @override
  ChatPollFormPanelState createState() => ChatPollFormPanelState();
}

class ChatPollFormPanelState extends State<ChatPollFormPanel> {
  final _questionController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _optionControllers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  ChatPollSettings _settings = const ChatPollSettings(
    showVoterNames: true,
    multipleChoice: true,
    allowAddOptions: true,
    allowChangeVote: true,
  );

  bool get canSend {
    final q = _questionController.text.trim();
    if (q.isEmpty) return false;
    return _optionControllers
            .map((c) => c.text.trim())
            .where((s) => s.isNotEmpty)
            .length >=
        2;
  }

  int get _remainingOptions =>
      ChatPollFormPanel.maxOptions - _optionControllers.length;

  @override
  void dispose() {
    _questionController.dispose();
    _descriptionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _notifyValidity() {
    widget.onValidityChanged?.call(canSend);
  }

  void _addOption() {
    if (_optionControllers.length >= ChatPollFormPanel.maxOptions) return;
    setState(() => _optionControllers.add(TextEditingController()));
    _notifyValidity();
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers.removeAt(index).dispose();
    });
    _notifyValidity();
  }

  ChatPollDraft? buildDraft() {
    if (!canSend) return null;
    return ChatPollDraft(
      question: _questionController.text.trim(),
      description: _descriptionController.text.trim(),
      options: _optionControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      settings: _settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final groupBg =
        isDark ? const Color(0xFF2C2C2E) : theme.colorScheme.surfaceContainerHighest;
    final labelColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75);

    return ListView(
      controller: widget.scrollController,
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
              onChanged: (_) {
                setState(_notifyValidity);
              },
            ),
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.25),
            ),
            _PollTextField(
              controller: _descriptionController,
              hint: 'Описание (необязательно)',
              trailing: Icon(
                Icons.attach_file,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onChanged: (_) {
                setState(_notifyValidity);
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionLabel('ВАРИАНТЫ ОТВЕТА', color: labelColor),
        const SizedBox(height: 8),
        _GroupedCard(
          color: groupBg,
          children: [
            for (var i = 0; i < _optionControllers.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.25),
                ),
              _PollTextField(
                controller: _optionControllers[i],
                hint: 'Ответ',
                trailing: _optionControllers.length > 2
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _removeOption(i),
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
                onChanged: (_) {
                setState(_notifyValidity);
              },
              ),
            ],
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.25),
            ),
            InkWell(
              onTap: _remainingOptions > 0 ? _addOption : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.add,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Добавить ответ',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.primary,
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
              style: theme.textTheme.bodySmall?.copyWith(color: labelColor),
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
              subtitle: 'Рядом с ответами отображаются имена голосовавших',
              value: _settings.showVoterNames,
              onChanged: (v) => setState(
                () => _settings = _settings.copyWith(showVoterNames: v),
              ),
            ),
            _settingDivider(theme),
            _PollSettingTile(
              icon: Icons.fact_check_outlined,
              iconColor: const Color(0xFFFF9500),
              title: 'Несколько ответов',
              subtitle: 'Участники могут выбрать более одного варианта',
              value: _settings.multipleChoice,
              onChanged: (v) => setState(
                () => _settings = _settings.copyWith(multipleChoice: v),
              ),
            ),
            _settingDivider(theme),
            _PollSettingTile(
              icon: Icons.add_circle_outline,
              iconColor: const Color(0xFF64D2FF),
              title: 'Добавление вариантов',
              subtitle: 'Участники могут предлагать новые варианты',
              value: _settings.allowAddOptions,
              onChanged: (v) => setState(
                () => _settings = _settings.copyWith(allowAddOptions: v),
              ),
            ),
            _settingDivider(theme),
            _PollSettingTile(
              icon: Icons.change_circle_outlined,
              iconColor: const Color(0xFFBF5AF2),
              title: 'Изменение ответа',
              subtitle: 'Участники могут изменить выбранный ответ',
              value: _settings.allowChangeVote,
              onChanged: (v) => setState(
                () => _settings = _settings.copyWith(allowChangeVote: v),
              ),
            ),
          ],
        ),
      ],
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
              onChanged: (v) => onChanged?.call(v),
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              maxLength: hint.contains('вопрос') ? 300 : 120,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                  null,
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
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

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
        child: Icon(icon, size: 18, color: iconColor),
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
