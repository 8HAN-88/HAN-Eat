import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../data/bot_models.dart';
import '../data/bot_token_storage.dart';
import 'bot_detail_screen.dart';

/// Экран «Мои боты» (аналог BotFather)
class MyBotsScreen extends StatefulWidget {
  const MyBotsScreen({super.key});

  @override
  State<MyBotsScreen> createState() => _MyBotsScreenState();
}

class _MyBotsScreenState extends State<MyBotsScreen> {
  bool _isLoading = false;
  List<_BotItem> _bots = [];

  @override
  void initState() {
    super.initState();
    _loadBots();
  }

  Future<void> _loadBots() async {
    setState(() => _isLoading = true);
    try {
      final list = await ApiService.getMyBots();
      setState(() {
        _bots = list
            .map((b) => _BotItem(id: b.id, name: b.name, username: b.username))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки ботов: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createBot() async {
    final result = await showDialog<_BotCreateResult>(
      context: context,
      builder: (_) => const _CreateBotDialog(),
    );
    if (result == null) return;

    setState(() => _isLoading = true);
    try {
      final req = BotCreateRequest(
        name: result.name,
        username: result.username,
        description: result.description,
        commands: const [], // MVP: команды добавляются позже в BotDetailScreen
      );
      final created = await ApiService.createBot(req);

      // Сохраняем токен локально, чтобы его можно было скопировать позже
      await BotTokenStorage.saveToken(created.id, created.botToken);

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BotDetailScreen(
            botId: created.id,
            botUsername: created.username,
            initialToken: created.botToken,
          ),
        ),
      );
      _loadBots();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка создания бота: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои боты'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createBot,
            tooltip: 'Создать бота',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bots.isEmpty
              ? _EmptyState(onCreate: _createBot)
              : ListView.separated(
                  itemCount: _bots.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final bot = _bots[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.smart_toy)),
                      title: Text(bot.name),
                      subtitle: Text('@${bot.username}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BotDetailScreen(
                              botId: bot.id,
                              botUsername: bot.username,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createBot,
        icon: const Icon(Icons.add),
        label: const Text('Создать бота'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('У вас пока нет ботов', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            const Text(
              'Создайте бота, чтобы он мог отвечать в чатах и запускать мини-приложения',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Создать бота'),
            ),
          ],
        ),
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
  final _descController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
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
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Имя бота (например, Погода)'),
            ),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username (например, weather_bot)'),
            ),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Описание (опционально)'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            const Text(
              'После создания вы получите токен — сохраните его сразу. Он показывается только один раз.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (_nameController.text.trim().isEmpty || _usernameController.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _BotCreateResult(
                name: _nameController.text.trim(),
                username: _usernameController.text.trim(),
                description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
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
  final String name;
  final String username;
  final String? description;
  _BotCreateResult({required this.name, required this.username, this.description});
}

class _BotItem {
  final int id;
  final String name;
  final String username;
  _BotItem({required this.id, required this.name, required this.username});
}
