import 'package:flutter/material.dart';
import '../../utils/api_error_parser.dart';
import '../../services/user_service.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_gradient_background.dart';
import '../../widgets/telegram_ui.dart';

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
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final p = await UserService.instance.loadPublicProfile(widget.uid);
      final following = await UserService.instance.isFollowing(widget.uid);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _isFollowing = following;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
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
        SnackBar(
            content: Text(userVisibleError(e,
                fallback: 'Не удалось выполнить действие'))),
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
    final loadError = _loadError;
    Widget body;
    if (loadError != null) {
      body = AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Не удалось загрузить профиль',
        subtitle: userVisibleError(loadError, fallback: 'Проверьте сеть'),
        action: FilledButton(
          onPressed: _load,
          child: const Text('Повторить'),
        ),
      );
    } else if (profile == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Center(
            child: AppUserAvatar(
              imageUrl: profile.avatarUrl,
              displayName: profile.displayName,
              radius: 50,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            profile.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 18),
          TelegramGroupedSurface(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                TelegramActionRow(
                  icon: Icons.person_add_alt_1_rounded,
                  title: _isFollowing ? 'Вы подписаны' : 'Подписаться',
                  subtitle: _isFollowing
                      ? 'Нажмите, чтобы отписаться'
                      : 'Следите за новыми публикациями',
                  trailing: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isFollowing
                              ? Icons.check_circle_rounded
                              : Icons.chevron_right_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  onTap: _loading ? null : _toggleFollow,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(profile?.displayName ?? 'Профиль'),
        ),
        body: body,
      ),
    );
  }
}
