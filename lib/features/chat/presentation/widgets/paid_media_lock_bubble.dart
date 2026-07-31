import 'dart:ui';

import 'package:flutter/material.dart';

/// Telegram-like locked paid media preview with blurred star overlay.
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 240,
        height: 180,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.surfaceContainerHighest,
                    scheme.secondaryContainer.withValues(alpha: 0.75),
                    scheme.surfaceContainerHigh,
                  ],
                ),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: ColoredBox(
                color: scheme.scrim.withValues(alpha: 0.28),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.surface.withValues(alpha: 0.92),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.star_rounded,
                      color: scheme.secondary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Платное медиа',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$priceStars ★',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: FilledButton(
                onPressed: loading ? null : onUnlock,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.surface.withValues(alpha: 0.95),
                  foregroundColor: scheme.onSurface,
                ),
                child: loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.secondary,
                        ),
                      )
                    : Text('Открыть · $priceStars ★'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
