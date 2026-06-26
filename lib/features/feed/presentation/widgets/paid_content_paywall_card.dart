import 'package:flutter/material.dart';

class PaidContentPaywallCard extends StatelessWidget {
  const PaidContentPaywallCard({
    super.key,
    required this.priceStars,
    required this.mediaCount,
    required this.isLoading,
    required this.onPurchase,
  });

  final int priceStars;
  final int mediaCount;
  final bool isLoading;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.72),
              scheme.secondaryContainer.withValues(alpha: 0.52),
              scheme.surfaceContainerHighest.withValues(alpha: 0.78),
            ],
          ),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Эксклюзивный контент',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Text(
                  '$priceStars ★',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              mediaCount > 0
                  ? 'Внутри $mediaCount медиа. Откройте пост за звёзды и смотрите без ограничений.'
                  : 'Откройте пост за звёзды, чтобы увидеть полный контент.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _PaywallChip(icon: Icons.visibility_rounded, label: 'Preview'),
                _PaywallChip(icon: Icons.stars_rounded, label: 'Stars'),
                _PaywallChip(
                    icon: Icons.favorite_rounded, label: 'Поддержка автора'),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: isLoading ? null : onPurchase,
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stars_rounded),
              label: Text(
                isLoading ? 'Открываем...' : 'Купить за $priceStars ★',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaywallChip extends StatelessWidget {
  const _PaywallChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
