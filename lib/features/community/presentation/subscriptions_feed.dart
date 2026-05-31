import 'package:flutter/material.dart';

import '../../feed/presentation/subscriptions_feed_screen.dart';

/// Legacy alias — лента подписок через Postgres API.
@Deprecated('Use SubscriptionsFeedScreen from features/feed')
class SubscriptionsFeed extends StatelessWidget {
  const SubscriptionsFeed({super.key});

  @override
  Widget build(BuildContext context) {
    return const SubscriptionsFeedScreen();
  }
}
