import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';

/// Opens Creator subscription for gated author actions (schedule, analytics, etc.).
Future<void> showCreatorUpsell(BuildContext context) async {
  await context.push(FlexSubscriptionRoute.path);
}
