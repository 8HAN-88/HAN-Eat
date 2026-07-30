import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/api_service.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/telegram_ui.dart';
import '../data/bot_models.dart';
import '../data/bot_token_storage.dart';
import 'bot_detail_screen.dart';

/// «Мои боты» — аналог списка ботов в @BotFather.
class MyBotsScreen extends StatefulWidget {
  const MyBotsScreen({super.key});

  @override
  State<MyBotsScreen> createState() => _MyBotsScreenState();
}

class _MyBotsScreenState extends State<MyBotsScreen> {
  bool _isLoading = false;
  String? _error;
  List<BotListItem> _bots = const [];

  @override
  void initState() {
    super.initState();
    _loadBots();
  }

  Future<void> _loadBots() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getMyBots();
      if (!mounted) return;
      setState(() => _bots = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openBot(
    BotListItem bot, {
    String? initialToken,
    bool showTokenSheet = false,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BotDetailScreen(
          botId: bot.id,
          botUsername: bot.username,
          initialToken: initialToken,
          showTokenOnOpen: showTokenSheet,
        ),
      ),
    );
    if (mounted) _loadBots();
  }

  Future<void> _createBot() async {
    final result = await showDialog<_BotCreateResult>(
      context: context,
      builder: (_) => const _CreateBotDialog(),
    );
    if (result == null) return;

    setState(() => _isLoading = true);
    try {
      final created = await ApiService.createBot(
        BotCreateRequest(
          name: result.name,
          username: result.username,
          description: result.description,
          shortDescription: result.shortDescription,
          commands: const [],
        ),
      );
      await BotTokenStorage.saveToken(created.id, created.botToken);
      if (!mounted) return;
      await _openBot(
        BotListItem(
          id: created.id,
          name: created.name,
          username: created.username,
          description: created.description,
          shortDescription: created.shortDescription,
        ),
        initialToken: created.botToken,
        showTokenSheet: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать бота: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                      tooltip: 'Назад',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Мои боты',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.8,
                                ),
                      ),
                    ),
                    NeoCircleAction(
                      icon: Icons.add_rounded,
                      tooltip: 'Создать бота',
                      onPressed: _createBot,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(
                'Как в @BotFather: создайте бота, получите токен, '
                'настройте команды и мини-приложения.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _bots.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _bots.isEmpty) {
      return AppEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Не удалось загрузить',
        subtitle: _error,
        action: FilledButton(
          onPressed: _loadBots,
          child: const Text('Повторить'),
        ),
      );
    }
    if (_bots.isEmpty) {
      return AppEmptyState(
        icon: Icons.smart_toy_outlined,
        title: 'Ботов пока нет',
        subtitle:
            'Создайте бота — как через @BotFather. Потом можно добавить команды и мини-приложения.',
        action: FilledButton.icon(
          onPressed: _createBot,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Создать бота'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBots,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
        itemCount: _bots.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final bot = _bots[index];
          final scheme = Theme.of(context).colorScheme;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _openBot(bot),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.smart_toy_rounded,
                          color: scheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bot.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '@${bot.username}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                          if ((bot.description ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              bot.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.outline),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CreateBotDialog extends StatefulWidget {
  const _CreateBotDialog();

  @override
  State<_CreateBotDialog> createState() => _CreateBotDialogState();
}

class _CreateBotDialogState extends State<_CreateBotDialog> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _descController = TextEditingController();
  String? _usernameError;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _aboutController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Создать бота'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Как в Telegram: укажите имя и username, заканчивающийся на bot.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Имя бота',
                hintText: 'например: Погода',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _usernameController,
              onChanged: (value) {
                setState(() => _usernameError = validateBotUsername(value));
              },
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: 'weather_bot',
                prefixText: '@',
                errorText: _usernameError,
                helperText: '5–32 символа, заканчивается на bot',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _aboutController,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'About (коротко)',
                hintText: 'до 120 символов',
              ),
            ),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (опционально)',
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
            final name = _nameController.text.trim();
            final username = normalizeBotUsername(_usernameController.text);
            final err = validateBotUsername(username);
            if (name.isEmpty) return;
            if (err != null) {
              setState(() => _usernameError = err);
              return;
            }
            Navigator.pop(
              context,
              _BotCreateResult(
                name: name,
                username: username,
                shortDescription: _aboutController.text.trim().isEmpty
                    ? null
                    : _aboutController.text.trim(),
                description: _descController.text.trim().isEmpty
                    ? null
                    : _descController.text.trim(),
              ),
            );
          },
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

class _BotCreateResult {
  const _BotCreateResult({
    required this.name,
    required this.username,
    this.description,
    this.shortDescription,
  });

  final String name;
  final String username;
  final String? description;
  final String? shortDescription;
}
