import 'package:flutter/material.dart';

/// Экран видео-звонка (заглушка на первую итерацию)
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Верхняя панель
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    isGroupCall ? 'Групповой звонок' : contactName,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const Spacer(),
                ],
              ),
            ),

            const Spacer(),

            // Заглушка видео
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.videocam, size: 64, color: Colors.white54),
            ),

            const SizedBox(height: 16),
            Text(
              contactName,
              style: const TextStyle(color: Colors.white, fontSize: 24),
            ),
            const Text(
              'Соединение...',
              style: TextStyle(color: Colors.white70),
            ),

            const Spacer(),

            // Панель управления
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              color: Colors.black87,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: Icons.mic_off,
                    label: 'Микрофон',
                    onPressed: () {},
                  ),
                  _CallButton(
                    icon: Icons.videocam_off,
                    label: 'Камера',
                    onPressed: () {},
                  ),
                  _CallButton(
                    icon: Icons.call_end,
                    label: 'Завершить',
                    color: Colors.red,
                    onPressed: () => Navigator.of(context).pop(),
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

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: color ?? Colors.white, size: 28),
          onPressed: onPressed,
        ),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
