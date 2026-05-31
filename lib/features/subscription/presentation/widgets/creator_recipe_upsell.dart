import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_router.dart';
import '../../subscription_copy.dart';
import 'subscription_visuals.dart';

/// Bottom sheet: подписка Creator для публикации рецептов в канале.
Future<void> showCreatorRecipeUpsellSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottom),
        child: AiScanExhaustedPaywall(
          headerIcon: Icons.restaurant_menu_outlined,
          title: SubscriptionCopy.creatorRecipeUpsellTitle,
          subtitle: SubscriptionCopy.creatorRecipeUpsellSubtitle,
          benefits: SubscriptionCopy.creatorRecipeBenefits,
          primaryCtaLabel: SubscriptionCopy.creatorRecipeUpsellCta,
          onChoosePlan: () {
            Navigator.of(ctx).pop();
            context.push(SubscriptionRoute.pathWithProduct('creator'));
          },
          onClose: () => Navigator.of(ctx).pop(),
        ),
      );
    },
  );
}
