import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';

class ChatInviteJoinScreen extends StatefulWidget {
  const ChatInviteJoinScreen({
    super.key,
    required this.token,
  });

  final String token;

  @override
  State<ChatInviteJoinScreen> createState() => _ChatInviteJoinScreenState();
}

class _ChatInviteJoinScreenState extends State<ChatInviteJoinScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    if (AuthService.instance.currentUser == null) {
      if (mounted) context.go('/login');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ChatService.joinGroupByInviteToken(widget.token);
      if (!mounted) return;
      if (result.status == 'requested') {
        setState(() {
          _loading = false;
          _error =
              'Заявка отправлена. Дождитесь одобрения администратора группы.';
        });
        return;
      }
      final conv = result.conversation;
      if (conv == null) {
        setState(() {
          _loading = false;
          _error = 'Не удалось открыть группу';
        });
        return;
      }
      context.go('/chats/thread/${conv.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Приглашение в группу')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 14),
                    Text('Вступаем в группу...'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link_off_outlined, size: 42),
                    const SizedBox(height: 10),
                    Text(_error ?? 'Не удалось обработать приглашение'),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _join,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
