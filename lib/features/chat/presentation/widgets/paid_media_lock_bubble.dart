import 'package:flutter/material.dart';

class PaidMediaLockBubble extends StatelessWidget {
  const PaidMediaLockBubble({
    super.key,
    required this.priceStars,
    required this.loading,
    required this.onUnlock,
  });

  final int priceStars;
  final bool loading;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.secondaryContainer.withValues(alpha: 0.85),
            scheme.surfaceContainerHighest.withValues(alpha: 0.9),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_rounded, color: scheme.secondary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Платное медиа',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Откройте за $priceStars ★, как в Telegram Stars',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: loading ? null : onUnlock,
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Открыть · $priceStars ★'),
            ),
          ),
        ],
      ),
    );
  }
}
