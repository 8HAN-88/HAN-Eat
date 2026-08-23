import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/call_service.dart';
import '../../../widgets/highlighted_text.dart';

/// Fullscreen incoming ring UI (accept / reject + haptic pulse).
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.call,
    required this.timeout,
  });

  final CallSessionInfo call;
  final Duration timeout;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  Timer? _pulse;
  Timer? _timeout;
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    _pulse = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    });
    HapticFeedback.heavyImpact();
    _timeout = Timer(widget.timeout, () {
      if (_decided || !mounted) return;
      _decided = true;
      Navigator.of(context).pop<bool>(null);
    });
  }

  @override
  void dispose() {
    _pulse?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  void _decide(bool accept) {
    if (_decided) return;
    _decided = true;
    _pulse?.cancel();
    _timeout?.cancel();
    Navigator.of(context).pop<bool>(accept);
  }

  @override
  Widget build(BuildContext context) {
    final peerName = widget.call.peerName?.trim().isNotEmpty == true
        ? widget.call.peerName!.trim()
        : 'Входящий звонок';
    final isVideo = widget.call.isVideo;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Text(
              isVideo ? 'Входящий видеозвонок' : 'Входящий звонок',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
            const Spacer(),
            CircleAvatar(
              radius: 56,
              backgroundColor: Colors.white24,
              backgroundImage: widget.call.peerAvatarUrl != null &&
                      widget.call.peerAvatarUrl!.isNotEmpty
                  ? NetworkImage(widget.call.peerAvatarUrl!)
                  : null,
              child: widget.call.peerAvatarUrl == null ||
                      widget.call.peerAvatarUrl!.isEmpty
                  ? Text(
                      peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 40, color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(height: 20),
            HighlightedText(
              text: peerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundAction(
                    color: Colors.red,
                    icon: Icons.call_end,
                    label: 'Отклонить',
                    onTap: () => _decide(false),
                  ),
                  _RoundAction(
                    color: Colors.green,
                    icon: isVideo ? Icons.videocam : Icons.call,
                    label: 'Ответить',
                    onTap: () => _decide(true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
