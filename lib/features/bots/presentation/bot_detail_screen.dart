import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/api_service.dart';
import '../../../services/chat_service.dart';
import '../../miniapps/data/miniapp_models.dart';
import '../../miniapps/data/miniapps_service.dart';
import '../../miniapps/presentation/miniapp_webview_screen.dart';
import '../data/bot_models.dart';
import '../data/bot_token_storage.dart';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _formatWebhookDateTime(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  return '${_twoDigits(local.day)}.${_twoDigits(local.month)} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _shortWebhookId(String? value) {
  final id = (value ?? '').trim();
  if (id.isEmpty) return '';
  if (id.length <= 12) return id;
  return '${id.substring(0, 12)}...';
}

/// Экран управления ботом (BotFather detail)
class BotDetailScreen extends StatefulWidget {
  const BotDetailScreen({
    super.key,
    required this.botId,
    required this.botUsername,
    this.initialToken,
  });

  final int botId;
  final String botUsername;
  final String? initialToken;

  @override
  State<BotDetailScreen> createState() => _BotDetailScreenState();
}

class _BotDetailScreenState extends State<BotDetailScreen> {
  BotResponse? _bot;
  String? _token;
  bool _isLoading = true;
  bool _analyticsLoading = false;
  bool _webhookTesting = false;
  bool _webhookAttemptsLoading = false;
  List<BotCommandCreate> _commands = [];
  List<MiniAppItem> _miniApps = [];
  bool _miniAppsLoading = false;
  BotAnalyticsResponse? _analytics;
  List<BotWebhookAttempt> _webhookAttempts = [];
  final _webhookController = TextEditingController();
  final _webhookSecretController = TextEditingController();

  @override
  void dispose() {
    _webhookController.dispose();
    _webhookSecretController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _token = widget.initialToken;
    _loadBot();
  }

  Future<void> _ensureTokenLoaded() async {
    if (_token != null && _token!.isNotEmpty) return;
    final saved = await BotTokenStorage.getToken(widget.botId);
    if (saved != null && saved.isNotEmpty) {
      if (mounted) setState(() => _token = saved);
    }
  }

  Future<void> _loadBot() async {
    setState(() => _isLoading = true);
    try {
      final bot = await ApiService.getBot(widget.botId);
      setState(() {
        _bot = bot;
        _webhookController.text = bot.webhookUrl ?? '';
      });
      await _loadCommands();
      await _loadMiniApps();
      await _loadBotAnalytics();
      await _loadWebhookAttempts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      await _ensureTokenLoaded();
    }
  }

  Future<void> _loadBotAnalytics() async {
    setState(() => _analyticsLoading = true);
    try {
      final data = await ApiService.getBotAnalytics(botId: widget.botId, days: 30);
      if (mounted) setState(() => _analytics = data);
    } catch (_) {
      if (mounted) setState(() => _analytics = null);
    } finally {
      if (mounted) setState(() => _analyticsLoading = false);
    }
  }

  Future<void> _loadWebhookAttempts() async {
    setState(() => _webhookAttemptsLoading = true);
    try {
      final items = await ApiService.getBotWebhookAttempts(
        botId: widget.botId,
        limit: 20,
      );
      if (mounted) setState(() => _webhookAttempts = items);
    } catch (_) {
      if (mounted) setState(() => _webhookAttempts = []);
    } finally {
      if (mounted) setState(() => _webhookAttemptsLoading = false);
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

  Future<void> _deleteCommand(String command) async {
    try {
      await ApiService.deleteBotCommand(widget.botId, command);
      await _loadCommands();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _showAddCommandDialog() async {
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
      await _loadCommands();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _showEditCommandDialog(BotCommandCreate command) async {
    final result = await showDialog<_CommandResult>(
      context: context,
      builder: (_) => _AddCommandDialog(
        initial: command,
        isEdit: true,
      ),
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
      await _loadCommands();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _copyToken() async {
    final tokenToCopy = _token ?? _bot?.botToken;
    if (tokenToCopy == null || tokenToCopy.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Токен недоступен. Скопируйте его сразу после создания.')),
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: tokenToCopy));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Токен скопирован в буфер обмена')),
      );
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(url.isEmpty ? 'Webhook удалён' : 'Webhook сохранён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _testWebhook() async {
    if (_webhookTesting) return;
    setState(() => _webhookTesting = true);
    try {
      final delivered = await ApiService.testBotWebhook(widget.botId);
      await _loadBot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              delivered
                  ? 'Тест webhook успешно доставлен'
                  : 'Тест webhook не доставлен (смотри last error)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка теста webhook: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _webhookTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.botUsername}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bot == null
              ? const Center(child: Text('Бот не найден'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SectionTitle('Токен'),
                    Card(
                      child: ListTile(
                        title: const Text('Токен бота'),
                        subtitle: const Text('Нажмите, чтобы скопировать'),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: _copyToken,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    _SectionTitle('Информация'),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Имя'),
                      controller: TextEditingController(text: _bot!.name),
                      readOnly: true,
                    ),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Описание'),
                      controller: TextEditingController(text: _bot!.description ?? ''),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),

                    _SectionTitle('Webhook (опционально)'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: Icon(
                            _bot!.webhookEnabled
                                ? Icons.check_circle_outline
                                : Icons.pause_circle_outline,
                            size: 16,
                          ),
                          label: Text(
                            _bot!.webhookEnabled
                                ? 'Webhook включен'
                                : 'Webhook выключен',
                          ),
                        ),
                        if ((_bot!.webhookLastError ?? '')
                            .toLowerCase()
                            .contains('auto-disabled'))
                          const Chip(
                            avatar: Icon(Icons.shield_outlined, size: 16),
                            label: Text('Автовыключение защиты'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _webhookController,
                      decoration: const InputDecoration(
                        labelText: 'https://your-server.com/webhook',
                        hintText: 'URL для получения обновлений',
                      ),
                    ),
                    TextField(
                      controller: _webhookSecretController,
                      decoration: const InputDecoration(
                        labelText: 'Secret token (опционально)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _saveWebhook,
                      child: const Text('Сохранить webhook'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _webhookTesting ? null : _testWebhook,
                      icon: _webhookTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bolt_outlined),
                      label: const Text('Тест webhook'),
                    ),
                    if ((_bot?.webhookLastError ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Webhook error: ${_bot!.webhookLastError}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_bot?.webhookLastOkAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Последняя успешная доставка: ${_formatWebhookDateTime(_bot!.webhookLastOkAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Последние webhook попытки',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    if (_webhookAttemptsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    else if (_webhookAttempts.isEmpty)
                      Text(
                        'Пока нет попыток доставки',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      ..._webhookAttempts.take(8).map(
                        (item) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            item.status == 'ok'
                                ? Icons.check_circle_outline
                                : item.status == 'auto_disabled'
                                    ? Icons.shield_outlined
                                    : Icons.error_outline,
                            color: item.status == 'ok'
                                ? Colors.green
                                : item.status == 'auto_disabled'
                                    ? Colors.orange
                                    : Theme.of(context).colorScheme.error,
                          ),
                          title: Text(
                            '${item.updateType ?? item.eventType} · ${item.status}',
                          ),
                          subtitle: Text(
                            [
                              if ((item.deliveryId ?? '').isNotEmpty)
                                'id ${_shortWebhookId(item.deliveryId)}',
                              if (item.attemptsUsed > 0)
                                'attempts ${item.attemptsUsed}',
                              if ((item.error ?? '').isNotEmpty) item.error!,
                              if (item.createdAt != null)
                                _formatWebhookDateTime(item.createdAt),
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),

                    _SectionTitle('Аналитика бота'),
                    if (_analyticsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_analytics == null)
                      const Text('Пока нет данных по аналитике'),
                    if (_analytics != null)
                      _BotAnalyticsCard(analytics: _analytics!),
                    const SizedBox(height: 24),

                    _SectionTitle('Мини-приложения'),
                    if (_miniAppsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_miniApps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Мини-приложений пока нет'),
                      )
                    else
                      ..._miniApps.map(
                        (app) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            app.isOfficial
                                ? Icons.verified_rounded
                                : Icons.apps_rounded,
                          ),
                          title: Text(app.name),
                          subtitle: Text(
                            '@${app.botUsername} · ${app.shortName}'
                            ' · ${app.moderationStatus}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: app.isActive,
                                onChanged: (_) => _toggleMiniAppActive(app),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'open') {
                                    await _openMiniApp(app);
                                  } else if (value == 'delete') {
                                    await _deleteMiniApp(app);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'open',
                                    child: Text('Открыть'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Удалить'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _showAddMiniAppDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить мини-приложение'),
                    ),
                    const SizedBox(height: 24),

                    _SectionTitle('Команды'),
                    if (_commands.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Нет команд. Добавьте первую команду ниже.'),
                      )
                    else
                      ..._commands.map((c) => ListTile(
                            leading: const Icon(Icons.code),
                            title: Text('/${c.command}'),
                            subtitle: Text(
                              [
                                c.description,
                                if (c.responseText != null &&
                                    c.responseText!.trim().isNotEmpty)
                                  'Ответ: ${c.responseText}',
                                if (c.inlineButtonRows.isNotEmpty)
                                  'Рядов: ${c.inlineButtonRows.length}, кнопок: ${c.inlineButtons.length}',
                              ].join('\n'),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showEditCommandDialog(c),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteCommand(c.command),
                                ),
                              ],
                            ),
                          )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _showAddCommandDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить команду'),
                    ),
                    const SizedBox(height: 32),

                    OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Удалить бота
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Удалить бота'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _showAddToChatSheet,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Добавить в чат / канал'),
                    ),
                  ],
                ),
    );
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Бот добавлен в чат')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _showAddMiniAppDialog() async {
    final result = await showDialog<_MiniAppCreateResult>(
      context: context,
      builder: (_) => const _AddMiniAppDialog(),
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
        ),
      );
      await _loadMiniApps();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Мини-приложение добавлено')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _toggleMiniAppActive(MiniAppItem app) async {
    try {
      await MiniAppsService.updateMiniApp(
        app.id,
        MiniAppUpdateRequest(isActive: !app.isActive),
      );
      await _loadMiniApps();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить статус: $e')),
      );
    }
  }

  Future<void> _deleteMiniApp(MiniAppItem app) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить мини-приложение?'),
        content: Text('«${app.name}» будет удалено.'),
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
    if (confirm != true) return;
    try {
      await MiniAppsService.deleteMiniApp(app.id);
      await _loadMiniApps();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить: $e')),
      );
    }
  }

  Future<void> _openMiniApp(MiniAppItem app) async {
    try {
      final launch = await MiniAppsService.getLaunchContext(app.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MiniAppWebViewScreen(
            title: app.name,
            subtitle: app.description ?? 'Мини-приложение',
            url: launch.url,
            initData: launch.initData,
            initDataUnsafe: launch.initDataUnsafe,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть mini app: $e')),
      );
    }
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
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

class _BotAnalyticsCard extends StatelessWidget {
  const _BotAnalyticsCard({required this.analytics});

  final BotAnalyticsResponse analytics;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                _metric('Команды', '${analytics.commandUses}'),
                _metric('Клики', '${analytics.callbackClicks}'),
                _metric('Пользователи', '${analytics.uniqueUsers}'),
                _metric('CTR', '${analytics.callbackCtrPercent.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Webhook delivery',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                _metric('Sent', '${analytics.webhookDelivery.sent}'),
                _metric('Failed', '${analytics.webhookDelivery.failed}'),
                _metric('Success rate',
                    '${analytics.webhookDelivery.successRatePercent.toStringAsFixed(1)}%'),
              ],
            ),
            if (analytics.webhookDelivery.lastOkAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Последний webhook OK: ${_formatWebhookDateTime(analytics.webhookDelivery.lastOkAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if ((analytics.webhookDelivery.lastError ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Последняя ошибка: ${analytics.webhookDelivery.lastError}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
            const SizedBox(height: 10),
            if (analytics.topCommands.isNotEmpty)
              Text(
                'Топ команд: ${analytics.topCommands.take(3).map((e) => '${e.key} (${e.count})').join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (analytics.topCallbacks.isNotEmpty)
              Text(
                'Топ callback: ${analytics.topCallbacks.take(3).map((e) => '${e.key} (${e.count})').join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (analytics.webhookDelivery.topErrors.isNotEmpty)
              Text(
                'Топ webhook ошибок: ${analytics.webhookDelivery.topErrors.take(2).map((e) => '${e.error} (${e.count})').join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Text(label),
      ],
    );
  }
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
    final parsedButtons = _parseInlineButtonRowsWithDiagnostics(_buttonsController.text);
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
            if (parsedButtons.rows.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Предпросмотр клавиатуры',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: parsedButtons.rows
                      .expand((row) => row)
                      .map((b) => Chip(label: Text(b.text)))
                      .toList(growable: false),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
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
        errors.add('Строка ${i + 1}: формат Текст|cb_data или Текст|url:https://...');
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
      } else if (action.startsWith('http://') || action.startsWith('https://')) {
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

class _AddMiniAppDialog extends StatefulWidget {
  const _AddMiniAppDialog();

  @override
  State<_AddMiniAppDialog> createState() => _AddMiniAppDialogState();
}

class _AddMiniAppDialogState extends State<_AddMiniAppDialog> {
  final _nameController = TextEditingController();
  final _shortNameController = TextEditingController();
  final _urlController = TextEditingController(text: 'https://');
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _shortNameController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить мини-приложение'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            TextField(
              controller: _shortNameController,
              decoration: const InputDecoration(
                labelText: 'Short name',
                hintText: 'например, calorie_calc',
              ),
            ),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://miniapp.example.com',
              ),
            ),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Описание'),
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
            final name = _nameController.text.trim();
            final shortName = _shortNameController.text.trim();
            final url = _urlController.text.trim();
            if (name.isEmpty || shortName.isEmpty || url.isEmpty) return;
            Navigator.pop(
              context,
              _MiniAppCreateResult(
                name: name,
                shortName: shortName,
                url: url,
                description: _descriptionController.text.trim().isEmpty
                    ? null
                    : _descriptionController.text.trim(),
              ),
            );
          },
          child: const Text('Добавить'),
        ),
      ],
    );
  }
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

class _MiniAppCreateResult {
  final String name;
  final String shortName;
  final String url;
  final String? description;
  _MiniAppCreateResult({
    required this.name,
    required this.shortName,
    required this.url,
    this.description,
  });
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}
