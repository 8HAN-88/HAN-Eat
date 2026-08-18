import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../services/api_service.dart';
import '../../utils/api_error_parser.dart';

/// Opens flex subscription for gated actions.
Future<void> showCreatorUpsell(BuildContext context) async {
  await context.push(FlexSubscriptionRoute.path);
}

bool offerFlexIfRequired(BuildContext context, Object error) {
  String? message;
  if (error is HanPlusRequiredException) {
    message = error.toString();
  } else if (error is ApiClientException && error.code == 'HAN_FEATURE_REQUIRED') {
    message = error.message;
  }
  if (message == null) return false;
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: 'Подписка',
        onPressed: () {
          if (context.mounted) {
            context.push(FlexSubscriptionRoute.path);
          }
        },
      ),
    ),
  );
  return true;
}
