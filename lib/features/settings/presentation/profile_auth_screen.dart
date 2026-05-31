import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_router.dart';
import '../../../core/config/google_auth_config.dart';
import '../../../services/user_service.dart';
import '../../../services/auth_service.dart';
import '../../auth/sign_out_helper.dart';
import '../../../utils/api_error_parser.dart';
import '../../../services/push_notification_service.dart';
import '../../../widgets/ai_scan_credits_tile.dart';

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
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить аватар'))),
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
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось обновить'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signOut() async {
    await confirmAndSignOut(
      context,
      navigateToLogin: false,
      onSignedOut: () {
        if (mounted) setState(() {});
      },
    );
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

    // Если пользователь не авторизован, показываем форму входа/регистрации
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Вход в аккаунт')),
        body: _LoginForm(),
      );
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
                  backgroundImage: currentProfile.avatarUrl != null
                      ? NetworkImage(currentProfile.avatarUrl!)
                      : null,
                  child: currentProfile.avatarUrl == null
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
          // Email
          Card(
            child: ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Эл. почта'),
              subtitle: Text(user.email),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: AiScanCreditsTile(),
          ),
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
                      border: OutlineInputBorder(),
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
                      border: OutlineInputBorder(),
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
              onTap: () {
                context.pushNamed('analytics');
              },
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Инструменты автора'),
              subtitle: const Text('Продвижение, расписание, аналитика'),
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

class _LoginForm extends StatefulWidget {
  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!AuthService.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Сервис авторизации не инициализирован')),
        );
      }
      return;
    }
    final email = _emailCtl.text.trim();
    final password = _passCtl.text.trim();
    if (email.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите email и пароль')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.signInWithEmail(email, password);
      // Профиль уже обновлен в AuthService.signInWithEmail, но убедимся
      if (UserService.isInitialized) {
        await UserService.instance.ensureProfileLoaded();
      }
      if (mounted) {
        context.go(FeedRoute.path);
      }
    } on AuthException catch (e) {
      if (mounted) {
        if (e.isEmailNotVerified) {
          context.push(VerifyEmailRoute.withEmail(_emailCtl.text.trim()));
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось войти'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _register() async {
    if (!AuthService.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Сервис авторизации не инициализирован')),
        );
      }
      return;
    }
    final email = _emailCtl.text.trim();
    final password = _passCtl.text.trim();
    if (email.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите email и пароль')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.createUserWithEmail(email, password);
      unawaited(
        PushNotificationService.syncTokenAfterAuth().catchError(
          (Object e) => debugPrint('FCM after register: $e'),
        ),
      );
      // Профиль уже обновлен в AuthService.createUserWithEmail, но убедимся
      if (UserService.isInitialized) {
        await UserService.instance.ensureProfileLoaded();
      }
      if (mounted) {
        context.go(FeedRoute.path);
      }
    } catch (e) {
      if (mounted) {
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось зарегистрироваться'),
              style: TextStyle(color: scheme.onError),
            ),
            backgroundColor: scheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _google() async {
    if (!AuthService.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Сервис авторизации не инициализирован')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.signInWithGoogle();
      unawaited(
        PushNotificationService.syncTokenAfterAuth().catchError(
          (Object e) => debugPrint('FCM after Google: $e'),
        ),
      );
      // Профиль уже обновлен в AuthService.signInWithGoogle, но убедимся
      if (UserService.isInitialized) {
        await UserService.instance.ensureProfileLoaded();
      }
      if (mounted) {
        context.go(FeedRoute.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось войти через Google'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Войдите в аккаунт',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _emailCtl,
            decoration: const InputDecoration(
              labelText: 'Эл. почта',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passCtl,
            decoration: const InputDecoration(
              labelText: 'Пароль',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () => context.push(
                        ForgotPasswordRoute.withEmail(_emailCtl.text.trim()),
                      ),
              child: const Text('Забыли пароль?'),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const CircularProgressIndicator()
          else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _signIn,
                child: const Text('Войти'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _loading
                    ? null
                    : () => context.push(RegisterRoute.path),
                child: const Text('Зарегистрироваться'),
              ),
            ),
            if (GoogleAuthConfig.isConfigured) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Войти через Google'),
                  onPressed: _google,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
