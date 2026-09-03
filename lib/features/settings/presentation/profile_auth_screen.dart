import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_router.dart';
import '../../../services/user_service.dart';
import '../../../services/auth_service.dart';
import '../../auth/sign_out_helper.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_avatar.dart';
import '../../../widgets/phone/profile_phone_tile.dart';
import '../../../widgets/account/profile_email_tile.dart';
import '../../../widgets/account/profile_password_tile.dart';

class ProfileAuthScreen extends ConsumerStatefulWidget {
  const ProfileAuthScreen({super.key});

  @override
  ConsumerState<ProfileAuthScreen> createState() => _ProfileAuthScreenState();
}

class _ProfileAuthScreenState extends ConsumerState<ProfileAuthScreen> {
  final _nameCtl = TextEditingController();
  final _bioCtl = TextEditingController();
  bool _loading = false;
  double _uploadProgress = 0.0;

  void _syncFieldsFromProfile() {
    final user = AuthService.instance.currentUser;
    final p = UserService.instance.profile.value;
    _nameCtl.text = p?.displayName ?? user?.name ?? '';
    _bioCtl.text = p?.user.bio ?? user?.bio ?? '';
  }

  @override
  void initState() {
    super.initState();
    if (UserService.isInitialized) {
      _syncFieldsFromProfile();
      UserService.instance.profile.addListener(_onProfileChanged);
    }
    AuthService.profileVersion.addListener(_onAuthProfileChanged);
    unawaited(AuthService.refreshMeFromApi());
  }

  void _onAuthProfileChanged() {
    if (mounted) setState(() {});
  }

  void _onProfileChanged() {
    if (UserService.isInitialized && mounted) {
      _syncFieldsFromProfile();
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (UserService.isInitialized) {
      UserService.instance.profile.removeListener(_onProfileChanged);
    }
    AuthService.profileVersion.removeListener(_onAuthProfileChanged);
    _nameCtl.dispose();
    _bioCtl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    if (!UserService.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Сервис пользователя не инициализирован')),
        );
      }
      return;
    }
    final picked = await UserService.instance.pickAvatarImage();
    if (picked == null) return;
    setState(() {
      _loading = true;
      _uploadProgress = 0.0;
    });
    try {
      await UserService.instance.updateAvatarFromXFile(picked, onProgress: (p) {
        setState(() => _uploadProgress = p);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Аватар обновлён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось загрузить аватар'),
            ),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => unawaited(_pickAndUploadAvatar()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!UserService.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Сервис пользователя не инициализирован')),
        );
      }
      return;
    }
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите отображаемое имя')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await UserService.instance.updateProfileFields(
        name: name,
        bio: _bioCtl.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль обновлён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось обновить'),
            ),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => unawaited(_saveProfile()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signOut() async {
    await confirmAndSignOut(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isInitialized || !UserService.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    final user = AuthService.instance.currentUser;
    final profile = UserService.instance.profile.value;

    if (user == null) {
      return const _RedirectToLoginGate();
    }

    // Если профиль еще не загружен, создаем его автоматически с uid
    final currentProfile = profile ?? UserProfile(uid: user.uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Аватар (с возможностью изменения)
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  backgroundImage: resolvedAvatarImage(
                    currentProfile.avatarUrl,
                    decodeWidth: 224,
                  ),
                  child: resolvedAvatarImage(currentProfile.avatarUrl) == null
                      ? Text(
                          _initials(currentProfile.displayName),
                          style: TextStyle(
                            fontSize: 32,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        )
                      : null,
                ),
                if (_loading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 120,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LinearProgressIndicator(value: _uploadProgress),
                            const SizedBox(height: 8),
                            Text(
                              '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.photo_camera),
              label: const Text('Изменить аватар'),
              onPressed: _loading ? null : _pickAndUploadAvatar,
            ),
          ),
          const SizedBox(height: 24),
          ProfileEmailTile(
            email: user.email,
            emailVerified: user.emailVerified,
            onChanged: () async {
              await AuthService.refreshMeFromApi();
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 12),
          ProfilePhoneTile(
            phone: user.phone,
            phoneLinked: user.phoneLinked,
            onChanged: () async {
              await AuthService.refreshMeFromApi();
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 12),
          const ProfilePasswordTile(),
          const SizedBox(height: 16),
          // Имя
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Отображаемое имя',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtl,
                    decoration: const InputDecoration(
                      hintText: 'Введите ваше имя',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'О себе',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bioCtl,
                    decoration: const InputDecoration(
                      hintText: 'Краткое описание профиля',
                    ),
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _saveProfile,
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Сохранить'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Аналитика
          Card(
            child: ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Аналитика'),
              subtitle: const Text('Статистика постов и активности'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppAnalyticsRoute.path),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Инструменты автора'),
              subtitle: const Text('Продвижение, расписание, аналитика'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(CreatorToolsRoute.path),
            ),
          ),
          const SizedBox(height: 16),
          // Выход
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Выйти из аккаунта'),
            onPressed: _signOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length > 1 ? 1 : 0][0]).toUpperCase();
  }
}

class _RedirectToLoginGate extends StatefulWidget {
  const _RedirectToLoginGate();

  @override
  State<_RedirectToLoginGate> createState() => _RedirectToLoginGateState();
}

class _RedirectToLoginGateState extends State<_RedirectToLoginGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(LoginRoute.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
