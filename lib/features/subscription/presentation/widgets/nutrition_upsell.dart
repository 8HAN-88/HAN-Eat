import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_router.dart';
import '../../subscription_copy.dart';
import 'subscription_visuals.dart';

/// Bottom sheet: оформить подписку для калорий и БЖУ.
Future<void> showNutritionUpsellSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottom),
        child: AiScanExhaustedPaywall(
          headerIcon: Icons.local_fire_department_rounded,
          title: SubscriptionCopy.nutritionUpsellTitle,
          subtitle: SubscriptionCopy.nutritionUpsellSubtitle,
          benefits: SubscriptionCopy.nutritionBenefits,
          primaryCtaLabel: SubscriptionCopy.nutritionUpsellCta,
          onChoosePlan: () {
            Navigator.of(ctx).pop();
            context.push(SubscriptionRoute.pathWithProduct('ai'));
          },
          onClose: () => Navigator.of(ctx).pop(),
        ),
      );
    },
  );
}
