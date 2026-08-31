import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/auth_service.dart';
import '../../../services/user_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_avatar.dart';
import '../../../widgets/app_empty_state.dart';

enum FollowListType { followers, following }

class FollowListScreen extends StatefulWidget {
  const FollowListScreen({
    super.key,
    required this.userId,
    required this.type,
  });

  final int userId;
  final FollowListType type;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  static const _pageSize = 50;

  final _items = <UserFollowItem>[];
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _total = 0;

  String get _title =>
      widget.type == FollowListType.followers ? 'Подписчики' : 'Подписки';

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  Future<void> _load({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final response = widget.type == FollowListType.followers
          ? await UserService.getFollowers(
              widget.userId,
              limit: _pageSize,
              offset: refresh ? 0 : _items.length,
            )
          : await UserService.getFollowing(
              widget.userId,
              limit: _pageSize,
              offset: refresh ? 0 : _items.length,
            );
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _items
            ..clear()
            ..addAll(response.items);
        } else {
          _items.addAll(response.items);
        }
        _total = response.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _toggleFollow(int index) async {
    final currentUser = AuthService.instance.currentUser;
    final item = _items[index];
    if (currentUser == null || currentUser.id == item.user.id) return;
    final next = !item.isFollowing;
    setState(() {
      _items[index] = UserFollowItem(user: item.user, isFollowing: next);
    });
    try {
      if (next) {
        await UserService.follow(item.user.id);
      } else {
        await UserService.unfollow(item.user.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items[index] = item;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось выполнить действие'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : error != null && _items.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      AppEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Не удалось загрузить',
                        subtitle:
                            userVisibleError(error, fallback: 'Проверьте сеть'),
                        action: FilledButton(
                          onPressed: () => _load(refresh: true),
                          child: const Text('Повторить'),
                        ),
                      ),
                    ],
                  )
                : _items.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 120),
                          AppEmptyState(
                            icon: widget.type == FollowListType.followers
                                ? Icons.people_outline
                                : Icons.person_add_alt_1_outlined,
                            title: widget.type == FollowListType.followers
                                ? 'Подписчиков пока нет'
                                : 'Подписок пока нет',
                            action: widget.type == FollowListType.following
                                ? FilledButton.icon(
                                    onPressed: () =>
                                        context.push(SearchRoute.path),
                                    icon: const Icon(Icons.search),
                                    label: const Text('Найти людей'),
                                  )
                                : null,
                          ),
                        ],
                      )
                    : ListView.separated(
                        itemCount: _items.length + 1,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == _items.length) {
                            if (_items.length >= _total) {
                              return const SizedBox(height: 24);
                            }
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : OutlinedButton(
                                        onPressed: () => _load(refresh: false),
                                        child: const Text('Загрузить ещё'),
                                      ),
                              ),
                            );
                          }
                          final item = _items[index];
                          final user = item.user;
                          final currentUser = AuthService.instance.currentUser;
                          final isSelf = currentUser?.id == user.id;
                          final name = user.name.isNotEmpty
                              ? user.name
                              : (user.username ?? user.email);
                          return ListTile(
                            onTap: () =>
                                context.push(ProfileRoute.withUserId(user.id)),
                            leading: CircleAvatar(
                              backgroundImage: resolvedAvatarImage(
                                user.avatarUrl,
                                decodeWidth: 96,
                              ),
                              child: resolvedAvatarImage(user.avatarUrl) == null
                                  ? Text(name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?')
                                  : null,
                            ),
                            title: Text(name),
                            subtitle: user.username != null
                                ? Text('@${user.username}')
                                : null,
                            trailing: isSelf
                                ? null
                                : TextButton(
                                    onPressed: () => _toggleFollow(index),
                                    child: Text(
                                      item.isFollowing
                                          ? 'Отписаться'
                                          : 'Подписаться',
                                    ),
                                  ),
                          );
                        },
                      ),
      ),
    );
  }
}
