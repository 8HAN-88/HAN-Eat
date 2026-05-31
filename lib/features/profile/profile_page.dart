import 'package:flutter/material.dart';
import '../../utils/api_error_parser.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_router.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import '../auth/sign_out_helper.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameCtl = TextEditingController();
  bool _loading = false;
  double _uploadProgress = 0.0; // 0.0..1.0

  @override
  void initState() {
    super.initState();
    final p = UserService.instance.profile.value;
    _nameCtl.text = p?.displayName ?? '';
    UserService.instance.profile.addListener(_onProfileChanged);
  }

  void _onProfileChanged() {
    final p = UserService.instance.profile.value;
    _nameCtl.text = p?.displayName ?? '';
    setState(() {});
  }

  @override
  void dispose() {
    UserService.instance.profile.removeListener(_onProfileChanged);
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аватар обновлён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить аватар'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  Future<void> _saveName() async {
    final name = _nameCtl.text.trim();
    setState(() => _loading = true);
    try {
      await UserService.instance.updateDisplayName(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось сохранить'))),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = UserService.instance.profile.value;
    final currentUser = AuthService.instance.currentUser;

    // Если профиль null, но пользователь авторизован - показываем базовый профиль
    if (profile == null && currentUser != null) {
      // Пытаемся загрузить профиль
      UserService.instance.ensureProfileLoaded();
      // Показываем базовый профиль с данными из Auth
      return Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage: currentUser.avatarUrl != null
                    ? NetworkImage(currentUser.avatarUrl!)
                    : null,
                child: currentUser.avatarUrl == null
                    ? Text(_initials(currentUser.name))
                    : null,
              ),
              const SizedBox(height: 16),
              Text(currentUser.name),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtl,
                decoration:
                    const InputDecoration(labelText: 'Отображаемое имя'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: _saveName,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Сохранить')),
            ],
          ),
        ),
      );
    }

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Загрузка профиля...'),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onTap: _pickAndUploadAvatar,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundImage: profile.avatarUrl != null
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child: profile.avatarUrl == null
                        ? Text(_initials(profile.displayName))
                        : null,
                  ),
                ),
                if (_loading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26,
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
                                style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.photo_camera),
              label: const Text('Сменить аватар'),
              onPressed: _pickAndUploadAvatar,
            ),
            const SizedBox(height: 16),
            TextField(
                controller: _nameCtl,
                decoration:
                    const InputDecoration(labelText: 'Отображаемое имя')),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _saveName,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Сохранить')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => confirmAndSignOut(context),
              child: const Text('Выйти'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.backup),
              label: const Text('Резервная копия'),
              onPressed: () => context.push(BackupRoute.path),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.notifications),
              label: const Text('Уведомления'),
              onPressed: () => context.push(NotificationsRoute.path),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
