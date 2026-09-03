import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../services/close_friends_service.dart';
import '../../../utils/api_error_parser.dart';

/// Manage Telegram-like close friends list for story privacy.
class CloseFriendsScreen extends StatefulWidget {
  const CloseFriendsScreen({super.key});

  @override
  State<CloseFriendsScreen> createState() => _CloseFriendsScreenState();
}

class _CloseFriendsScreenState extends State<CloseFriendsScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<CloseFriendUser> _friends = const [];
  List<ChatUserSearchItem> _searchResults = const [];
  String? _searchError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await CloseFriendsService.list();
      if (!mounted) return;
      setState(() {
        _friends = items;
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

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_runSearch(value));
    });
  }

  Future<void> _runSearch(String value) async {
    final q = value.trim();
    if (q.length < 2) {
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _searchError = null;
        });
      }
      return;
    }
    try {
      final results = await ChatService.searchUsers(q);
      if (!mounted) return;
      final friendIds = _friends.map((f) => f.id).toSet();
      setState(() {
        _searchResults =
            results.where((u) => !friendIds.contains(u.id)).toList();
        _searchError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _searchError = userVisibleError(e);
        });
      }
    }
  }

  Future<void> _add(ChatUserSearchItem user) async {
    setState(() => _busy = true);
    try {
      await CloseFriendsService.add(user.id);
      _searchController.clear();
      setState(() => _searchResults = const []);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.name ?? user.username ?? 'Пользователь'} добавлен(а)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_add(user)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(CloseFriendUser user) async {
    setState(() => _busy = true);
    try {
      await CloseFriendsService.remove(user.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_remove(user)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Близкие друзья')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Эти люди увидят сторис с аудиторией «Близкие друзья».',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Найти пользователя',
                        hintText: 'Имя или @username',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                    if (_searchError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _searchError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => unawaited(
                                    _runSearch(_searchController.text),
                                  ),
                          child: const Text('Повторить поиск'),
                        ),
                      ),
                    ],
                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ..._searchResults.map(
                        (u) => ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(u.name ?? u.username ?? 'Пользователь'),
                          subtitle: Text(
                            (u.username ?? '').isNotEmpty
                                ? '@${u.username}'
                                : 'ID ${u.id}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Добавить',
                            onPressed: _busy ? null : () => _add(u),
                            icon: const Icon(Icons.person_add_alt_1),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Список (${_friends.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (_friends.isEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Пока пусто'),
                        subtitle: const Text(
                          'Добавьте людей через поиск выше',
                        ),
                        trailing: TextButton(
                          onPressed: _busy
                              ? null
                              : () => _searchFocus.requestFocus(),
                          child: const Text('Найти'),
                        ),
                      )
                    else
                      ..._friends.map(
                        (f) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.favorite_outline),
                          ),
                          title: Text(f.name),
                          subtitle: Text(f.subtitle),
                          trailing: IconButton(
                            tooltip: 'Убрать',
                            onPressed: _busy ? null : () => _remove(f),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
