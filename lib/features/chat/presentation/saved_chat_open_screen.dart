import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';

/// Deep link `#/saved-messages` → живой чат «Избранное».
class SavedChatOpenScreen extends StatefulWidget {
  const SavedChatOpenScreen({super.key});

  @override
  State<SavedChatOpenScreen> createState() => _SavedChatOpenScreenState();
}

class _SavedChatOpenScreenState extends State<SavedChatOpenScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    try {
      final conv = await ChatService.ensureSavedChat();
      if (!mounted) return;
      context.go('/chats/thread/${conv.id}', extra: conv);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
      context.go('/chats');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
