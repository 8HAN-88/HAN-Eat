import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_router.dart';
import '../features/subscription/presentation/widgets/subscription_visuals.dart';
import '../features/subscription/subscription_copy.dart';
import '../models/ai_meal_plan.dart';
import 'product_analytics.dart';

/// Мягкий paywall при cooldown бесплатного AI meal plan (без таймеров).
class MealPlanGate {
  static Future<bool> ensureCanGenerate(
    BuildContext context,
    MealPlanLimits limits,
  ) async {
    if (limits.canGenerateMealPlan) return true;
    await showCooldownPaywall(context);
    return false;
  }

  static Future<void> showCooldownPaywall(BuildContext context) async {
    unawaited(
      ProductAnalytics.logEvent(
        eventType: 'meal_plan_cooldown_paywall_view',
        metadata: const {'tier': 'free'},
      ),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottom),
          child: AiScanExhaustedPaywall(
            isPlus: false,
            headerIcon: Icons.restaurant_menu_rounded,
            title: SubscriptionCopy.mealPlanCooldownTitle,
            subtitle: SubscriptionCopy.mealPlanCooldownSubtitle,
            benefits: SubscriptionCopy.mealPlanAiBenefits,
            primaryCtaLabel: SubscriptionCopy.mealPlanCooldownCta,
            onChoosePlan: () {
              ProductAnalytics.logEvent(
                eventType: 'meal_plan_cooldown_paywall_cta',
              );
              Navigator.of(ctx).pop();
              context.push(SubscriptionRoute.pathWithProduct('ai'));
            },
            onClose: () {
              ProductAnalytics.logEvent(
                eventType: 'meal_plan_cooldown_paywall_dismiss',
              );
              Navigator.of(ctx).pop();
            },
          ),
        );
      },
    );
  }

}
