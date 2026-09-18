import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';

/// Открывает лестницу Flex на уровне 16 для авторских действий.
Future<void> showCreatorUpsell(BuildContext context) async {
  await context.push(FlexSubscriptionRoute.pathWithLevel(16));
}
