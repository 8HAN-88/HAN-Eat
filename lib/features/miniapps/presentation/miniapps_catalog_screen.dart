import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../services/api_service.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/telegram_ui.dart';
import '../../bots/data/bot_models.dart';
import '../data/miniapp_models.dart';
import '../data/miniapps_service.dart';
import 'miniapp_webview_screen.dart';

/// Раздел мини-приложений как в Telegram: каталог + публикация своих.
class MiniAppsCatalogScreen extends StatefulWidget {
  const MiniAppsCatalogScreen({super.key});

  @override
  State<MiniAppsCatalogScreen> createState() => _MiniAppsCatalogScreenState();
}

class _MiniAppsCatalogScreenState extends State<MiniAppsCatalogScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  int _lastTabIndex = 0;
  String _searchQuery = '';
  bool _loading = true;
  String? _error;
  List<MiniAppItem> _catalog = const [];
  List<MiniAppItem> _myApps = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
    _reload();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == _lastTabIndex) return;
    _lastTabIndex = _tabs.index;
    AppHaptics.selection();
    setState(() {});
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await MiniAppsService.fetchCatalog(
        query: _searchQuery,
        sort: 'default',
      );
      final myApps = await MiniAppsService.fetchMyMiniApps();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _myApps = myApps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), _reload);
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
    _reload();
  }

  List<MiniAppItem> get _visibleApps {
    final q = _searchQuery.trim().toLowerCase();
    bool matches(MiniAppItem app) {
      if (q.isEmpty) return true;
      final hay = [
        app.name,
        app.description ?? '',
        app.botUsername,
        app.shortName,
        app.categoryLabel,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }

    if (_tabs.index == 1) {
      return _myApps.where(matches).toList(growable: false);
    }
    final items = _catalog.where(matches).toList();
    items.sort((a, b) {
      if (a.isInstalled != b.isInstalled) {
        return a.isInstalled ? -1 : 1;
      }
      final aLaunch = a.lastLaunchedAt;
      final bLaunch = b.lastLaunchedAt;
      if (aLaunch != null || bLaunch != null) {
        if (aLaunch == null) return 1;
        if (bLaunch == null) return -1;
        return bLaunch.compareTo(aLaunch);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
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
        const SnackBar(
          content: Text('Мини-приложение отправлено на модерацию'),
        ),
      );
      _tabs.animateTo(1);
      await _reload();
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
            subtitle: '@${app.botUsername}',
            url: launch.url,
            initData: launch.initData,
            initDataUnsafe: launch.initDataUnsafe,
          ),
        ),
      );
      if (mounted) _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть: $e')),
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
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Операция не выполнена: $e')),
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
          title: 'Открыть',
          subtitle: '@${app.botUsername}',
          onTap: () => _openMiniApp(app),
        ),
        TelegramActionSheetAction(
          icon: app.isInstalled
              ? Icons.remove_circle_outline_rounded
              : Icons.download_rounded,
          title: app.isInstalled ? 'Удалить из установленных' : 'Установить',
          onTap: () => _toggleInstall(app),
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
            _MiniAppsNeoHeader(
              controller: _tabs,
              searchController: _searchController,
              searchQuery: _searchQuery,
              onSearchChanged: _onSearchChanged,
              onClearSearch: _clearSearch,
              onCreate: _publishMiniApp,
              onRefresh: _reload,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _catalog.isEmpty && _myApps.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _catalog.isEmpty && _myApps.isEmpty) {
      return AppEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Не удалось загрузить',
        subtitle: _error,
        action: FilledButton(
          onPressed: _reload,
          child: const Text('Повторить'),
        ),
      );
    }

    final apps = _visibleApps;
    if (apps.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.55,
              child: AppEmptyState(
                icon: _tabs.index == 1
                    ? Icons.publish_outlined
                    : Icons.apps_outlined,
                title: _emptyTitle,
                subtitle: _emptySubtitle,
                action: _tabs.index == 1
                    ? FilledButton.icon(
                        onPressed: _publishMiniApp,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Опубликовать'),
                      )
                    : (_searchQuery.isNotEmpty
                        ? TextButton(
                            onPressed: _clearSearch,
                            child: const Text('Очистить поиск'),
                          )
                        : null),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
        itemCount: apps.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final app = apps[index];
          return _MiniAppRow(
            app: app,
            showOwnerStatus: _tabs.index == 1 || app.isOwner,
            onOpen: () => _openMiniApp(app),
            onMore: () => _showAppActions(app),
          );
        },
      ),
    );
  }

  String get _emptyTitle {
    if (_searchQuery.trim().isNotEmpty) return 'Ничего не найдено';
    if (_tabs.index == 1) return 'Своих приложений нет';
    return 'Каталог пока пуст';
  }

  String get _emptySubtitle {
    if (_searchQuery.trim().isNotEmpty) {
      return 'Попробуйте другой запрос.';
    }
    if (_tabs.index == 1) {
      return 'Опубликуйте mini app для своего бота — после проверки оно появится в каталоге.';
    }
    return 'Здесь будут мини-приложения ботов. Нажмите +, чтобы выложить своё.';
  }
}

class _MiniAppsNeoHeader extends StatelessWidget {
  const _MiniAppsNeoHeader({
    required this.controller,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onCreate,
    required this.onRefresh,
  });

  final TabController controller;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Мини-приложения',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                        ),
                  ),
                ),
                NeoCircleAction(
                  icon: Icons.add_rounded,
                  tooltip: 'Опубликовать своё',
                  onPressed: onCreate,
                ),
                const SizedBox(width: 8),
                NeoCircleAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Обновить',
                  onPressed: onRefresh,
                ),
              ],
            ),
            const SizedBox(height: 18),
            NeoUnderlineTabs(
              controller: controller,
              padding: EdgeInsets.zero,
              tabs: const [
                Tab(text: 'Каталог'),
                Tab(text: 'Мои'),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Поиск в каталоге',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить',
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: scheme.surfaceContainer.withValues(alpha: 0.7),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.46),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.46),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAppRow extends StatelessWidget {
  const _MiniAppRow({
    required this.app,
    required this.onOpen,
    required this.onMore,
    this.showOwnerStatus = false,
  });

  final MiniAppItem app;
  final VoidCallback onOpen;
  final VoidCallback onMore;
  final bool showOwnerStatus;

  String? get _statusLabel {
    if (!showOwnerStatus || app.isApproved) return null;
    if (app.isRejected) return 'Отклонено';
    return 'На проверке';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _statusLabel;
    final desc = (app.description ?? '').trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onMore,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                    width: 0.7,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: app.iconUrl != null && app.iconUrl!.trim().isNotEmpty
                    ? Image.network(
                        app.iconUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.apps_rounded,
                          color: scheme.primary,
                        ),
                      )
                    : Icon(Icons.apps_rounded, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc.isNotEmpty ? desc : 'Без описания',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        app.categoryLabel,
                        '@${app.botUsername}',
                        if (app.isInstalled) 'Установлено',
                        if (status != null) status,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: status != null && !app.isApproved
                                ? (app.isRejected
                                    ? scheme.error
                                    : scheme.tertiary)
                                : scheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Действия',
                onPressed: onMore,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
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
  String _category = 'tools';
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
      title: const Text('Опубликовать мини-приложение'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Как в Telegram: привяжите web-приложение к своему боту. После проверки оно появится в каталоге.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 14),
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
                  labelText: 'Короткое имя',
                  hintText: 'например: my_shop',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Категория'),
                items: MiniAppCategory.known
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: c.id,
                        child: Text(c.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _category = value);
                },
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
                decoration: const InputDecoration(labelText: 'Описание'),
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
                category: _category,
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
