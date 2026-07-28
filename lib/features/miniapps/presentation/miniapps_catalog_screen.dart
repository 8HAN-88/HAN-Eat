import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../bots/data/bot_models.dart';
import '../data/miniapp_models.dart';
import '../data/miniapps_service.dart';
import 'miniapp_webview_screen.dart';

class MiniAppsCatalogScreen extends StatefulWidget {
  const MiniAppsCatalogScreen({super.key});

  @override
  State<MiniAppsCatalogScreen> createState() => _MiniAppsCatalogScreenState();
}

class _MiniAppsCatalogScreenState extends State<MiniAppsCatalogScreen> {
  late Future<List<MiniAppItem>> _catalogFuture;
  late Future<List<MiniAppItem>> _myAppsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _catalogFuture = MiniAppsService.fetchCatalog();
      _myAppsFuture = MiniAppsService.fetchMyMiniApps();
    });
  }

  Future<void> _publishMiniApp() async {
    final result = await showDialog<MiniAppCreateRequest>(
      context: context,
      builder: (_) => const _PublishMiniAppDialog(),
    );
    if (result == null) return;
    try {
      await MiniAppsService.createMiniApp(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Мини-приложение опубликовано')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось опубликовать: $e')),
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

  Future<void> _toggleInstall(MiniAppItem app) async {
    try {
      if (app.isInstalled) {
        await MiniAppsService.uninstallMiniApp(app.id);
      } else {
        await MiniAppsService.installMiniApp(app.id);
      }
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Операция не выполнена: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Мини-приложения'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Обновить',
              onPressed: _reload,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Опубликовать своё приложение',
              onPressed: _publishMiniApp,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Каталог'),
              Tab(text: 'Мои'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MiniAppsListTab(
              future: _catalogFuture,
              emptyTitle: 'Каталог пока пуст',
              emptySubtitle:
                  'Опубликуйте первое мини-приложение и установите его в каталог.',
              onOpen: _openMiniApp,
              onToggleInstall: _toggleInstall,
              onRefresh: _reload,
            ),
            _MiniAppsListTab(
              future: _myAppsFuture,
              emptyTitle: 'У вас пока нет мини-приложений',
              emptySubtitle:
                  'Нажмите + вверху, чтобы опубликовать mini app для вашего бота.',
              onOpen: _openMiniApp,
              onToggleInstall: _toggleInstall,
              onRefresh: _reload,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAppsListTab extends StatelessWidget {
  const _MiniAppsListTab({
    required this.future,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onOpen,
    required this.onToggleInstall,
    required this.onRefresh,
  });

  final Future<List<MiniAppItem>> future;
  final String emptyTitle;
  final String emptySubtitle;
  final Future<void> Function(MiniAppItem app) onOpen;
  final Future<void> Function(MiniAppItem app) onToggleInstall;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MiniAppItem>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'Ошибка загрузки mini apps',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: onRefresh,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          );
        }
        final apps = snapshot.data ?? const [];
        if (apps.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.apps_outlined, size: 44),
                  const SizedBox(height: 10),
                  Text(
                    emptyTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    emptySubtitle,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.95,
          ),
          itemCount: apps.length,
          itemBuilder: (context, index) {
            final app = apps[index];
            return _MiniAppCard(
              app: app,
              onOpen: () => onOpen(app),
              onToggleInstall: () => onToggleInstall(app),
            );
          },
        );
      },
    );
  }
}

class _MiniAppCard extends StatelessWidget {
  const _MiniAppCard({
    required this.app,
    required this.onOpen,
    required this.onToggleInstall,
  });

  final MiniAppItem app;
  final VoidCallback onOpen;
  final VoidCallback onToggleInstall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    app.isOfficial ? Icons.verified_rounded : Icons.apps_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const Spacer(),
                if (app.isOfficial)
                  const _Badge(
                    text: 'Official',
                    fg: Colors.blue,
                    bg: Color(0x1A2196F3),
                  )
                else if (app.isOwner)
                  const _Badge(
                    text: 'My app',
                    fg: Colors.orange,
                    bg: Color(0x1AFF9800),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
            if (app.isOwner && !app.isApproved) ...[
              const SizedBox(height: 6),
              _Badge(
                text: app.isRejected ? 'Rejected' : 'Pending review',
                fg: app.isRejected ? Colors.red : Colors.amber.shade900,
                bg: app.isRejected
                    ? const Color(0x1AFF5252)
                    : const Color(0x1AFFC107),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              app.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              app.description?.trim().isNotEmpty == true
                  ? app.description!
                  : 'Без описания',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '@${app.botUsername}',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onToggleInstall,
                    child: Text(app.isInstalled ? 'Удалить' : 'Установить'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onOpen,
                    child: const Text('Открыть'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.fg,
    required this.bg,
  });

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PublishMiniAppDialog extends StatefulWidget {
  const _PublishMiniAppDialog();

  @override
  State<_PublishMiniAppDialog> createState() => _PublishMiniAppDialogState();
}

class _PublishMiniAppDialogState extends State<_PublishMiniAppDialog> {
  final _nameController = TextEditingController();
  final _shortController = TextEditingController();
  final _urlController = TextEditingController(text: 'https://');
  final _descController = TextEditingController();
  int? _selectedBotId;
  late Future<List<BotListItem>> _botsFuture;

  @override
  void initState() {
    super.initState();
    _botsFuture = ApiService.getMyBots();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shortController.dispose();
    _urlController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Публикация mini app'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder<List<BotListItem>>(
                future: _botsFuture,
                builder: (context, snapshot) {
                  final bots = snapshot.data ?? const [];
                  return DropdownButtonFormField<int>(
                    value: _selectedBotId,
                    decoration: const InputDecoration(labelText: 'Бот'),
                    items: bots
                        .map(
                          (b) => DropdownMenuItem<int>(
                            value: b.id,
                            child: Text('${b.name} (@${b.username})'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: snapshot.hasData && bots.isNotEmpty
                        ? (value) => setState(() => _selectedBotId = value)
                        : null,
                  );
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _shortController,
                decoration: const InputDecoration(
                  labelText: 'Short name',
                  hintText: 'например: calorie_calc',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://miniapp.example.com',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Описание',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final botId = _selectedBotId;
            final name = _nameController.text.trim();
            final shortName = _shortController.text.trim();
            final url = _urlController.text.trim();
            if (botId == null ||
                name.isEmpty ||
                shortName.isEmpty ||
                url.isEmpty) {
              return;
            }
            Navigator.pop(
              context,
              MiniAppCreateRequest(
                botId: botId,
                name: name,
                shortName: shortName,
                url: url,
                description: _descController.text.trim().isEmpty
                    ? null
                    : _descController.text.trim(),
              ),
            );
          },
          child: const Text('Опубликовать'),
        ),
      ],
    );
  }
}
