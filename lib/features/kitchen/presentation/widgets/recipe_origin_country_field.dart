import 'package:flutter/material.dart';
import 'package:han_eat/features/kitchen/domain/cuisine_countries.dart';

/// Выбор страны происхождения блюда при публикации рецепта.
class RecipeOriginCountryField extends StatelessWidget {
  const RecipeOriginCountryField({
    super.key,
    required this.selectedCode,
    required this.onChanged,
    this.enabled = true,
  });

  final String? selectedCode;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) return;
    final query = ValueNotifier<String>('');
    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Страна блюда',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Необязательно — помогает другим найти кухню рецепта',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Поиск страны…',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => query.value = v.trim().toLowerCase(),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.public_off_outlined),
                    title: const Text('Не указано'),
                    onTap: () => Navigator.pop(ctx, null),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: query,
                      builder: (context, q, _) {
                        final items = kRecipeOriginCountries.where((c) {
                          if (q.isEmpty) return true;
                          return c.nameRu.toLowerCase().contains(q) ||
                              c.nameEn.toLowerCase().contains(q) ||
                              c.code.toLowerCase().contains(q);
                        }).toList();
                        return ListView.builder(
                          controller: scrollController,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final country = items[index];
                            final isSelected =
                                selectedCode?.toUpperCase() == country.code;
                            return ListTile(
                              leading: Text(
                                country.flag,
                                style: const TextStyle(fontSize: 22),
                              ),
                              title: Text(country.nameRu),
                              subtitle: Text(country.code),
                              trailing: isSelected
                                  ? Icon(
                                      Icons.check_circle,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    )
                                  : null,
                              onTap: () => Navigator.pop(ctx, country.code),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (selected != selectedCode) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final country = findRecipeOriginCountry(selectedCode);
    final label = country?.displayLabel ?? 'Страна блюда (необязательно)';

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Страна блюда',
        border: OutlineInputBorder(),
      ),
      child: InkWell(
        onTap: enabled ? () => _openPicker(context) : null,
        child: Row(
          children: [
            Icon(
              Icons.flag_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: country != null
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (enabled)
              Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
