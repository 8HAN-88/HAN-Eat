import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/layout/floating_bottom_padding.dart';
import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../services/paid_features_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_avatar.dart';

/// Telegram-like allowlist: who can DM you without paying Stars.
class PaidMessageExceptionsScreen extends StatefulWidget {
  const PaidMessageExceptionsScreen({super.key});

  @override
  State<PaidMessageExceptionsScreen> createState() =>
      _PaidMessageExceptionsScreenState();
}

class _PaidMessageExceptionsScreenState
    extends State<PaidMessageExceptionsScreen> {
  bool _loading = true;
  String? _error;
  List<PaidMessageExceptionUser> _items = const [];

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
      final items = await PaidFeaturesService.listMessageExceptions();
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

  Future<void> _remove(PaidMessageExceptionUser user) async {
    try {
      await PaidFeaturesService.removeMessageException(user.id);
      if (!mounted) return;
      setState(() {
        _items = _items.where((u) => u.id != user.id).toList(growable: false);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _addUser() async {
    final picked = await showModalBottomSheet<ChatUserSearchItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _UserSearchSheet(),
    );
    if (picked == null || !mounted) return;
    if (_items.any((u) => u.id == picked.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Уже в списке исключений')),
      );
      return;
    }
    try {
      final added = await PaidFeaturesService.addMessageException(picked.id);
      if (!mounted) return;
      setState(() => _items = [added, ..._items]);
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
      appBar: AppBar(
        title: const Text('Кто пишет бесплатно'),
        actions: [
          IconButton(
            tooltip: 'Добавить',
            onPressed: _addUser,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addUser,
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
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
          const SizedBox(height: 12),
          Center(
            child: TextButton(onPressed: _load, child: const Text('Повторить')),
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
        children: const [
          Icon(Icons.star_border_rounded, size: 48),
          SizedBox(height: 12),
          Text(
            'Никого нет в исключениях.\nДобавьте друзей — они смогут писать вам без Stars.',
            textAlign: TextAlign.center,
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
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final user = _items[index];
        final username = user.username?.trim();
        return ListTile(
          leading: AppUserAvatar(
            imageUrl: user.avatarUrl,
            displayName: user.displayName,
            radius: 22,
          ),
          title: Text(user.displayName),
          subtitle: username != null && username.isNotEmpty
              ? Text(username.startsWith('@') ? username : '@$username')
              : const Text('Пишет бесплатно'),
          trailing: IconButton(
            tooltip: 'Удалить',
            onPressed: () => unawaited(_remove(user)),
            icon: const Icon(Icons.close_rounded),
          ),
        );
      },
    );
  }
}

class _UserSearchSheet extends StatefulWidget {
  const _UserSearchSheet();

  @override
  State<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<_UserSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<ChatUserSearchItem> _results = const [];
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_search(value));
    });
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatService.searchUsers(q);
      if (!mounted) return;
      setState(() {
        _results = items;
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Поиск по имени или @username',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _onQueryChanged,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!))
                        : _results.isEmpty
                            ? const Center(
                                child: Text('Начните вводить имя'),
                              )
                            : ListView.builder(
                                itemCount: _results.length,
                                itemBuilder: (context, index) {
                                  final item = _results[index];
                                  final name = item.name?.trim().isNotEmpty ==
                                          true
                                      ? item.name!.trim()
                                      : (item.username ?? 'Пользователь');
                                  return ListTile(
                                    leading: AppUserAvatar(
                                      imageUrl: item.avatarUrl,
                                      displayName: name,
                                      radius: 20,
                                    ),
                                    title: Text(name),
                                    subtitle: item.username == null
                                        ? null
                                        : Text(
                                            item.username!.startsWith('@')
                                                ? item.username!
                                                : '@${item.username}',
                                          ),
                                    onTap: () => Navigator.pop(context, item),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
