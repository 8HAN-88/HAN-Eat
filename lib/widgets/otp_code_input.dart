import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/auth/otp_code.dart';

/// Шесть клеток под цифры: автофокус, вставка, SMS Autofill.
class OtpCodeInput extends StatefulWidget {
  const OtpCodeInput({
    super.key,
    this.length = kOtpCodeLength,
    this.enabled = true,
    this.autofocus = true,
    this.error = false,
    this.controller,
    this.onChanged,
    this.onCompleted,
  });

  final int length;
  final bool enabled;
  final bool autofocus;
  final bool error;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<OtpCodeInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _ownsController = false;
  String _lastCompleted = '';

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(_onText);
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    _focusNode.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onText() {
    final digits = normalizeOtpInput(_controller.text).replaceAll(
      RegExp(r'\D'),
      '',
    );
    final clipped = digits.length > widget.length
        ? digits.substring(0, widget.length)
        : digits;
    if (clipped != _controller.text) {
      _controller.value = TextEditingValue(
        text: clipped,
        selection: TextSelection.collapsed(offset: clipped.length),
      );
      return;
    }
    widget.onChanged?.call(clipped);
    if (clipped.length == widget.length) {
      if (_lastCompleted != clipped) {
        _lastCompleted = clipped;
        HapticFeedback.lightImpact();
        widget.onCompleted?.call(clipped);
      }
    } else {
      _lastCompleted = '';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final raw = normalizeOtpInput(_controller.text);
    final focused = _focusNode.hasFocus && widget.enabled;
    final mid = (widget.length / 2).floor();

    return GestureDetector(
      onTap: widget.enabled ? () => _focusNode.requestFocus() : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i == mid) const SizedBox(width: 12),
                Expanded(
                  child: _OtpBox(
                    digit: i < raw.length ? raw[i] : '',
                    highlighted: focused &&
                        (i == raw.length ||
                            (raw.length == widget.length &&
                                i == widget.length - 1)),
                    error: widget.error,
                    enabled: widget.enabled,
                    scheme: scheme,
                    theme: theme,
                  ),
                ),
                if (i != widget.length - 1 && i != mid - 1)
                  const SizedBox(width: 8),
              ],
            ],
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: AutofillGroup(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  enableSuggestions: false,
                  autocorrect: false,
                  maxLength: widget.length,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.digit,
    required this.highlighted,
    required this.error,
    required this.enabled,
    required this.scheme,
    required this.theme,
  });

  final String digit;
  final bool highlighted;
  final bool error;
  final bool enabled;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final borderColor = error
        ? scheme.error
        : highlighted
            ? scheme.primary
            : scheme.outlineVariant;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: highlighted || error ? 2 : 1,
        ),
      ),
      child: Text(
        digit,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class OtpResendControl extends StatefulWidget {
  const OtpResendControl({
    super.key,
    required this.onResend,
    this.enabled = true,
    this.cooldown = kOtpResendCooldown,
    this.startCooldown = true,
    this.idleLabel = 'Отправить код ещё раз',
  });

  final Future<void> Function() onResend;
  final bool enabled;
  final Duration cooldown;
  final bool startCooldown;
  final String idleLabel;

  @override
  State<OtpResendControl> createState() => _OtpResendControlState();
}

class _OtpResendControlState extends State<OtpResendControl> {
  DateTime? _until;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.startCooldown) {
      _until = DateTime.now().add(widget.cooldown);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (_remaining == Duration.zero) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Duration get _remaining {
    if (_until == null) return Duration.zero;
    final left = _until!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _resend() async {
    if (_busy || _remaining > Duration.zero || !widget.enabled) return;
    setState(() => _busy = true);
    try {
      await widget.onResend();
      if (!mounted) return;
      setState(() {
        _until = DateTime.now().add(widget.cooldown);
        _busy = false;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = _remaining;
    final seconds = left.inSeconds;
    final waiting = seconds > 0;
    final label = waiting ? 'Новый код через $seconds с' : widget.idleLabel;
    return TextButton(
      onPressed: (!widget.enabled || _busy || waiting) ? null : _resend,
      child: Text(label),
    );
  }
}
