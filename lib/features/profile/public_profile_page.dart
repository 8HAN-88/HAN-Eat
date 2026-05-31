import 'package:flutter/material.dart';
import '../../utils/api_error_parser.dart';
import '../../services/user_service.dart';

class PublicProfilePage extends StatefulWidget {
  final String uid;
  const PublicProfilePage({required this.uid, super.key});

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  bool _loading = false;
  bool _isFollowing = false;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await UserService.instance.loadPublicProfile(widget.uid);
    final following = await UserService.instance.isFollowing(widget.uid);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _isFollowing = following;
    });
  }

  Future<void> _toggleFollow() async {
    setState(() => _loading = true);
    try {
      if (_isFollowing) {
        await UserService.unfollowUser(widget.uid);
      } else {
        await UserService.followUser(widget.uid);
      }
      final following = await UserService.instance.isFollowing(widget.uid);
      if (!mounted) return;
      setState(() {
        _isFollowing = following;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось выполнить действие'))),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: Text(profile?.displayName ?? 'Профиль')),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CircleAvatar(
                      radius: 48,
                      backgroundImage: profile.avatarUrl != null
                          ? NetworkImage(profile.avatarUrl!)
                          : null,
                      child: profile.avatarUrl == null
                          ? Text(_initialForName(profile.displayName))
                          : null),
                  const SizedBox(height: 12),
                  Text(profile.displayName,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _toggleFollow,
                    child: Text(_isFollowing ? 'Отписаться' : 'Подписаться'),
                  ),
                ],
              ),
            ),
    );
  }

  String _initialForName(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t[0].toUpperCase();
  }
}
