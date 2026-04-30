// Экран управления каналами (поиск, сортировка, фильтры)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/channel_service.dart';
import 'channel_detail_screen.dart';

class ChannelsManagementScreen extends ConsumerStatefulWidget {
  const ChannelsManagementScreen({Key? key}) : super(key: key);
  
  @override
  ConsumerState<ChannelsManagementScreen> createState() => _ChannelsManagementScreenState();
}

class _ChannelsManagementScreenState extends ConsumerState<ChannelsManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Channel> _channels = [];
  bool _isLoading = false;
  String _sortBy = 'popular'; // popular, new, members, activity, posts
  String? _selectedCategory;
  bool? _hasRecipes; // true = только с рецептами, false = без рецептов, null = все
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
    _loadChannels();
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
      final response = await ChannelService.listChannels(
        limit: 50,
        offset: 0,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        catalog: true, // Каталог всех каналов
        category: _selectedCategory,
        sort: _sortBy,
        hasRecipes: _hasRecipes,
        minSubscribers: _minSubscribers,
        minPosts: _minPosts,
      );
      
      setState(() {
        _channels = response.items;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки каналов: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление каналами'),
      ),
      body: Column(
        children: [
          // Поиск
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск каналов...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadChannels();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onSubmitted: (_) => _loadChannels(),
            ),
          ),
          // Сортировка
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'popular',
                  label: Text('Популярные'),
                ),
                ButtonSegment(
                  value: 'new',
                  label: Text('Новые'),
                ),
                ButtonSegment(
                  value: 'activity',
                  label: Text('Активные'),
                ),
                ButtonSegment(
                  value: 'posts',
                  label: Text('По постам'),
                ),
                ButtonSegment(
                  value: 'members',
                  label: Text('По подписчикам'),
                ),
              ],
              selected: {_sortBy},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _sortBy = newSelection.first;
                });
                _loadChannels();
              },
            ),
          ),
          // Фильтры
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Фильтр по категории
                FilterChip(
                  label: Text(_selectedCategory ?? 'Все категории'),
                  selected: _selectedCategory != null,
                  onSelected: (selected) {
                    if (!selected) {
                      setState(() => _selectedCategory = null);
                      _loadChannels();
                    } else {
                      _showCategoryPicker();
                    }
                  },
                ),
                // Фильтр по рецептам
                FilterChip(
                  label: Text(_hasRecipes == null 
                      ? 'Все каналы'
                      : _hasRecipes == true 
                          ? 'С рецептами'
                          : 'Без рецептов'),
                  selected: _hasRecipes != null,
                  onSelected: (selected) {
                    setState(() {
                      if (!selected) {
                        _hasRecipes = null;
                      } else if (_hasRecipes == null) {
                        _hasRecipes = true;
                      } else if (_hasRecipes == true) {
                        _hasRecipes = false;
                      } else {
                        _hasRecipes = null;
                      }
                    });
                    _loadChannels();
                  },
                ),
                // Кнопка дополнительных фильтров
                ActionChip(
                  label: const Text('Еще фильтры'),
                  onPressed: _showAdvancedFilters,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Список каналов
          Expanded(
            child: _isLoading && _channels.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _channels.isEmpty
                    ? Center(
                        child: Text(
                          'Каналы не найдены',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _channels.length,
                        itemBuilder: (context, index) {
                          final channel = _channels[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: channel.avatarUrl != null
                                    ? NetworkImage(channel.avatarUrl!)
                                    : null,
                                child: channel.avatarUrl == null
                                    ? Text(channel.name[0].toUpperCase())
                                    : null,
                              ),
                              title: Text(channel.name),
                              subtitle: Text(
                                '${channel.postsCount} постов • ${channel.membersCount} участников',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                context.push('/channel/${channel.id}');
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
  
  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Выберите категорию',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                title: const Text('Все категории'),
                onTap: () {
                  setState(() => _selectedCategory = null);
                  Navigator.pop(context);
                  _loadChannels();
                },
              ),
              const Divider(),
              ..._availableCategories.map((category) {
                return ListTile(
                  title: Text(category),
                  onTap: () {
                    setState(() => _selectedCategory = category);
                    Navigator.pop(context);
                    _loadChannels();
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
  
  void _showAdvancedFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Дополнительные фильтры',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Минимальное количество подписчиков
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Мин. подписчиков',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          setModalState(() {
                            _minSubscribers = value.isEmpty 
                                ? null 
                                : int.tryParse(value);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Минимальное количество постов
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Мин. постов',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          setModalState(() {
                            _minPosts = value.isEmpty 
                                ? null 
                                : int.tryParse(value);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.all(16),
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
                          const SizedBox(width: 16),
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
    );
  }
}

