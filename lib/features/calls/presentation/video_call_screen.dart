import 'package:flutter/material.dart';

/// Deprecated stub — use [CallScreen] via [CallCoordinator].
@Deprecated('Use CallCoordinator.openOutgoing(media: video)')
class VideoCallScreen extends StatelessWidget {
  const VideoCallScreen({
    super.key,
    required this.contactName,
    this.isGroupCall = false,
  });

  final String contactName;
  final bool isGroupCall;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(contactName)),
      body: const Center(
        child: Text('Используйте звонок из чата'),
      ),
    );
  }
}
