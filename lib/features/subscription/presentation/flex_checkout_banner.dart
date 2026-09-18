import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../subscription_copy.dart';

class FlexCheckoutBanner extends StatelessWidget {
  const FlexCheckoutBanner({
    super.key,
    required this.checkoutAvailable,
    required this.legalConsentRequired,
    this.message,
  });

  final bool checkoutAvailable;
  final bool legalConsentRequired;
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (checkoutAvailable && !legalConsentRequired) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final title = legalConsentRequired
        ? 'Сначала документы'
        : SubscriptionCopy.paymentsComingSoonTitle;
    final body = (message != null && message!.trim().isNotEmpty)
        ? message!
        : legalConsentRequired
            ? 'Примите условия, чтобы оформить подписку.'
            : SubscriptionCopy.paymentsComingSoonBody;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(body, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (legalConsentRequired) ...[
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () => context.push(LegalConsentRoute.path),
                child: const Text('Принять документы'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
