import 'package:flutter/material.dart';

import '../../../core/phone/phone_format.dart';
import '../../../core/phone/phone_hash.dart';
import '../../../services/auth_service.dart';
import '../../../utils/api_error_parser.dart';

/// Диалог привязки номера (общий для профиля и контактов).
Future<bool> showLinkPhoneDialog(BuildContext context) async {
  final phoneController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  try {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Номер телефона'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Укажите номер в международном формате. Друзья из телефонной книги '
                'смогут найти вас в HAN Eat.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Номер',
                  hintText: '+7 900 123 45 67',
                ),
                validator: (value) {
                  final raw = value?.trim() ?? '';
                  if (raw.isEmpty) return 'Введите номер';
                  if (normalizePhoneE164(raw) == null) {
                    return 'Некорректный номер';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (saved != true || !context.mounted) return false;

    await AuthService.linkPhone(phoneController.text.trim());
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Номер сохранён')),
    );
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
    return false;
  } finally {
    phoneController.dispose();
  }
}

enum _PhoneAction { change, remove }

Future<void> showPhoneManageSheet(
  BuildContext context, {
  required String phoneE164,
  required VoidCallback onChanged,
}) async {
  final action = await showModalBottomSheet<_PhoneAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              formatPhoneForDisplay(phoneE164),
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Изменить номер'),
            onTap: () => Navigator.pop(ctx, _PhoneAction.change),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(ctx).colorScheme.error,
            ),
            title: Text(
              'Удалить номер',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
            onTap: () => Navigator.pop(ctx, _PhoneAction.remove),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;

  if (action == _PhoneAction.change) {
    final ok = await showLinkPhoneDialog(context);
    if (ok) onChanged();
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Удалить номер?'),
      content: const Text(
        'Вас не смогут найти по телефонной книге. Номер можно добавить снова.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await AuthService.unlinkPhone();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Номер удалён')),
    );
    onChanged();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userVisibleError(e))),
    );
  }
}

/// Строка «Номер телефона» в профиле (как в Telegram).
class ProfilePhoneTile extends StatelessWidget {
  const ProfilePhoneTile({
    super.key,
    required this.phone,
    required this.phoneLinked,
    required this.onChanged,
  });

  final String? phone;
  final bool phoneLinked;
  final VoidCallback onChanged;

  Future<void> _onTap(BuildContext context) async {
    if (phoneLinked && phone != null && phone!.isNotEmpty) {
      await showPhoneManageSheet(
        context,
        phoneE164: phone!,
        onChanged: onChanged,
      );
      return;
    }
    final ok = await showLinkPhoneDialog(context);
    if (ok) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = phoneLinked && phone != null && phone!.isNotEmpty;
    final subtitle = hasPhone
        ? formatPhoneForDisplay(phone!)
        : 'Добавить номер телефона';

    return Card(
      child: ListTile(
        leading: const Icon(Icons.phone_outlined),
        title: const Text('Номер телефона'),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _onTap(context),
      ),
    );
  }
}
