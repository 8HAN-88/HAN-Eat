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

/// Раздел мини-приложений: каталог, установленные и свои — в одном хабе.
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
  String _category = '';
  bool _loading = true;
  String? _error;
  List<MiniAppItem> _catalog = const [];
  List<MiniAppItem> _myApps = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
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
        category: _category.isEmpty ? null : _category,
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
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      _reload();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
    _reload();
  }

  void _selectCategory(String id) {
    if (_category == id) return;
    AppHaptics.selection();
    setState(() => _category = id);
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

    switch (_tabs.index) {
      case 1:
        return _catalog.where((a) => a.isInstalled && matches(a)).toList();
      case 2:
        return _myApps.where(matches).toList();
      default:
        // «Для вас»: официальные и одобренные сверху; фильтр категории уже с API.
        final items = _catalog.where(matches).toList();
        items.sort((a, b) {
          if (a.isOfficial != b.isOfficial) {
            return a.isOfficial ? -1 : 1;
          }
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
        const SnackBar(content: Text('Мини-приложение отправлено на публикацию')),
      );
      _tabs.animateTo(2);
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
            subtitle: app.description ?? '@${app.botUsername}',
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
          subtitle: app.categoryLabel,
          onTap: () => _openMiniApp(app),
        ),
        TelegramActionSheetAction(
          icon: app.isInstalled
              ? Icons.remove_circle_outline_rounded
              : Icons.download_rounded,
          title: app.isInstalled ? 'Убрать из установленных' : 'Установить',
          onTap: () => _toggleInstall(app),
        ),
      ],
    );
  }

  void _showMoreMenu() {
    showTelegramActionSheet<void>(
      context: context,
      title: 'Мини-приложения',
      actions: [
        TelegramActionSheetAction(
          icon: Icons.refresh_rounded,
          title: 'Обновить',
          onTap: _reload,
        ),
        TelegramActionSheetAction(
          icon: Icons.publish_outlined,
          title: 'Опубликовать своё',
          subtitle: 'Для бота, которым вы управляете',
          onTap: _publishMiniApp,
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
              onMore: _showMoreMenu,
              category: _category,
              onCategorySelected: _selectCategory,
              showCategories: _tabs.index != 2,
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
                icon: _emptyIcon,
                title: _emptyTitle,
                subtitle: _emptySubtitle,
                action: _tabs.index == 2
                    ? FilledButton.icon(
                        onPressed: _publishMiniApp,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Опубликовать'),
                      )
                    : (_searchQuery.isNotEmpty || _category.isNotEmpty)
                        ? TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _category = '';
                              });
                              _reload();
                            },
                            child: const Text('Сбросить фильтры'),
                          )
                        : null,
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
            showOwnerStatus: _tabs.index == 2 || app.isOwner,
            onOpen: () => _openMiniApp(app),
            onMore: () => _showAppActions(app),
          );
        },
      ),
    );
  }

  IconData get _emptyIcon {
    switch (_tabs.index) {
      case 1:
        return Icons.download_done_outlined;
      case 2:
        return Icons.construction_outlined;
      default:
        return Icons.apps_outlined;
    }
  }

  String get _emptyTitle {
    if (_searchQuery.trim().isNotEmpty || _category.isNotEmpty) {
      return 'Ничего не найдено';
    }
    switch (_tabs.index) {
      case 1:
        return 'Пока нет установленных';
      case 2:
        return 'Своих приложений нет';
      default:
        return 'Каталог пока пуст';
    }
  }

  String get _emptySubtitle {
    if (_searchQuery.trim().isNotEmpty || _category.isNotEmpty) {
      return 'Попробуйте другой запрос или категорию.';
    }
    switch (_tabs.index) {
      case 1:
        return 'Откройте приложение из раздела «Для вас» — оно появится здесь.';
      case 2:
        return 'Опубликуйте mini app для своего бота: оно пройдёт проверку и появится в каталоге.';
      default:
        return 'Здесь появятся кухонные инструменты HAN и приложения сообщества.';
    }
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
    required this.onMore,
    required this.category,
    required this.onCategorySelected,
    required this.showCategories,
  });

  final TabController controller;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onCreate;
  final VoidCallback onMore;
  final String category;
  final ValueChanged<String> onCategorySelected;
  final bool showCategories;

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
                  tooltip: 'Опубликовать',
                  onPressed: onCreate,
                ),
                const SizedBox(width: 8),
                NeoCircleAction(
                  icon: Icons.more_horiz_rounded,
                  tooltip: 'Ещё',
                  onPressed: onMore,
                ),
              ],
            ),
            const SizedBox(height: 18),
            NeoUnderlineTabs(
              controller: controller,
              padding: EdgeInsets.zero,
              tabs: const [
                Tab(text: 'Для вас'),
                Tab(text: 'Установленные'),
                Tab(text: 'Мои'),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Поиск приложений',
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
            if (showCategories) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final cat in [
                      MiniAppCategory.all,
                      ...MiniAppCategory.known,
                    ]) ...[
                      NeoFilterChip(
                        label: cat.label,
                        selected: category == cat.id,
                        onTap: () => onCategorySelected(cat.id),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
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

  IconData get _icon {
    switch ((app.category ?? '').toLowerCase()) {
      case 'recipes':
        return Icons.restaurant_menu_rounded;
      case 'calories':
        return Icons.local_fire_department_rounded;
      case 'planning':
        return Icons.calendar_month_rounded;
      case 'shopping':
        return Icons.shopping_basket_rounded;
      case 'games':
        return Icons.sports_esports_rounded;
      case 'utils':
        return Icons.handyman_rounded;
      default:
        return app.isOfficial ? Icons.verified_rounded : Icons.apps_rounded;
    }
  }

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
                          _icon,
                          color: scheme.primary,
                        ),
                      )
                    : Icon(_icon, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (app.isOfficial) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: scheme.primary,
                          ),
                        ],
                      ],
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
  String _category = 'utils';
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
      title: const Text('Публикация мини-приложения'),
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
                  labelText: 'Короткое имя',
                  hintText: 'например: calorie_calc',
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
