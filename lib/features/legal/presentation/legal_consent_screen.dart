import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/auth_service.dart';
import '../../../services/legal_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/legal_consent_checkbox.dart';

/// Экран повторного согласия (новая версия документов или старые аккаунты).
class LegalConsentScreen extends StatefulWidget {
  const LegalConsentScreen({super.key});

  static const path = '/legal-consent';

  @override
  State<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends State<LegalConsentScreen> {
  bool _accepted = false;
  bool _loading = false;
  bool _submitting = false;
  LegalStatus? _status;
  String? _loadWarning;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadWarning = null;
    });
    try {
      final status = await LegalService.fetchStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = LegalService.fallbackStatus();
          _loadWarning = userVisibleError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Подтвердите согласие, чтобы продолжить'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await LegalService.acceptConsent();
      if (mounted) {
        context.go(FeedRoute.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userVisibleError(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    await AuthService.logout();
    if (mounted) context.go(LoginRoute.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Согласие на обработку данных'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.privacy_tip_outlined,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Обновили условия',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Чтобы продолжить пользоваться HAN Eat, ознакомьтесь '
                      'с документами и подтвердите согласие. Это требование '
                      'законодательства о персональных данных (152-ФЗ).',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_loadWarning != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _loadWarning!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    if (_status != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Версия документов: ${_status!.version}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                    const SizedBox(height: 24),
                    LegalConsentCheckbox(
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v ?? false),
                      consentText: _status?.consentText,
                      privacyUrl: _status?.privacyUrl,
                      termsUrl: _status?.termsUrl,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _submitting || !_accepted ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Принять и продолжить'),
                    ),
                    TextButton(
                      onPressed: _submitting ? null : _signOut,
                      child: const Text('Выйти из аккаунта'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
