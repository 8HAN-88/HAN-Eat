import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/app_brand_logo.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _loading = false;
  bool _sent = false;
  String? _sentToEmail;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _useAnotherEmail() {
    setState(() {
      _sent = false;
      _sentToEmail = null;
    });
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (!_sent) {
      if (!_formKey.currentState!.validate()) return;
    } else if (email.isEmpty || !email.contains('@')) {
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await AuthService.forgotPassword(email: email);
      if (mounted) {
        setState(() {
          _sent = true;
          _sentToEmail = email;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Забыли пароль?')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _sent ? _buildSentStep(theme) : _buildRequestStep(theme),
        ),
      ),
    );
  }

  Widget _buildRequestStep(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: AppBrandLogo(size: 64)),
          const SizedBox(height: 24),
          Text(
            'Восстановление доступа',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Укажите email — отправим письмо со ссылкой для нового пароля.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Введите email';
              if (!v.contains('@')) return 'Некорректный email';
              return null;
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Отправить письмо'),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => context.push(ResetPasswordRoute.path),
              child: const Text('Уже есть код из письма?'),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => context.go(LoginRoute.path),
              child: const Text('Вернуться ко входу'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentStep(ThemeData theme) {
    final email = _sentToEmail ?? _emailController.text.trim();
    final primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: AppBrandLogo(size: 56)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Письмо отправлено',
            style: theme.textTheme.labelLarge?.copyWith(
              color: primary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Проверьте почту',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Мы отправили инструкцию на',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.mark_email_read_outlined, color: primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    email,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _InstructionStep(
          number: 1,
          text: 'Откройте письмо «Сброс пароля — HAN Eat» (проверьте «Спам»).',
        ),
        const SizedBox(height: 10),
        _InstructionStep(
          number: 2,
          text: 'Нажмите оранжевую кнопку «Задать новый пароль».',
        ),
        const SizedBox(height: 10),
        _InstructionStep(
          number: 3,
          text: 'Приложение откроет экран ввода нового пароля.',
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Отправить письмо снова'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _useAnotherEmail,
          child: const Text('Указать другой email'),
        ),
        TextButton(
          onPressed: () => context.push(ResetPasswordRoute.path),
          child: const Text('Ввести код вручную'),
        ),
        TextButton(
          onPressed: () => context.go(LoginRoute.path),
          child: const Text('Вернуться ко входу'),
        ),
      ],
    );
  }
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: theme.textTheme.labelLarge?.copyWith(
              color: primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
        ),
      ],
    );
  }
}
