import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../services/api_service.dart';
import '../../services/subscription_status_cache.dart';
import '../../utils/api_error_parser.dart';

/// Opens flex subscription for gated actions.
Future<void> showCreatorUpsell(BuildContext context) async {
  await context.push(FlexSubscriptionRoute.path);
}

bool hasFlexFeature(String slug) =>
    SubscriptionStatusCache.peek()?.hasFeature(slug) == true;

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

bool offerPackStoreIfRequired(BuildContext context, Object error) {
  String? message;
  if (error is ApiClientException &&
      (error.code == 'pack_purchase_required' ||
          error.code == 'custom_emoji_denied')) {
    message = error.message;
  } else {
    final raw = error.toString();
    if (raw.contains('pack_purchase_required') ||
        raw.contains('custom_emoji_denied') ||
        raw.contains('купите пак')) {
      message = raw.contains('купите пак')
          ? raw
          : 'Этот эмодзи недоступен — купите пак';
    }
  }
  if (message == null) return false;
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: 'Магазин',
        onPressed: () {
          if (context.mounted) {
            context.push(PackStoreRoute.path);
          }
        },
      ),
    ),
  );
  return true;
}
