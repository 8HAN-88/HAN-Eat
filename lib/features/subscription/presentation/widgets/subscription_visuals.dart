import 'package:flutter/material.dart';

import '../../../../core/theme/color_schemes.dart';
import '../../subscription_copy.dart';

/// Мягкий градиент бренда HAN Eat.
BoxDecoration subscriptionBrandGradientDecoration({
  BorderRadius? radius,
  double opacity = 1,
}) {
  return BoxDecoration(
    borderRadius: radius ?? BorderRadius.circular(20),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppColors.gradientStart.withValues(alpha: opacity),
        AppColors.gradientEnd.withValues(alpha: opacity * 0.85),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.22),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

/// Шапка экрана подписки.
class SubscriptionHero extends StatelessWidget {
  const SubscriptionHero({
    super.key,
    this.trialDays,
  });

  final int? trialDays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: subscriptionBrandGradientDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const Spacer(),
              if (trialDays != null && trialDays! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Пробный период $trialDays дн.',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            SubscriptionCopy.heroTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            SubscriptionCopy.heroSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка тарифа на экране подписки.
class SubscriptionTierCard extends StatelessWidget {
  const SubscriptionTierCard({
    super.key,
    required this.tierId,
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    required this.benefits,
    required this.isSelected,
    required this.isRecommended,
    required this.isOwned,
    required this.trialEligible,
    this.onTap,
  });

  final String tierId;
  final String title;
  final String subtitle;
  final String priceLabel;
  final List<String> benefits;
  final bool isSelected;
  final bool isRecommended;
  final bool isOwned;
  final bool trialEligible;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = SubscriptionCopy.tierIcon(tierId);

    final borderColor = isSelected
        ? AppColors.primary
        : isRecommended
            ? AppColors.primary.withValues(alpha: 0.45)
            : cs.outlineVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.55)
            : cs.surface,
        border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        boxShadow: [
          if (isSelected || isRecommended)
            BoxShadow(
              color: AppColors.primary.withValues(alpha: isSelected ? 0.18 : 0.08),
              blurRadius: isSelected ? 16 : 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSelected
                              ? [AppColors.gradientStart, AppColors.gradientEnd]
                              : [
                                  cs.surfaceContainerHighest,
                                  cs.surfaceContainerHigh,
                                ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        color: isSelected ? Colors.white : cs.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (isRecommended)
                                _Badge(
                                  label: 'Лучшее предложение',
                                  filled: true,
                                ),
                              if (isOwned)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(
                                    Icons.verified_rounded,
                                    color: cs.primary,
                                    size: 22,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: cs.primary, size: 22),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  priceLabel,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isSelected ? AppColors.primaryDark : null,
                      ),
                ),
                if (trialEligible && !isOwned) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Доступен пробный период',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ...benefits.take(4).map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: isSelected ? AppColors.primary : cs.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                b,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.filled = false});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? AppColors.primary : const Color(0xFFFFE8E0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? Colors.white : AppColors.primaryDark,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Paywall при исчерпании бесплатных AI-сканов.
class AiScanExhaustedPaywall extends StatelessWidget {
  const AiScanExhaustedPaywall({
    super.key,
    required this.onChoosePlan,
    required this.onClose,
    this.isPlus = false,
    this.title,
    this.subtitle,
    this.benefits,
    this.primaryCtaLabel,
    this.headerIcon = Icons.document_scanner_rounded,
  });

  final VoidCallback onChoosePlan;
  final VoidCallback onClose;
  final bool isPlus;
  final String? title;
  final String? subtitle;
  final List<SubscriptionBenefitItem>? benefits;
  final String? primaryCtaLabel;
  final IconData headerIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: subscriptionBrandGradientDecoration(
            radius: BorderRadius.circular(28),
          ),
          child: Icon(
            headerIcon,
            color: Colors.white,
            size: 42,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          title ??
              (isPlus
                  ? SubscriptionCopy.aiScanPlusExhaustedTitle
                  : SubscriptionCopy.aiScanExhaustedTitle),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          subtitle ??
              (isPlus
                  ? SubscriptionCopy.aiScanPlusExhaustedSubtitle
                  : SubscriptionCopy.aiScanExhaustedSubtitle),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        if (!isPlus) ...[
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                for (var i = 0;
                    i < (benefits ?? SubscriptionCopy.aiScanBenefits).length;
                    i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _BenefitRow(
                    icon: (benefits ?? SubscriptionCopy.aiScanBenefits)[i].icon,
                    text: (benefits ?? SubscriptionCopy.aiScanBenefits)[i].text,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ] else
          const SizedBox(height: 28),
        if (!isPlus)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: subscriptionBrandGradientDecoration(
                radius: BorderRadius.circular(14),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onChoosePlan,
                  borderRadius: BorderRadius.circular(14),
                  child: Center(
                    child: Text(
                      primaryCtaLabel ?? SubscriptionCopy.paywallCta,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (!isPlus) const SizedBox(height: 8),
        TextButton(
          onPressed: onClose,
          child: Text(SubscriptionCopy.paywallLater),
        ),
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, height: 1.3),
          ),
        ),
      ],
    );
  }
}
