import 'package:flutter/material.dart';

import '../services/custom_emoji_registry.dart';
import '../services/server_config.dart';

/// Renders a purchased custom emoji by numeric id.
class CustomEmojiView extends StatefulWidget {
  const CustomEmojiView({
    super.key,
    required this.id,
    this.size = 20,
  });

  final int id;
  final double size;

  @override
  State<CustomEmojiView> createState() => _CustomEmojiViewState();
}

class _CustomEmojiViewState extends State<CustomEmojiView> {
  String? _url;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _url = CustomEmojiRegistry.instance.urlFor(widget.id);
    if (_url == null) {
      _loading = true;
      _resolve();
    }
  }

  @override
  void didUpdateWidget(covariant CustomEmojiView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _url = CustomEmojiRegistry.instance.urlFor(widget.id);
      if (_url == null) {
        _loading = true;
        _resolve();
      } else {
        _loading = false;
      }
    }
  }

  Future<void> _resolve() async {
    await CustomEmojiRegistry.instance.resolveMissing([widget.id]);
    if (!mounted) return;
    setState(() {
      _url = CustomEmojiRegistry.instance.urlFor(widget.id);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final url = _url;
    if (url == null || url.isEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: _loading
            ? Padding(
                padding: EdgeInsets.all(size * 0.28),
                child: const CircularProgressIndicator(strokeWidth: 1.4),
              )
            : Icon(Icons.emoji_emotions_outlined, size: size * 0.9),
      );
    }
    return Image.network(
      ServerConfig.resolveMediaUrl(url),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.broken_image_outlined,
        size: size * 0.9,
      ),
    );
  }
}

/// Unicode emoji, `ce:id` reaction, or `[[e:id]]` token.
class ReactionEmojiView extends StatelessWidget {
  const ReactionEmojiView({
    super.key,
    required this.token,
    this.size = 18,
  });

  final String token;
  final double size;

  @override
  Widget build(BuildContext context) {
    final id = parseCustomEmojiTokenId(token);
    if (id != null) {
      return CustomEmojiView(id: id, size: size);
    }
    return Text(
      token,
      style: TextStyle(fontSize: size, height: 1),
    );
  }
}

class StatusEmojiView extends StatelessWidget {
  const StatusEmojiView({
    super.key,
    required this.status,
    this.size = 22,
  });

  final String? status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final raw = (status ?? '').trim();
    if (raw.isEmpty) return const SizedBox.shrink();
    return ReactionEmojiView(token: raw, size: size);
  }
}
