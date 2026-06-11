import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/legal_urls.dart';

/// Чекбокс согласия с политикой конфиденциальности и пользовательским соглашением.
class LegalConsentCheckbox extends StatelessWidget {
  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.consentText,
    this.privacyUrl,
    this.termsUrl,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;
  final String? consentText;
  final String? privacyUrl;
  final String? termsUrl;

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть ссылку')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final privacy = privacyUrl ?? LegalUrls.privacyPolicy;
    final terms = termsUrl ?? LegalUrls.termsOfService;
    final baseStyle = theme.textTheme.bodySmall?.copyWith(height: 1.35);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: RichText(
              text: TextSpan(
                style: baseStyle,
                children: [
                  if (consentText != null && consentText!.isNotEmpty)
                    TextSpan(text: '$consentText ')
                  else
                    const TextSpan(
                      text:
                          'Я принимаю ',
                    ),
                  TextSpan(
                    text: 'Политику конфиденциальности',
                    style: baseStyle?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _open(context, privacy),
                  ),
                  const TextSpan(text: ' и '),
                  TextSpan(
                    text: 'Пользовательское соглашение',
                    style: baseStyle?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _open(context, terms),
                  ),
                  const TextSpan(
                    text:
                        ', даю согласие на обработку персональных данных (152-ФЗ).',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
