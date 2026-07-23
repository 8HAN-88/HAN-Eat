import 'package:flutter/material.dart';

/// Кнопка микрофона: удержание для записи (как в Telegram).
/// Свайп влево — отмена, вверх — lock (запись без удержания).
class ChatVoiceMicButton extends StatefulWidget {
  const ChatVoiceMicButton({
    super.key,
    required this.enabled,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.onHoldDrag,
    this.recording = false,
    this.locked = false,
  });

  final bool enabled;
  final bool recording;
  final bool locked;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  /// (dx, dy) from press origin. dy < 0 = up.
  final void Function(double dx, double dy)? onHoldDrag;

  @override
  State<ChatVoiceMicButton> createState() => _ChatVoiceMicButtonState();
}

class _ChatVoiceMicButtonState extends State<ChatVoiceMicButton> {
  bool _pressing = false;

  @override
  void didUpdateWidget(covariant ChatVoiceMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Once locked, finger-up should not look "pressed".
    if (widget.locked && _pressing) {
      _pressing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.recording || _pressing || widget.locked;

    return GestureDetector(
      onLongPressStart: widget.enabled && !widget.locked
          ? (_) {
              setState(() => _pressing = true);
              widget.onHoldStart();
            }
          : null,
      onLongPressEnd: widget.enabled && !widget.locked
          ? (_) {
              if (mounted) setState(() => _pressing = false);
              // Parent ignores end if already locked during drag.
              widget.onHoldEnd();
            }
          : null,
      onLongPressCancel: widget.enabled && !widget.locked
          ? () {
              if (mounted) setState(() => _pressing = false);
              if (widget.recording) widget.onHoldEnd();
            }
          : null,
      onLongPressMoveUpdate: widget.enabled && !widget.locked
          ? (d) => widget.onHoldDrag?.call(
                d.offsetFromOrigin.dx,
                d.offsetFromOrigin.dy,
              )
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: widget.locked ? 48 : 44,
        height: widget.locked ? 48 : 44,
        decoration: BoxDecoration(
          color: widget.locked
              ? scheme.primary
              : (active ? scheme.error : scheme.primary),
          shape: BoxShape.circle,
          boxShadow: widget.locked
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Icon(
          widget.locked
              ? Icons.lock_rounded
              : (active ? Icons.mic_rounded : Icons.mic_none_rounded),
          color: scheme.onPrimary,
        ),
      ),
    );
  }
}
