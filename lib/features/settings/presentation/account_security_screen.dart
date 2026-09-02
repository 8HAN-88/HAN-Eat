import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_router.dart';
import '../../../services/auth_service.dart';
import '../../../services/auth_sessions_service.dart';
import '../../../utils/api_error_parser.dart';

/// Центр безопасности аккаунта: активные сеансы и быстрые действия.
class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  bool _busy = false;
  bool _loading = true;
  String? _error;
  List<AuthSessionInfo> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AuthSessionsService.listSessions();
      if (!mounted) return;
      setState(() {
        _sessions = items;
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

  String _fmt(DateTime dt) =>
      DateFormat('dd.MM.yyyy HH:mm').format(dt.toLocal());

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Аккаунт и безопасность'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Аккаунт'),
              subtitle: Text(
                user == null
                    ? 'Неизвестный пользователь'
                    : '${user.email}\nАктивные сеансы на устройствах',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(ProfileAuthRoute.path),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Активные сеансы',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Card(
              child: ListTile(
                title: Text(_error!),
                trailing: TextButton(
                  onPressed: _load,
                  child: const Text('Повторить'),
                ),
              ),
            )
          else if (_sessions.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Нет активных сеансов',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'После следующего входа здесь появятся устройства.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Обновить'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < _sessions.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _SessionTile(
                      session: _sessions[i],
                      busy: _busy,
                      onRevoke: () => _revokeOne(_sessions[i]),
                      format: _fmt,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: const Text('Пароль и вход'),
                  subtitle:
                      const Text('Смена пароля, email и вход через провайдеры'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(ProfileAuthRoute.path),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Двухфакторная защита'),
                  subtitle: const Text(
                    'Код из аутентификатора при входе',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(TwoFactorSetupRoute.path),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.favorite_outline),
                  title: const Text('Близкие друзья'),
                  subtitle: const Text(
                    'Кто видит сторис «Близкие друзья»',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(CloseFriendsRoute.path),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy || _sessions.length <= 1 ? null : _revokeOthers,
            icon: const Icon(Icons.phonelink_erase_outlined),
            label: const Text('Завершить другие сеансы'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _logoutEverywhere,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            label: const Text('Завершить все сеансы'),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeOne(AuthSessionInfo session) async {
    if (session.isCurrent) {
      await _logoutEverywhere();
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthSessionsService.revokeSession(session.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сеанс завершён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_revokeOne(session)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeOthers() async {
    setState(() => _busy = true);
    try {
      await AuthSessionsService.revokeOthers();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Другие сеансы завершены')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_revokeOthers()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logoutEverywhere() async {
    setState(() => _busy = true);
    try {
      try {
        await AuthSessionsService.revokeAll();
      } catch (_) {
        // Still clear local session even if API fails.
      }
      await AuthService.logout();
      if (!mounted) return;
      context.go(LoginRoute.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.busy,
    required this.onRevoke,
    required this.format,
  });

  final AuthSessionInfo session;
  final bool busy;
  final VoidCallback onRevoke;
  final String Function(DateTime) format;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        session.isCurrent ? Icons.smartphone : Icons.devices_other_outlined,
        color: session.isCurrent ? scheme.primary : null,
      ),
      title: Text(
        session.isCurrent ? '${session.title} · это устройство' : session.title,
      ),
      subtitle: Text(
        [
          if ((session.ipAddress ?? '').isNotEmpty) session.ipAddress!,
          'Активность: ${format(session.lastSeenAt)}',
          'Вход: ${format(session.createdAt)}',
        ].join('\n'),
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: session.isCurrent ? 'Выйти' : 'Завершить',
        onPressed: busy ? null : onRevoke,
        icon: Icon(
          session.isCurrent ? Icons.logout : Icons.close,
          color: scheme.error,
        ),
      ),
    );
  }
}
