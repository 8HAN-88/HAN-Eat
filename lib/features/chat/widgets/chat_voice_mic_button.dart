import 'package:flutter/material.dart';

/// Кнопка микрофона: удержание для записи (как в Telegram).
class ChatVoiceMicButton extends StatefulWidget {
  const ChatVoiceMicButton({
    super.key,
    required this.enabled,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.onHoldDragDx,
    this.recording = false,
  });

  final bool enabled;
  final bool recording;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final ValueChanged<double>? onHoldDragDx;

  @override
  State<ChatVoiceMicButton> createState() => _ChatVoiceMicButtonState();
}

class _ChatVoiceMicButtonState extends State<ChatVoiceMicButton> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.recording || _pressing;

    return GestureDetector(
      onLongPressStart: widget.enabled
          ? (_) {
              setState(() => _pressing = true);
              widget.onHoldStart();
            }
          : null,
      onLongPressEnd: widget.enabled
          ? (_) {
              if (mounted) setState(() => _pressing = false);
              widget.onHoldEnd();
            }
          : null,
      onLongPressCancel: widget.enabled
          ? () {
              if (mounted) setState(() => _pressing = false);
              if (widget.recording) widget.onHoldEnd();
            }
          : null,
      onLongPressMoveUpdate: widget.enabled
          ? (d) => widget.onHoldDragDx?.call(d.offsetFromOrigin.dx)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? scheme.error : scheme.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          active ? Icons.mic_rounded : Icons.mic_none_rounded,
          color: scheme.onPrimary,
        ),
      ),
    );
  }
}
