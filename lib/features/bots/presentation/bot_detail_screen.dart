import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/api_service.dart';
import '../data/bot_models.dart';

/// Экран управления ботом (BotFather detail)
class BotDetailScreen extends StatefulWidget {
  const BotDetailScreen({super.key, required this.botId, required this.botUsername});

  final int botId;
  final String botUsername;

  @override
  State<BotDetailScreen> createState() => _BotDetailScreenState();
}

class _BotDetailScreenState extends State<BotDetailScreen> {
  BotResponse? _bot;
  bool _isLoading = true;
  List<BotCommandCreate> _commands = [];
  final _webhookController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBot();
  }

  Future<void> _loadBot() async {
    setState(() => _isLoading = true);
    try {
      final list = await ApiService.getMyBots();
      final item = list.firstWhere((b) => b.id == widget.botId);
      setState(() {
        _bot = BotResponse(
          id: item.id,
          name: item.name,
          username: item.username,
          botToken: '••••••••••••••••••••••••••••••••',
          description: item.description,
          shortDescription: item.shortDescription,
        );
      });
      await _loadCommands();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCommands() async {
    try {
      final cmds = await ApiService.getBotCommands(widget.botId);
      if (mounted) setState(() => _commands = cmds);
    } catch (_) {}
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
        BotCommandCreate(command: result.command, description: result.description),
      );
      await _loadCommands();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _copyToken() async {
    if (_bot == null) return;
    // В реальном сценарии токен приходит только при создании.
    // Здесь показываем заглушку. Для продвинутого варианта нужно хранить токен локально при создании.
    await Clipboard.setData(const ClipboardData(text: 'Токен показывается только при создании'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Токен показывается только один раз при создании')),
      );
    }
  }

  Future<void> _saveWebhook() async {
    final url = _webhookController.text.trim();
    try {
      // placeholder — реальный вызов будет после доработки ApiService
      // await http.post(...);
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
                        subtitle: const Text('Показывается только при создании'),
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
                    TextField(
                      controller: _webhookController,
                      decoration: const InputDecoration(
                        labelText: 'https://your-server.com/webhook',
                        hintText: 'URL для получения обновлений',
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _saveWebhook,
                      child: const Text('Сохранить webhook'),
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
                            subtitle: Text(c.description),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteCommand(c.command),
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
    // TODO: Загрузить список чатов пользователя и показать выбор
    // Для MVP показываем заглушку
    final convId = await showDialog<int>(
      context: context,
      builder: (_) => const _SelectChatDialog(),
    );
    if (convId == null) return;

    try {
      // TODO: Реальный вызов API
      // await http.post(.../bots/{botId}/add-to-chat, {conversation_id: convId})
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Бот добавлен в чат #$convId (демо)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }
}

class _SelectChatDialog extends StatelessWidget {
  const _SelectChatDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Выберите чат'),
      content: const Text('Здесь будет список ваших чатов и каналов'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(context, 42),
          child: const Text('Добавить (демо)'),
        ),
      ],
    );
  }
}

class _AddCommandDialog extends StatefulWidget {
  const _AddCommandDialog({super.key});

  @override
  State<_AddCommandDialog> createState() => _AddCommandDialogState();
}

class _AddCommandDialogState extends State<_AddCommandDialog> {
  final _cmdController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _cmdController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить команду'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _cmdController,
            decoration: const InputDecoration(labelText: 'Команда (без /)'),
          ),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(labelText: 'Описание'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (_cmdController.text.trim().isEmpty || _descController.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _CommandResult(
                command: _cmdController.text.trim(),
                description: _descController.text.trim(),
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
  _CommandResult({required this.command, required this.description});
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
