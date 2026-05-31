// Экран управления каналами (поиск, сортировка, фильтры)
import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/theme/app_card_decorations.dart';
import '../../../services/channel_service.dart';
import '../../../widgets/channel_list_badges.dart';
import '../../../widgets/app_empty_state.dart';

class ChannelsManagementScreen extends ConsumerStatefulWidget {
  const ChannelsManagementScreen({super.key});

  @override
  ConsumerState<ChannelsManagementScreen> createState() =>
      _ChannelsManagementScreenState();
}

class _SortOption {
  const _SortOption(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}

const _sortOptions = [
  _SortOption('popular', 'Популярные', Icons.local_fire_department_outlined),
  _SortOption('new', 'Новые', Icons.fiber_new_outlined),
  _SortOption('activity', 'Активные', Icons.bolt_outlined),
  _SortOption('posts', 'По постам', Icons.article_outlined),
  _SortOption('members', 'Подписчики', Icons.people_outline),
];

class _ChannelsManagementScreenState
    extends ConsumerState<ChannelsManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Channel> _ownedChannels = [];
  List<Channel> _catalogChannels = [];
  bool _isLoading = false;
  String _sortBy = 'popular';
  String? _selectedCategory;
  bool? _hasRecipes;
  int? _minSubscribers;
  int? _minPosts;
  final List<String> _availableCategories = [
    'Итальянская',
    'Азиатская',
    'Веган',
    'ЗОЖ',
    'Выпечка',
    'Напитки',
    'Завтраки',
    'Ужины',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final q = GoRouterState.of(context).uri.queryParameters['search'];
      if (q != null && q.trim().isNotEmpty) {
        _searchController.text = q.trim();
      }
      _loadChannels();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final search = _searchController.text.trim();
      final searchParam = search.isEmpty ? null : search;

      final mineResponse = await ChannelService.listChannels(
        limit: 50,
        offset: 0,
        mine: true,
        search: searchParam,
      );
      final catalogResponse = await ChannelService.listChannels(
        limit: 50,
        offset: 0,
        search: searchParam,
        catalog: true,
        category: _selectedCategory,
        sort: _sortBy,
        hasRecipes: _hasRecipes,
        minSubscribers: _minSubscribers,
        minPosts: _minPosts,
      );

      final owned = mineResponse.items;
      final mineIds = owned.map((c) => c.id).toSet();
      final catalog = catalogResponse.items.where((c) => !mineIds.contains(c.id)).toList();
      setState(() {
        _ownedChannels = owned;
        _catalogChannels = catalog;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить каналы'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setSort(String value) {
    if (_sortBy == value) return;
    setState(() => _sortBy = value);
    _loadChannels();
  }

  bool get _hasActiveFilters =>
      _selectedCategory != null ||
      _hasRecipes != null ||
      _minSubscribers != null ||
      _minPosts != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление каналами'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ManagementHeader(
            scheme: scheme,
            textTheme: textTheme,
            searchController: _searchController,
            sortBy: _sortBy,
            onSortChanged: _setSort,
            selectedCategory: _selectedCategory,
            hasRecipes: _hasRecipes,
            hasAdvancedFilters: _minSubscribers != null || _minPosts != null,
            hasActiveFilters: _hasActiveFilters,
            onSearch: _loadChannels,
            onCategoryTap: _showCategoryPicker,
            onRecipesTap: _cycleRecipesFilter,
            onAdvancedTap: _showAdvancedFilters,
            onClearFilters: _clearFilters,
          ),
          Expanded(child: _buildChannelList(scheme)),
        ],
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _hasRecipes = null;
      _minSubscribers = null;
      _minPosts = null;
    });
    _loadChannels();
  }

  void _cycleRecipesFilter() {
    setState(() {
      if (_hasRecipes == null) {
        _hasRecipes = true;
      } else if (_hasRecipes == true) {
        _hasRecipes = false;
      } else {
        _hasRecipes = null;
      }
    });
    _loadChannels();
  }

  Widget _buildChannelList(ColorScheme scheme) {
    if (_isLoading && _ownedChannels.isEmpty && _catalogChannels.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_ownedChannels.isEmpty && _catalogChannels.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadChannels,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyState(
                icon: Icons.hub_outlined,
                title: 'Каналы не найдены',
                subtitle: _hasActiveFilters || _searchController.text.isNotEmpty
                    ? 'Попробуйте изменить фильтры или запрос'
                    : 'Создайте канал или зайдите позже',
                action: (_hasActiveFilters || _searchController.text.isNotEmpty)
                    ? TextButton(
                        onPressed: () {
                          _searchController.clear();
                          _clearFilters();
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
      onRefresh: _loadChannels,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_ownedChannels.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text(
                'Мои каналы',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            ..._ownedChannels.map(
              (channel) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ManagementChannelCard(channel: channel),
              ),
            ),
          ],
          if (_catalogChannels.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(4, _ownedChannels.isNotEmpty ? 8 : 4, 4, 8),
              child: Text(
                'Каталог',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            ..._catalogChannels.map(
              (channel) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ManagementChannelCard(channel: channel),
              ),
            ),
          ],
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  void _showCategoryPicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Категория',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.grid_view_outlined),
                title: const Text('Все категории'),
                trailing: _selectedCategory == null
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  setState(() => _selectedCategory = null);
                  Navigator.pop(context);
                  _loadChannels();
                },
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableCategories.length,
                  itemBuilder: (context, i) {
                    final category = _availableCategories[i];
                    final selected = _selectedCategory == category;
                    return ListTile(
                      title: Text(category),
                      trailing: selected
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () {
                        setState(() => _selectedCategory = category);
                        Navigator.pop(context);
                        _loadChannels();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAdvancedFilters() {
    final subsController =
        TextEditingController(text: _minSubscribers?.toString() ?? '');
    final postsController =
        TextEditingController(text: _minPosts?.toString() ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Text(
                        'Дополнительные фильтры',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Мин. подписчиков',
                          prefixIcon: Icon(Icons.people_outline),
                        ),
                        keyboardType: TextInputType.number,
                        controller: subsController,
                        onChanged: (value) {
                          setModalState(() {
                            _minSubscribers =
                                value.isEmpty ? null : int.tryParse(value);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Мин. постов',
                          prefixIcon: Icon(Icons.article_outlined),
                        ),
                        keyboardType: TextInputType.number,
                        controller: postsController,
                        onChanged: (value) {
                          setModalState(() {
                            _minPosts =
                                value.isEmpty ? null : int.tryParse(value);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModalState(() {
                                  _minSubscribers = null;
                                  _minPosts = null;
                                });
                              },
                              child: const Text('Сбросить'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _loadChannels();
                              },
                              child: const Text('Применить'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      subsController.dispose();
      postsController.dispose();
    });
  }
}

class _ManagementHeader extends StatelessWidget {
  const _ManagementHeader({
    required this.scheme,
    required this.textTheme,
    required this.searchController,
    required this.sortBy,
    required this.onSortChanged,
    required this.selectedCategory,
    required this.hasRecipes,
    required this.hasAdvancedFilters,
    required this.hasActiveFilters,
    required this.onSearch,
    required this.onCategoryTap,
    required this.onRecipesTap,
    required this.onAdvancedTap,
    required this.onClearFilters,
  });

  final ColorScheme scheme;
  final TextTheme textTheme;
  final TextEditingController searchController;
  final String sortBy;
  final ValueChanged<String> onSortChanged;
  final String? selectedCategory;
  final bool? hasRecipes;
  final bool hasAdvancedFilters;
  final bool hasActiveFilters;
  final VoidCallback onSearch;
  final VoidCallback onCategoryTap;
  final VoidCallback onRecipesTap;
  final VoidCallback onAdvancedTap;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final recipesLabel = hasRecipes == null
        ? 'Все каналы'
        : hasRecipes!
            ? 'С рецептами'
            : 'Без рецептов';

    return Material(
      color: scheme.surface,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Поиск каналов…',
                  prefixIcon: Icon(Icons.search_rounded, color: scheme.primary),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            searchController.clear();
                            onSearch();
                          },
                        )
                      : null,
                ),
                onSubmitted: (_) => onSearch(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 6),
              child: Text(
                'Сортировка',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _sortOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final opt = _sortOptions[index];
                  final selected = sortBy == opt.value;
                  return FilterChip(
                    label: Text(opt.label),
                    avatar: Icon(
                      opt.icon,
                      size: 18,
                      color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                    ),
                    showCheckmark: false,
                    selected: selected,
                    onSelected: (_) => onSortChanged(opt.value),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    labelStyle: textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 6),
              child: Text(
                'Фильтры',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  FilterChip(
                    label: Text(selectedCategory ?? 'Категория'),
                    avatar: Icon(
                      Icons.category_outlined,
                      size: 18,
                      color: selectedCategory != null
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    showCheckmark: false,
                    selected: selectedCategory != null,
                    onSelected: (_) => onCategoryTap(),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(recipesLabel),
                    avatar: Icon(
                      Icons.restaurant_menu_outlined,
                      size: 18,
                      color: hasRecipes != null
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    showCheckmark: false,
                    selected: hasRecipes != null,
                    onSelected: (_) => onRecipesTap(),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Ещё'),
                    avatar: Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: hasAdvancedFilters
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    showCheckmark: false,
                    selected: hasAdvancedFilters,
                    onSelected: (_) => onAdvancedTap(),
                  ),
                  if (hasActiveFilters) ...[
                    const SizedBox(width: 8),
                    ActionChip(
                      label: const Text('Сбросить'),
                      avatar: Icon(Icons.filter_alt_off_outlined, size: 18, color: scheme.error),
                      onPressed: onClearFilters,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ManagementChannelCard extends StatelessWidget {
  const _ManagementChannelCard({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppElevatedCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            context.push(ChannelDetailRoute.pathFor(channel.id));
          },
          borderRadius: BorderRadius.circular(AppCardDecorations.defaultRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  backgroundImage: channel.avatarUrl != null
                      ? NetworkImage(channel.avatarUrl!)
                      : null,
                  child: channel.avatarUrl == null
                      ? Text(
                          channel.name.isNotEmpty
                              ? channel.name[0].toUpperCase()
                              : '?',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      ChannelListBadges(channel: channel),
                      if (channel.description != null &&
                          channel.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          channel.description!,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _StatChip(
                            icon: Icons.article_outlined,
                            label: '${channel.postsCount} постов',
                          ),
                          _StatChip(
                            icon: Icons.people_outline,
                            label: '${channel.membersCount} участников',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
