import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/channel_service.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';
import '../application/chat_open_direct.dart';

/// Resolves `/u/:username` (or `@username` deep links) into a DM.
/// Public channel slugs fall through to the channel wall.
class UsernameDeepLinkScreen extends StatefulWidget {
  const UsernameDeepLinkScreen({super.key, required this.username});

  final String username;

  @override
  State<UsernameDeepLinkScreen> createState() => _UsernameDeepLinkScreenState();
}

class _UsernameDeepLinkScreenState extends State<UsernameDeepLinkScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final handle = widget.username.trim().replaceFirst(RegExp(r'^@'), '');
    if (handle.length < 2) {
      setState(() => _error = 'Некорректное имя');
      return;
    }
    try {
      final user = await ChatService.resolveUsername(handle);
      if (!mounted) return;
      if (user == null) {
        final channel = await _channelBySlug(handle);
        if (!mounted) return;
        if (channel != null) {
          context.go(ChannelDetailRoute.pathFor(channel.id));
          return;
        }
        setState(() => _error = 'Не нашли @$handle');
        return;
      }
      final chat = await ChatOpenDirect.openNow(user.id, peer: user);
      if (!mounted) return;
      context.go(ChatThreadRoute.pathFor(chat), extra: chat);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userVisibleError(e));
    }
  }

  Future<Channel?> _channelBySlug(String handle) async {
    final needle = handle.toLowerCase();
    try {
      final found = await ChannelService.listChannels(
        search: handle,
        limit: 12,
      );
      for (final channel in found.items) {
        if (channel.slug.toLowerCase() == needle) return channel;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final err = _error;
    return Scaffold(
      appBar: AppBar(
        title: Text('@${widget.username.replaceFirst('@', '')}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Назад',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(ChatsRoute.path);
            }
          },
        ),
      ),
      body: Center(
        child: err == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(err, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _open();
                      },
                      child: const Text('Повторить'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(ChatsRoute.path);
                        }
                      },
                      child: const Text('К чатам'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
