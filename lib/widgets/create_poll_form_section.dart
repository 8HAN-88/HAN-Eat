import 'package:flutter/material.dart';

/// Форма создания опроса (вопрос + варианты ответа).
class CreatePollFormSection extends StatelessWidget {
  const CreatePollFormSection({
    super.key,
    required this.questionController,
    required this.optionControllers,
    required this.onAddOption,
    required this.onRemoveOption,
  });

  final TextEditingController questionController;
  final List<TextEditingController> optionControllers;
  final VoidCallback onAddOption;
  final void Function(int index) onRemoveOption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Опрос',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: questionController,
          decoration: const InputDecoration(
            labelText: 'Вопрос',
            hintText: 'Например: Какой рецепт готовим на ужин?',
            border: OutlineInputBorder(),
          ),
          maxLength: 300,
        ),
        const SizedBox(height: 16),
        Text(
          'Варианты ответа (минимум 2)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ...optionControllers.asMap().entries.map((entry) {
          final i = entry.key;
          final ctrl = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      labelText: 'Вариант ${i + 1}',
                      border: const OutlineInputBorder(),
                    ),
                    maxLength: 120,
                  ),
                ),
                if (optionControllers.length > 2)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => onRemoveOption(i),
                    tooltip: 'Удалить вариант',
                  ),
              ],
            ),
          );
        }),
        if (optionControllers.length < 10)
          TextButton.icon(
            onPressed: onAddOption,
            icon: const Icon(Icons.add),
            label: const Text('Добавить вариант'),
          ),
      ],
    );
  }

  /// Собрать непустые варианты; null если валидация не прошла.
  static List<String>? collectOptions(List<TextEditingController> controllers) {
    final opts = controllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (opts.length < 2) return null;
    return opts;
  }
}
