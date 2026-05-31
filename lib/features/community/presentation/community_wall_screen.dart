import 'package:flutter/material.dart';

/// Legacy Firestore wall — не используется в основном роутере.
@Deprecated('Community wall is legacy Firestore; use channel posts API')
class CommunityWallScreen extends StatelessWidget {
  const CommunityWallScreen({super.key, required this.communityId});

  final String communityId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сообщество (legacy)')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Стена сообщества Firestore больше не поддерживается. '
            'Откройте канал в разделе «Каналы».',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
