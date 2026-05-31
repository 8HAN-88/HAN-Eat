import 'package:flutter/material.dart';

import 'presentation/community_screen.dart';

/// Legacy entry — делегирует на [CommunityScreen] (Postgres API).
@Deprecated('Use CommunityScreen from presentation/community_screen.dart')
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) => const CommunityScreen();
}
