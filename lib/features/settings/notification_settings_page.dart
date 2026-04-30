import 'package:flutter/material.dart';
import '../../services/notification_preferences_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  NotificationPreferences? _preferences;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await NotificationPreferencesService.getPreferences();
      setState(() {
        _preferences = prefs;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки настроек: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePreferences() async {
    if (_preferences == null) return;
    
    setState(() => _isSaving = true);
    try {
      final updated = await NotificationPreferencesService.updatePreferences(
        likesEnabled: _preferences!.likesEnabled,
        commentsEnabled: _preferences!.commentsEnabled,
        followsEnabled: _preferences!.followsEnabled,
        repostsEnabled: _preferences!.repostsEnabled,
        mentionsEnabled: _preferences!.mentionsEnabled,
        systemEnabled: _preferences!.systemEnabled,
        pushEnabled: _preferences!.pushEnabled,
      );
      setState(() {
        _preferences = updated;
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки уведомлений сохранены')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Уведомления')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_preferences == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Уведомления')),
        body: const Center(child: Text('Не удалось загрузить настройки')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Уведомления')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Общий переключатель push уведомлений
          Card(
            child: SwitchListTile(
              title: const Text('Push уведомления'),
              subtitle: const Text(
                'Включить или выключить все push уведомления',
              ),
              value: _preferences!.pushEnabled,
              onChanged: (v) {
                setState(() {
                  _preferences = _preferences!.copyWith(pushEnabled: v);
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          
          // Типы уведомлений
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Лайки'),
                  subtitle: const Text(
                    'Получать уведомления, когда кто-то лайкает ваш контент',
                  ),
                  value: _preferences!.likesEnabled,
                  onChanged: _preferences!.pushEnabled
                      ? (v) {
                          setState(() {
                            _preferences = _preferences!.copyWith(likesEnabled: v);
                          });
                        }
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Комментарии'),
                  subtitle: const Text('Получать уведомления о новых комментариях'),
                  value: _preferences!.commentsEnabled,
                  onChanged: _preferences!.pushEnabled
                      ? (v) {
                          setState(() {
                            _preferences = _preferences!.copyWith(commentsEnabled: v);
                          });
                        }
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Подписки'),
                  subtitle: const Text(
                    'Получать уведомления, когда кто-то подписывается на вас',
                  ),
                  value: _preferences!.followsEnabled,
                  onChanged: _preferences!.pushEnabled
                      ? (v) {
                          setState(() {
                            _preferences = _preferences!.copyWith(followsEnabled: v);
                          });
                        }
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Репосты'),
                  subtitle: const Text(
                    'Получать уведомления, когда кто-то репостит ваш контент',
                  ),
                  value: _preferences!.repostsEnabled,
                  onChanged: _preferences!.pushEnabled
                      ? (v) {
                          setState(() {
                            _preferences = _preferences!.copyWith(repostsEnabled: v);
                          });
                        }
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Упоминания'),
                  subtitle: const Text(
                    'Получать уведомления, когда вас упоминают в постах',
                  ),
                  value: _preferences!.mentionsEnabled,
                  onChanged: _preferences!.pushEnabled
                      ? (v) {
                          setState(() {
                            _preferences = _preferences!.copyWith(mentionsEnabled: v);
                          });
                        }
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Системные уведомления'),
                  subtitle: const Text(
                    'Получать важные системные уведомления и обновления',
                  ),
                  value: _preferences!.systemEnabled,
                  onChanged: _preferences!.pushEnabled
                      ? (v) {
                          setState(() {
                            _preferences = _preferences!.copyWith(systemEnabled: v);
                          });
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSaving ? null : _savePreferences,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Сохранить настройки'),
          ),
        ],
      ),
    );
  }
}
