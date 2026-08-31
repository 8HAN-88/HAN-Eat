import 'package:flutter/material.dart';

import '../../../core/layout/floating_bottom_padding.dart';
import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_avatar.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  bool _loading = true;
  String? _error;
  List<ChatUserBrief> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatService.listBlockedUsers();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e);
      });
    }
  }

  Future<void> _unblock(ChatUserBrief user) async {
    try {
      await ChatService.unblockUser(user.id);
      if (!mounted) return;
      setState(() {
        _items = _items.where((u) => u.id != user.id).toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.displayName} разблокирован')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Чёрный список')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: const Text('Повторить'),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24,
          48,
          24,
          24 + floatingBottomPadding(context),
        ),
        children: [
          const Icon(Icons.block_outlined, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Нет заблокированных пользователей',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Назад'),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        16 + floatingBottomPadding(context),
      ),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = _items[index];
        final username = (user.username ?? '').trim();
        return ListTile(
          leading: AppUserAvatar(
            imageUrl: user.avatarUrl,
            displayName: user.displayName,
            radius: 22,
          ),
          title: Text(user.displayName),
          subtitle: username.isEmpty ? null : Text('@$username'),
          trailing: TextButton(
            onPressed: () => _unblock(user),
            child: const Text('Разблокировать'),
          ),
        );
      },
    );
  }
}
