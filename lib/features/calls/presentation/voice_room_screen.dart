import 'package:flutter/material.dart';

/// Deprecated stub — 1:1 voice calls use [CallScreen] via [CallCoordinator].
@Deprecated('Use CallCoordinator.openOutgoing(media: voice)')
class VoiceRoomScreen extends StatelessWidget {
  const VoiceRoomScreen({
    super.key,
    required this.roomName,
    this.roomId,
    this.isCreator = false,
  });

  final String roomName;
  final String? roomId;
  final bool isCreator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(roomName)),
      body: const Center(
        child: Text('Используйте аудиозвонок из чата'),
      ),
    );
  }
}
