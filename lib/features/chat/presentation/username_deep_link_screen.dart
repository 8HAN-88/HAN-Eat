import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';

/// Resolves `/u/:username` (or `@username` deep links) into a DM thread.
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
      setState(() => _error = 'Некорректный username');
      return;
    }
    try {
      final user = await ChatService.resolveUsername(handle);
      if (!mounted) return;
      if (user == null) {
        setState(() => _error = 'Пользователь @$handle не найден');
        return;
      }
      final chat = await ChatService.openDirectChat(user.id);
      if (!mounted) return;
      context.go(ChatThreadRoute.pathForId(chat.id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userVisibleError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final err = _error;
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username.replaceFirst('@', '')}')),
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
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(ChatsRoute.path);
                        }
                      },
                      child: const Text('Назад'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
