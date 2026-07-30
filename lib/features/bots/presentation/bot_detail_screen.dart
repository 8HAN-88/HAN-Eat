import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/api_service.dart';
import '../../../services/chat_service.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/telegram_ui.dart';
import '../../miniapps/data/miniapp_models.dart';
import '../../miniapps/data/miniapps_service.dart';
import '../../miniapps/presentation/miniapp_webview_screen.dart';
import '../data/bot_models.dart';
import '../data/bot_token_storage.dart';

String _moderationLabel(MiniAppItem app) {
  if (app.isApproved) return 'Одобрено';
  if (app.isRejected) return 'Отклонено';
  return 'На проверке';
}

/// Управление ботом — как меню @BotFather.
class BotDetailScreen extends StatefulWidget {
  const BotDetailScreen({
    super.key,
    required this.botId,
    required this.botUsername,
    this.initialToken,
    this.showTokenOnOpen = false,
  });

  final int botId;
  final String botUsername;
  final String? initialToken;
  final bool showTokenOnOpen;

  @override
  State<BotDetailScreen> createState() => _BotDetailScreenState();
}

class _BotDetailScreenState extends State<BotDetailScreen> {
  BotResponse? _bot;
  String? _token;
  bool _isLoading = true;
  List<BotCommandCreate> _commands = [];
  List<MiniAppItem> _miniApps = [];
  bool _miniAppsLoading = false;
  final _webhookController = TextEditingController();
  final _webhookSecretController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _token = widget.initialToken;
    _loadBot().then((_) {
      if (widget.showTokenOnOpen && mounted) {
        _showTokenSheet(forceReveal: true);
      }
    });
  }

  @override
  void dispose() {
    _webhookController.dispose();
    _webhookSecretController.dispose();
    super.dispose();
  }

  Future<void> _ensureTokenLoaded() async {
    if (_token != null && _token!.isNotEmpty) return;
    final saved = await BotTokenStorage.getToken(widget.botId);
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => _token = saved);
    }
  }

  Future<void> _loadBot() async {
    setState(() => _isLoading = true);
    try {
      final bot = await ApiService.getBot(widget.botId);
      if (!mounted) return;
      setState(() {
        _bot = bot;
        _webhookController.text = bot.webhookUrl ?? '';
        if ((_token == null || _token!.isEmpty) && bot.botToken.isNotEmpty) {
          _token = bot.botToken;
        }
      });
      await Future.wait([_loadCommands(), _loadMiniApps()]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      await _ensureTokenLoaded();
    }
  }

  Future<void> _loadCommands() async {
    try {
      final cmds = await ApiService.getBotCommands(widget.botId);
      if (mounted) setState(() => _commands = cmds);
    } catch (_) {}
  }

  Future<void> _loadMiniApps() async {
    if (!mounted) return;
    setState(() => _miniAppsLoading = true);
    try {
      final apps = await MiniAppsService.fetchByBot(widget.botId);
      if (mounted) setState(() => _miniApps = apps);
    } catch (_) {
      if (mounted) setState(() => _miniApps = []);
    } finally {
      if (mounted) setState(() => _miniAppsLoading = false);
    }
  }

  Future<void> _showTokenSheet({bool forceReveal = false}) async {
    await _ensureTokenLoaded();
    final token = _token ?? _bot?.botToken ?? '';
    if (!mounted) return;
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Токен недоступен. Если вы его потеряли — сделайте Revoke Token.',
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  forceReveal ? 'Done! Congratulations on your new bot.' : 'API Token',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  forceReveal
                      ? 'Сохраните токен сейчас — как в Telegram, он нужен для API.'
                      : 'Используйте этот токен для HTTP API вашего бота.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 14),
                SelectableText(
                  token,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: token));
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Токен скопирован')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Скопировать токен'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editBotProfile() async {
    final bot = _bot;
    if (bot == null) return;
    final result = await showDialog<_BotProfileEdit>(
      context: context,
      builder: (_) => _EditBotProfileDialog(bot: bot),
    );
    if (result == null) return;
    try {
      final updated = await ApiService.updateBot(
        widget.botId,
        BotUpdateRequest(
          name: result.name,
          description: result.description,
          shortDescription: result.shortDescription,
        ),
      );
      if (!mounted) return;
      setState(() => _bot = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль бота обновлён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $e')),
      );
    }
  }

  Future<void> _revokeToken() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke token?'),
        content: const Text(
          'Как /revoke в BotFather: старый токен перестанет работать, '
          'будет выдан новый.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final updated = await ApiService.revokeBotToken(widget.botId);
      await BotTokenStorage.saveToken(widget.botId, updated.botToken);
      if (!mounted) return;
      setState(() {
        _bot = updated;
        _token = updated.botToken;
      });
      await _showTokenSheet(forceReveal: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить токен: $e')),
      );
    }
  }

  Future<void> _deleteBot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить бота?'),
        content: Text(
          'Бот @${widget.botUsername}, его команды и мини-приложения '
          'будут удалены без восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteBot(widget.botId);
      await BotTokenStorage.removeToken(widget.botId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $e')),
      );
    }
  }

  Future<void> _manageCommands() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _BotCommandsScreen(
          botId: widget.botId,
          botUsername: widget.botUsername,
          initialCommands: _commands,
          onChanged: _loadCommands,
        ),
      ),
    );
    await _loadCommands();
  }

  Future<void> _manageMiniApps() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _BotMiniAppsScreen(
          botId: widget.botId,
          botUsername: widget.botUsername,
        ),
      ),
    );
    await _loadMiniApps();
  }

  Future<void> _manageWebhook() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Webhook',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _bot?.webhookEnabled == true
                    ? 'Webhook включён'
                    : 'Webhook выключен',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _webhookController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://your-server.com/webhook',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _webhookSecretController,
                decoration: const InputDecoration(
                  labelText: 'Secret token (опционально)',
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _saveWebhook();
                },
                child: const Text('Сохранить'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  _webhookController.clear();
                  await _saveWebhook();
                },
                child: const Text('Удалить webhook'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveWebhook() async {
    final url = _webhookController.text.trim();
    try {
      if (url.isEmpty) {
        await ApiService.deleteBotWebhook(widget.botId);
      } else {
        await ApiService.setBotWebhook(
          botId: widget.botId,
          url: url,
          secretToken: _webhookSecretController.text.trim().isEmpty
              ? null
              : _webhookSecretController.text.trim(),
        );
      }
      await _loadBot();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(url.isEmpty ? 'Webhook удалён' : 'Webhook сохранён'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _showAddToChatSheet() async {
    final convId = await showDialog<int>(
      context: context,
      builder: (_) => const _SelectChatDialog(),
    );
    if (convId == null) return;
    try {
      await ApiService.addBotToChat(
        botId: widget.botId,
        conversationId: convId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Бот добавлен в чат')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  void _showMoreMenu() {
    showTelegramActionSheet<void>(
      context: context,
      title: '@${widget.botUsername}',
      actions: [
        TelegramActionSheetAction(
          icon: Icons.refresh_rounded,
          title: 'Обновить',
          onTap: _loadBot,
        ),
        TelegramActionSheetAction(
          icon: Icons.key_off_outlined,
          title: 'Revoke token',
          subtitle: 'Выдать новый API-токен',
          onTap: _revokeToken,
        ),
        TelegramActionSheetAction(
          icon: Icons.delete_outline_rounded,
          title: 'Удалить бота',
          destructive: true,
          onTap: _deleteBot,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bot = _bot;
    final scheme = Theme.of(context).colorScheme;

    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '@${widget.botUsername}',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    NeoCircleAction(
                      icon: Icons.more_horiz_rounded,
                      tooltip: 'Ещё',
                      onPressed: _showMoreMenu,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _isLoading && bot == null
                  ? const Center(child: CircularProgressIndicator())
                  : bot == null
                      ? const Center(child: Text('Бот не найден'))
                      : RefreshIndicator(
                          onRefresh: _loadBot,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            children: [
                              Center(
                                child: Container(
                                  width: 84,
                                  height: 84,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer
                                        .withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.smart_toy_rounded,
                                    size: 40,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                bot.name,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (bot.shortDescription ?? bot.description ?? '')
                                        .trim()
                                        .isEmpty
                                    ? 'Настройте бота как в @BotFather'
                                    : (bot.shortDescription ??
                                        bot.description)!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 22),
                              _BotFatherGroup(
                                children: [
                                  _BotFatherTile(
                                    icon: Icons.key_rounded,
                                    title: 'API Token',
                                    subtitle: 'Показать / скопировать токен',
                                    onTap: () => _showTokenSheet(),
                                  ),
                                  _BotFatherTile(
                                    icon: Icons.edit_outlined,
                                    title: 'Edit Bot',
                                    subtitle: 'Имя, About, Description',
                                    onTap: _editBotProfile,
                                  ),
                                  _BotFatherTile(
                                    icon: Icons.code_rounded,
                                    title: 'Edit Commands',
                                    subtitle: _commands.isEmpty
                                        ? 'Команд пока нет'
                                        : '${_commands.length} команд(ы)',
                                    onTap: _manageCommands,
                                  ),
                                  _BotFatherTile(
                                    icon: Icons.apps_rounded,
                                    title: 'Mini Apps',
                                    subtitle: _miniAppsLoading
                                        ? 'Загрузка…'
                                        : _miniApps.isEmpty
                                            ? 'New App · Edit App · Delete App'
                                            : '${_miniApps.length} · ${_miniApps.where((a) => a.isApproved).length} в каталоге',
                                    onTap: _manageMiniApps,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _BotFatherGroup(
                                children: [
                                  _BotFatherTile(
                                    icon: Icons.webhook_outlined,
                                    title: 'Webhook',
                                    subtitle: bot.webhookEnabled
                                        ? 'Включён'
                                        : 'Не задан',
                                    onTap: _manageWebhook,
                                  ),
                                  _BotFatherTile(
                                    icon: Icons.chat_bubble_outline_rounded,
                                    title: 'Add to Chat',
                                    subtitle: 'Добавить бота в чат или группу',
                                    onTap: _showAddToChatSheet,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _BotFatherGroup(
                                children: [
                                  _BotFatherTile(
                                    icon: Icons.key_off_outlined,
                                    title: 'Revoke Token',
                                    subtitle: 'Старый токен перестанет работать',
                                    onTap: _revokeToken,
                                  ),
                                  _BotFatherTile(
                                    icon: Icons.delete_outline_rounded,
                                    title: 'Delete Bot',
                                    subtitle: 'Удалить бота навсегда',
                                    destructive: true,
                                    onTap: _deleteBot,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotFatherGroup extends StatelessWidget {
  const _BotFatherGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.04)
            : scheme.surfaceContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
          width: 0.7,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                indent: 56,
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
          ],
        ],
      ),
    );
  }
}

class _BotFatherTile extends StatelessWidget {
  const _BotFatherTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = destructive ? scheme.error : scheme.onSurface;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: fg),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, color: fg),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                color: destructive
                    ? scheme.error.withValues(alpha: 0.8)
                    : scheme.onSurfaceVariant,
              ),
            ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class _EditBotProfileDialog extends StatefulWidget {
  const _EditBotProfileDialog({required this.bot});

  final BotResponse bot;

  @override
  State<_EditBotProfileDialog> createState() => _EditBotProfileDialogState();
}

class _EditBotProfileDialogState extends State<_EditBotProfileDialog> {
  late final TextEditingController _name;
  late final TextEditingController _about;
  late final TextEditingController _desc;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.bot.name);
    _about = TextEditingController(text: widget.bot.shortDescription ?? '');
    _desc = TextEditingController(text: widget.bot.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Bot'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _about,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'About',
                helperText: 'Короткое описание в профиле бота',
              ),
            ),
            TextField(
              controller: _desc,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                helperText: 'Что умеет бот',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _BotProfileEdit(
                name: name,
                shortDescription: _about.text.trim(),
                description: _desc.text.trim(),
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _BotProfileEdit {
  const _BotProfileEdit({
    required this.name,
    required this.shortDescription,
    required this.description,
  });

  final String name;
  final String shortDescription;
  final String description;
}

// ---------------------------------------------------------------------------
// Mini Apps (BotFather: /newapp /editapp /deleteapp)
// ---------------------------------------------------------------------------

class _BotMiniAppsScreen extends StatefulWidget {
  const _BotMiniAppsScreen({
    required this.botId,
    required this.botUsername,
  });

  final int botId;
  final String botUsername;

  @override
  State<_BotMiniAppsScreen> createState() => _BotMiniAppsScreenState();
}

class _BotMiniAppsScreenState extends State<_BotMiniAppsScreen> {
  bool _loading = true;
  List<MiniAppItem> _apps = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final apps = await MiniAppsService.fetchByBot(widget.botId);
      if (!mounted) return;
      setState(() => _apps = apps);
    } catch (_) {
      if (mounted) setState(() => _apps = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newApp() async {
    final result = await showDialog<_MiniAppFormResult>(
      context: context,
      builder: (_) => const _MiniAppFormDialog(title: 'New Mini App'),
    );
    if (result == null) return;
    try {
      await MiniAppsService.createMiniApp(
        MiniAppCreateRequest(
          botId: widget.botId,
          name: result.name,
          shortName: result.shortName,
          url: result.url,
          description: result.description,
          category: result.category,
          iconUrl: result.iconUrl,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Мини-приложение создано и отправлено на проверку'),
        ),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _editApp(MiniAppItem app) async {
    final result = await showDialog<_MiniAppFormResult>(
      context: context,
      builder: (_) => _MiniAppFormDialog(
        title: 'Edit Mini App',
        initial: app,
        shortNameReadOnly: true,
      ),
    );
    if (result == null) return;
    try {
      await MiniAppsService.updateMiniApp(
        app.id,
        MiniAppUpdateRequest(
          name: result.name,
          url: result.url,
          description: result.description,
          category: result.category,
          iconUrl: result.iconUrl ?? '',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Изменения сохранены')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _toggleActive(MiniAppItem app) async {
    try {
      await MiniAppsService.updateMiniApp(
        app.id,
        MiniAppUpdateRequest(isActive: !app.isActive),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _deleteApp(MiniAppItem app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Mini App?'),
        content: Text('«${app.name}» будет удалено из каталога.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MiniAppsService.deleteMiniApp(app.id);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _openApp(MiniAppItem app) async {
    try {
      final launch = await MiniAppsService.getLaunchContext(app.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MiniAppWebViewScreen(
            title: app.name,
            subtitle: '@${widget.botUsername}',
            url: launch.url,
            initData: launch.initData,
            initDataUnsafe: launch.initDataUnsafe,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть: $e')),
      );
    }
  }

  void _showAppActions(MiniAppItem app) {
    showTelegramActionSheet<void>(
      context: context,
      title: app.name,
      actions: [
        TelegramActionSheetAction(
          icon: Icons.open_in_new_rounded,
          title: 'Open App',
          onTap: () => _openApp(app),
        ),
        TelegramActionSheetAction(
          icon: Icons.edit_outlined,
          title: 'Edit App',
          subtitle: 'Название, URL, описание, иконка',
          onTap: () => _editApp(app),
        ),
        TelegramActionSheetAction(
          icon: app.isActive
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          title: app.isActive ? 'Deactivate' : 'Activate',
          onTap: () => _toggleActive(app),
        ),
        TelegramActionSheetAction(
          icon: Icons.delete_outline_rounded,
          title: 'Delete App',
          destructive: true,
          onTap: () => _deleteApp(app),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Mini Apps',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    NeoCircleAction(
                      icon: Icons.add_rounded,
                      tooltip: 'New App',
                      onPressed: _newApp,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(
                'Как /newapp в BotFather: short name уникален для бота, '
                'после проверки приложение появится в каталоге.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _apps.isEmpty
                      ? Center(
                          child: FilledButton.icon(
                            onPressed: _newApp,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('New Mini App'),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _reload,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                            itemCount: _apps.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final app = _apps[index];
                              return ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                leading: CircleAvatar(
                                  child: Icon(
                                    app.isActive
                                        ? Icons.apps_rounded
                                        : Icons.apps_outage_outlined,
                                  ),
                                ),
                                title: Text(
                                  app.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    app.shortName,
                                    _moderationLabel(app),
                                    if (!app.isActive) 'выкл.',
                                  ].join(' · '),
                                ),
                                trailing: const Icon(Icons.more_horiz_rounded),
                                onTap: () => _showAppActions(app),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAppFormResult {
  const _MiniAppFormResult({
    required this.name,
    required this.shortName,
    required this.url,
    this.description,
    this.category,
    this.iconUrl,
  });

  final String name;
  final String shortName;
  final String url;
  final String? description;
  final String? category;
  final String? iconUrl;
}

class _MiniAppFormDialog extends StatefulWidget {
  const _MiniAppFormDialog({
    required this.title,
    this.initial,
    this.shortNameReadOnly = false,
  });

  final String title;
  final MiniAppItem? initial;
  final bool shortNameReadOnly;

  @override
  State<_MiniAppFormDialog> createState() => _MiniAppFormDialogState();
}

class _MiniAppFormDialogState extends State<_MiniAppFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _short;
  late final TextEditingController _url;
  late final TextEditingController _desc;
  late final TextEditingController _icon;
  late String _category;
  static final _shortRe = RegExp(r'^[a-z0-9_]{3,30}$');

  @override
  void initState() {
    super.initState();
    final app = widget.initial;
    _name = TextEditingController(text: app?.name ?? '');
    _short = TextEditingController(text: app?.shortName ?? '');
    _url = TextEditingController(text: app?.url ?? 'https://');
    _desc = TextEditingController(text: app?.description ?? '');
    _icon = TextEditingController(text: app?.iconUrl ?? '');
    final existing = (app?.category ?? 'tools').toLowerCase();
    _category = MiniAppCategory.known.any((c) => c.id == existing)
        ? existing
        : 'tools';
  }

  @override
  void dispose() {
    _name.dispose();
    _short.dispose();
    _url.dispose();
    _desc.dispose();
    _icon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _short,
              readOnly: widget.shortNameReadOnly,
              decoration: const InputDecoration(
                labelText: 'Short name',
                helperText: '3–30: a-z, 0-9, _ · уникален для бота',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'Web App URL',
                hintText: 'https://…',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: MiniAppCategory.known
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.label)),
                  )
                  .toList(growable: false),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _category = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _icon,
              decoration: const InputDecoration(
                labelText: 'Photo URL (опционально)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final shortName = _short.text.trim().toLowerCase();
            final url = _url.text.trim();
            if (name.isEmpty || shortName.isEmpty || url.isEmpty) return;
            if (!_shortRe.hasMatch(shortName)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Short name: 3–30 символов, a-z 0-9 _'),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              _MiniAppFormResult(
                name: name,
                shortName: shortName,
                url: url,
                description:
                    _desc.text.trim().isEmpty ? null : _desc.text.trim(),
                category: _category,
                iconUrl:
                    _icon.text.trim().isEmpty ? null : _icon.text.trim(),
              ),
            );
          },
          child: Text(widget.initial == null ? 'Создать' : 'Сохранить'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

class _BotCommandsScreen extends StatefulWidget {
  const _BotCommandsScreen({
    required this.botId,
    required this.botUsername,
    required this.initialCommands,
    required this.onChanged,
  });

  final int botId;
  final String botUsername;
  final List<BotCommandCreate> initialCommands;
  final Future<void> Function() onChanged;

  @override
  State<_BotCommandsScreen> createState() => _BotCommandsScreenState();
}

class _BotCommandsScreenState extends State<_BotCommandsScreen> {
  late List<BotCommandCreate> _commands;

  @override
  void initState() {
    super.initState();
    _commands = List.of(widget.initialCommands);
  }

  Future<void> _reload() async {
    final cmds = await ApiService.getBotCommands(widget.botId);
    if (!mounted) return;
    setState(() => _commands = cmds);
    await widget.onChanged();
  }

  Future<void> _add() async {
    final result = await showDialog<_CommandResult>(
      context: context,
      builder: (_) => const _AddCommandDialog(),
    );
    if (result == null) return;
    try {
      await ApiService.addBotCommand(
        widget.botId,
        BotCommandCreate(
          command: result.command,
          description: result.description,
          responseText: result.responseText,
          inlineButtonRows: result.inlineButtonRows,
        ),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _edit(BotCommandCreate command) async {
    final result = await showDialog<_CommandResult>(
      context: context,
      builder: (_) => _AddCommandDialog(initial: command, isEdit: true),
    );
    if (result == null) return;
    try {
      await ApiService.updateBotCommand(
        botId: widget.botId,
        command: command.command,
        cmd: BotCommandCreate(
          command: command.command,
          description: result.description,
          responseText: result.responseText,
          inlineButtonRows: result.inlineButtonRows,
        ),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _delete(String command) async {
    try {
      await ApiService.deleteBotCommand(widget.botId, command);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Commands',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    NeoCircleAction(
                      icon: Icons.add_rounded,
                      onPressed: _add,
                      tooltip: 'Добавить команду',
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _commands.isEmpty
                  ? Center(
                      child: FilledButton.icon(
                        onPressed: _add,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Добавить /start'),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                      itemCount: _commands.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final c = _commands[index];
                        return ListTile(
                          leading: const Icon(Icons.code_rounded),
                          title: Text('/${c.command}'),
                          subtitle: Text(c.description),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(c),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(c.command),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectChatDialog extends StatefulWidget {
  const _SelectChatDialog();

  @override
  State<_SelectChatDialog> createState() => _SelectChatDialogState();
}

class _SelectChatDialogState extends State<_SelectChatDialog> {
  late Future<List<_DialogConversation>> _future;
  int? _selectedConversationId;

  @override
  void initState() {
    super.initState();
    _future = _loadConversations();
  }

  Future<List<_DialogConversation>> _loadConversations() async {
    final items = await ChatService.listConversations();
    return items
        .where((c) => !c.isSaved)
        .map(
          (c) => _DialogConversation(
            id: c.id,
            title: c.displayTitle,
            subtitle: c.isGroup ? 'Группа' : 'Личный чат',
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Выберите чат'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<List<_DialogConversation>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return const Text('Не удалось загрузить список чатов');
            }
            final chats = snapshot.data ?? const [];
            if (chats.isEmpty) {
              return const Text('Нет доступных чатов');
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  final chat = chats[index];
                  return RadioListTile<int>(
                    value: chat.id,
                    groupValue: _selectedConversationId,
                    title: Text(chat.title),
                    subtitle: Text(chat.subtitle),
                    onChanged: (value) {
                      setState(() => _selectedConversationId = value);
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _selectedConversationId == null
              ? null
              : () => Navigator.pop(context, _selectedConversationId),
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}

class _DialogConversation {
  const _DialogConversation({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final int id;
  final String title;
  final String subtitle;
}

class _AddCommandDialog extends StatefulWidget {
  const _AddCommandDialog({
    this.initial,
    this.isEdit = false,
  });

  final BotCommandCreate? initial;
  final bool isEdit;

  @override
  State<_AddCommandDialog> createState() => _AddCommandDialogState();
}

class _AddCommandDialogState extends State<_AddCommandDialog> {
  final _cmdController = TextEditingController();
  final _descController = TextEditingController();
  final _responseController = TextEditingController();
  final _buttonsController = TextEditingController();
  static final RegExp _commandRegExp = RegExp(r'^[a-zA-Z0-9_]{1,32}$');

  @override
  void initState() {
    super.initState();
    _buttonsController.addListener(_onButtonsChanged);
    final initial = widget.initial;
    if (initial == null) return;
    _cmdController.text = initial.command;
    _descController.text = initial.description;
    _responseController.text = initial.responseText ?? '';
    _buttonsController.text = _serializeButtonRows(initial.inlineButtonRows);
  }

  @override
  void dispose() {
    _buttonsController.removeListener(_onButtonsChanged);
    _cmdController.dispose();
    _descController.dispose();
    _responseController.dispose();
    _buttonsController.dispose();
    super.dispose();
  }

  void _onButtonsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final parsedButtons =
        _parseInlineButtonRowsWithDiagnostics(_buttonsController.text);
    return AlertDialog(
      title: Text(widget.isEdit ? 'Редактировать команду' : 'Добавить команду'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _cmdController,
              decoration: const InputDecoration(labelText: 'Команда (без /)'),
              readOnly: widget.isEdit,
            ),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Описание'),
            ),
            TextField(
              controller: _responseController,
              decoration: const InputDecoration(
                labelText: 'Ответ бота (опционально)',
              ),
              minLines: 2,
              maxLines: 4,
            ),
            TextField(
              controller: _buttonsController,
              decoration: const InputDecoration(
                labelText: 'Inline-кнопки (строки через пустую строку)',
                hintText: 'Текст|cb_data|Ответ\nТекст|url:https://site',
              ),
              minLines: 2,
              maxLines: 8,
            ),
            if (parsedButtons.errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    parsedButtons.errors.first,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final command = _cmdController.text.trim();
            final description = _descController.text.trim();
            if (command.isEmpty || description.isEmpty) return;
            if (!_commandRegExp.hasMatch(command)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Команда: только a-z, 0-9 и _ (до 32 символов)'),
                ),
              );
              return;
            }
            if (parsedButtons.errors.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(parsedButtons.errors.first)),
              );
              return;
            }
            Navigator.pop(
              context,
              _CommandResult(
                command: command,
                description: description,
                responseText: _responseController.text.trim().isEmpty
                    ? null
                    : _responseController.text.trim(),
                inlineButtonRows: parsedButtons.rows,
              ),
            );
          },
          child: Text(widget.isEdit ? 'Сохранить' : 'Добавить'),
        ),
      ],
    );
  }

  _ButtonsParseResult _parseInlineButtonRowsWithDiagnostics(String source) {
    final rows = <List<BotInlineButton>>[];
    final errors = <String>[];
    var current = <BotInlineButton>[];
    var buttonsCount = 0;
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        if (current.isNotEmpty) {
          rows.add(current);
          current = <BotInlineButton>[];
        }
        continue;
      }
      final parts = line.split('|');
      if (parts.length < 2) {
        errors.add(
          'Строка ${i + 1}: формат Текст|cb_data или Текст|url:https://...',
        );
        continue;
      }
      final text = parts[0].trim();
      final action = parts[1].trim();
      final third = parts.length >= 3 ? parts[2].trim() : '';
      if (text.isEmpty || action.isEmpty) {
        errors.add('Строка ${i + 1}: текст и действие обязательны');
        continue;
      }
      if (text.length > 64) {
        errors.add('Строка ${i + 1}: текст кнопки до 64 символов');
        continue;
      }

      BotInlineButton? btn;
      if (action.startsWith('url:')) {
        final url = action.substring(4).trim();
        if (!_isValidButtonUrl(url)) {
          errors.add('Строка ${i + 1}: некорректный URL кнопки');
          continue;
        }
        btn = BotInlineButton(text: text, url: url);
      } else if (action.startsWith('http://') ||
          action.startsWith('https://')) {
        if (!_isValidButtonUrl(action)) {
          errors.add('Строка ${i + 1}: некорректный URL кнопки');
          continue;
        }
        btn = BotInlineButton(text: text, url: action);
      } else {
        if (action.length > 128) {
          errors.add('Строка ${i + 1}: callback_data до 128 символов');
          continue;
        }
        if (third.length > 300) {
          errors.add('Строка ${i + 1}: callback text до 300 символов');
          continue;
        }
        btn = BotInlineButton(
          text: text,
          callbackData: action,
          callbackText: third.isEmpty ? null : third,
        );
      }
      current.add(btn);
      buttonsCount += 1;
      if (buttonsCount > 40) {
        errors.add('Слишком много кнопок (максимум 40)');
        break;
      }
    }
    if (current.isNotEmpty) rows.add(current);
    if (rows.length > 8) {
      errors.add('Слишком много рядов кнопок (максимум 8)');
    }
    return _ButtonsParseResult(
      rows: rows.length > 8 ? rows.take(8).toList(growable: false) : rows,
      errors: errors,
    );
  }

  bool _isValidButtonUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority) return false;
    return uri.scheme == 'https' || uri.scheme == 'http';
  }

  String _serializeButtonRows(List<List<BotInlineButton>> rows) {
    if (rows.isEmpty) return '';
    final out = <String>[];
    for (final row in rows) {
      for (final btn in row) {
        if (btn.url != null && btn.url!.trim().isNotEmpty) {
          out.add('${btn.text}|url:${btn.url}');
          continue;
        }
        final callback = btn.callbackData?.trim() ?? '';
        if (callback.isEmpty) continue;
        final callbackText = btn.callbackText?.trim();
        if (callbackText != null && callbackText.isNotEmpty) {
          out.add('${btn.text}|$callback|$callbackText');
        } else {
          out.add('${btn.text}|$callback');
        }
      }
      out.add('');
    }
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    return out.join('\n');
  }
}

class _ButtonsParseResult {
  final List<List<BotInlineButton>> rows;
  final List<String> errors;
  const _ButtonsParseResult({required this.rows, required this.errors});
}

class _CommandResult {
  final String command;
  final String description;
  final String? responseText;
  final List<List<BotInlineButton>> inlineButtonRows;
  _CommandResult({
    required this.command,
    required this.description,
    this.responseText,
    this.inlineButtonRows = const [],
  });
}
