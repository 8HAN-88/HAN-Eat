import 'package:flutter/material.dart';
import '../../services/user_service.dart';

class PublicProfilePage extends StatefulWidget {
  final String uid;
  const PublicProfilePage({required this.uid, Key? key}) : super(key: key);

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
      setState(() {
        _isFollowing = following;
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Action failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: Text(profile?.displayName ?? 'Profile')),
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
                          ? Text((profile.displayName ?? '?')[0].toUpperCase())
                          : null),
                  const SizedBox(height: 12),
                  Text(profile.displayName ?? 'No name',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _toggleFollow,
                    child: Text(_isFollowing ? 'Unfollow' : 'Follow'),
                  ),
                ],
              ),
            ),
    );
  }
}
