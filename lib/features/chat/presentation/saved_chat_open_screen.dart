import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

/// Deep link `#/saved-messages` → живой чат «Избранное».
class SavedChatOpenScreen extends StatefulWidget {
  const SavedChatOpenScreen({super.key});

  @override
  State<SavedChatOpenScreen> createState() => _SavedChatOpenScreenState();
}

class _SavedChatOpenScreenState extends State<SavedChatOpenScreen> {
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conv = await ChatService.ensureSavedChat();
      if (!mounted) return;
      context.go('/chats/thread/${conv.id}', extra: conv);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Избранное'),
        leading: BackButton(
          onPressed: () => context.go(ChatsRoute.path),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AppEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Не удалось открыть избранное',
              subtitle: userVisibleError(
                _error ?? 'Не удалось открыть избранное',
                fallback: 'Проверьте сеть',
              ),
              action: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () => unawaited(_open()),
                    child: const Text('Повторить'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go(ChatsRoute.path),
                    child: const Text('К чатам'),
                  ),
                ],
              ),
            ),
    );
  }
}
