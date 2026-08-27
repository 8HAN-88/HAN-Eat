import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../services/close_friends_service.dart';
import '../../../services/custom_emoji_registry.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/highlighted_text.dart';

/// Manage Telegram-like close friends list for story privacy.
class CloseFriendsScreen extends StatefulWidget {
  const CloseFriendsScreen({super.key});

  @override
  State<CloseFriendsScreen> createState() => _CloseFriendsScreenState();
}

class _CloseFriendsScreenState extends State<CloseFriendsScreen> {
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<CloseFriendUser> _friends = const [];
  List<ChatUserSearchItem> _searchResults = const [];
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
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = value.trim();
      if (q.length < 2) {
        if (mounted) setState(() => _searchResults = const []);
        return;
      }
      try {
        final results = await ChatService.searchUsers(q);
        if (!mounted) return;
        final friendIds = _friends.map((f) => f.id).toSet();
        setState(() {
          _searchResults =
              results.where((u) => !friendIds.contains(u.id)).toList();
        });
      } catch (_) {
        if (mounted) setState(() => _searchResults = const []);
      }
    });
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
          content: Text(
            '${previewTextWithCustomEmoji(user.name ?? user.username ?? 'Пользователь')} добавлен(а)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
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
        SnackBar(content: Text(userVisibleError(e))),
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
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Найти пользователя',
                        hintText: 'Имя или @username',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ..._searchResults.map(
                        (u) => ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: HighlightedText(
                            text: u.name ?? u.username ?? 'Пользователь',
                            style: Theme.of(context).textTheme.bodyLarge ??
                                const TextStyle(fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Пока пусто'),
                        subtitle: Text('Добавьте людей через поиск выше'),
                      )
                    else
                      ..._friends.map(
                        (f) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.favorite_outline),
                          ),
                          title: HighlightedText(
                            text: f.name,
                            style: Theme.of(context).textTheme.bodyLarge ??
                                const TextStyle(fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
