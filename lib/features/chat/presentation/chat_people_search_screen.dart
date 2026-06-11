import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../services/server_config.dart';
import '../../../utils/api_error_parser.dart';

class ChatPeopleSearchScreen extends StatefulWidget {
  const ChatPeopleSearchScreen({super.key});

  @override
  State<ChatPeopleSearchScreen> createState() => _ChatPeopleSearchScreenState();
}

class _ChatPeopleSearchScreenState extends State<ChatPeopleSearchScreen> {
  final _query = TextEditingController();
  List<ChatUserSearchItem> _results = [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  int _searchSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    final seq = ++_searchSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatService.searchUsers(q);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = userVisibleError(e);
        _loading = false;
      });
    }
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _openChat(ChatUserSearchItem user) async {
    try {
      final conv = await ChatService.openDirectChat(user.id);
      if (!mounted) return;
      context.pushReplacement(
        ChatThreadRoute.pathFor(conv),
        extra: conv,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _toggleContact(ChatUserSearchItem user) async {
    try {
      if (user.isContact) {
        await ChatService.removeContact(user.id);
      } else {
        await ChatService.addContact(user.id);
      }
      await _search();
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
      appBar: AppBar(title: const Text('Найти людей')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Имя или @username',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _query.clear();
                    setState(() => _results = []);
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onSubmitted: (_) => _search(),
              onChanged: (_) {
                if (_query.text.trim().length < 2) {
                  _debounce?.cancel();
                  setState(() {
                    _results = [];
                    _error = null;
                    _loading = false;
                  });
                  return;
                }
                _scheduleSearch();
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final user = _results[index];
                return ListTile(
                  leading: _Avatar(user: user.brief),
                  title: Text(user.brief.displayName),
                  subtitle: user.username != null
                      ? Text('@${user.username}')
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: user.isContact ? 'Удалить из контактов' : 'В контакты',
                        icon: Icon(
                          user.isContact
                              ? Icons.person_remove_outlined
                              : Icons.person_add_outlined,
                        ),
                        onPressed: () => _toggleContact(user),
                      ),
                      IconButton(
                        tooltip: 'Написать',
                        icon: const Icon(Icons.chat_bubble_outline),
                        onPressed: () => _openChat(user),
                      ),
                    ],
                  ),
                  onTap: () => _openChat(user),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _avatarLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final ChatUserBrief user;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl;
    final resolved =
        url != null && url.isNotEmpty ? ServerConfig.resolveMediaUrl(url) : null;
    return CircleAvatar(
      radius: 24,
      backgroundImage:
          resolved != null ? CachedNetworkImageProvider(resolved) : null,
      child: resolved == null
          ? Text(
              _avatarLetter(user.displayName),
              style: const TextStyle(fontWeight: FontWeight.w600),
            )
          : null,
    );
  }
}
