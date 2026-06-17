import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_router.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/layout/floating_bottom_padding.dart';
import '../../../../core/phone/phone_hash.dart';
import '../../../../models/chat_models.dart';
import '../../../../services/api_reachability_service.dart';
import '../../../../services/app_invite_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/chat_service.dart';
import '../../../../services/phone_contacts_service.dart';
import '../../../../utils/api_error_parser.dart';
import '../../../../widgets/app_empty_state.dart';
import 'chats_hub_tiles.dart';

class ChatsHubContactsTab extends StatefulWidget {
  const ChatsHubContactsTab({
    super.key,
    required this.tabController,
    this.searchQuery = '',
  });

  static const contactsTabIndex = 1;

  final TabController tabController;
  final String searchQuery;

  @override
  State<ChatsHubContactsTab> createState() => _ChatsHubContactsTabState();
}

class _ChatsHubContactsTabState extends State<ChatsHubContactsTab> {
  List<ChatContact> _items = [];
  List<PhoneBookContact> _phoneBook = [];
  bool _loading = false;
  bool _syncingPhone = false;
  bool _loadStarted = false;
  bool _phonePermissionDenied = false;
  Object? _error;
  Object? _phoneSyncError;
  int? _contactActionUserId;
  int _contactsLoadSeq = 0;
  VoidCallback? _reconnectedListener;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onSubTabChanged);
    _reconnectedListener = () {
      if (!mounted || !_isContactsSubTabVisible) return;
      unawaited(_fetchPhoneContacts());
      unawaited(_fetchContacts());
    };
    ApiReachabilityService.addReconnectedListener(_reconnectedListener!);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSubTabChanged());
  }

  void _onSubTabChanged() {
    if (!mounted || widget.tabController.indexIsChanging) return;
    if (_isContactsSubTabVisible && !_loadStarted) {
      _loadStarted = true;
      _loadAll();
      return;
    }
    setState(() {});
  }

  bool get _isContactsSubTabVisible =>
      widget.tabController.index == ChatsHubContactsTab.contactsTabIndex;

  String get _query => widget.searchQuery.trim().toLowerCase();

  List<PhoneBookContact> get _visiblePhoneBook {
    final q = _query;
    if (q.isEmpty) return _phoneBook;
    return _phoneBook.where((entry) {
      if (entry.displayName.toLowerCase().contains(q)) return true;
      if (entry.phoneE164.toLowerCase().contains(q)) return true;
      final matched = entry.matchedUser;
      if (matched == null) return false;
      return (matched.name?.toLowerCase().contains(q) ?? false) ||
          (matched.username?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  List<ChatContact> get _visibleItems {
    final q = _query;
    if (q.isEmpty) return _items;
    return _items.where((contact) {
      return contact.user.displayName.toLowerCase().contains(q) ||
          (contact.user.username?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  void dispose() {
    if (_reconnectedListener != null) {
      ApiReachabilityService.removeReconnectedListener(_reconnectedListener!);
    }
    widget.tabController.removeListener(_onSubTabChanged);
    super.dispose();
  }

  Future<void> _loadAll() async {
    final seq = ++_contactsLoadSeq;
    setState(() {
      _loading = true;
      _syncingPhone = true;
      _error = null;
      _phoneSyncError = null;
      _phonePermissionDenied = false;
    });
    try {
      await Future.wait([
        _fetchContacts(),
        _fetchPhoneContacts(),
      ]);
    } finally {
      if (mounted && seq == _contactsLoadSeq) {
        setState(() {
          _loading = false;
          _syncingPhone = false;
        });
      }
    }
  }

  Future<void> _fetchContacts() async {
    try {
      final items = await ChatService.listContacts();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _fetchPhoneContacts() async {
    try {
      final result = await PhoneContactsService.syncFromDevice();
      if (!mounted) return;
      setState(() {
        _phoneBook = result.phoneBook;
        _phonePermissionDenied = false;
        _phoneSyncError = result.apiError;
      });
      if (result.apiError != null &&
          ApiReachabilityService.instance.isApiReachable.value) {
        // Повторим сопоставление через несколько секунд, если API снова доступен.
        Future<void>.delayed(const Duration(seconds: 4), () {
          if (!mounted || _phoneSyncError == null) return;
          unawaited(_fetchPhoneContacts());
        });
      }
    } on PhoneContactsPermissionDenied {
      if (!mounted) return;
      setState(() {
        _phoneBook = [];
        _phonePermissionDenied = !kIsWeb;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _phoneSyncError = e);
    }
  }

  Future<void> _importFromPhoneBook() async {
    if (!PhoneContactsService.supportsContactPicker) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Импорт из телефонной книги недоступен в этом браузере. '
            'Используйте Chrome на Android или добавьте контакты вручную.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _syncingPhone = true;
      _phoneSyncError = null;
      _phonePermissionDenied = false;
    });
    try {
      final count = await PhoneContactsService.importFromPicker();
      if (!mounted) return;
      if (count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Контакты не выбраны')),
        );
      }
      await _fetchPhoneContacts();
    } catch (e) {
      if (!mounted) return;
      setState(() => _phoneSyncError = e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _syncingPhone = false);
    }
  }

  Future<void> _retryPhonePermission() async {
    if (kIsWeb) {
      await _importFromPhoneBook();
      return;
    }
    setState(() {
      _syncingPhone = true;
      _phoneSyncError = null;
      _phonePermissionDenied = false;
    });
    await _fetchPhoneContacts();
    if (mounted) setState(() => _syncingPhone = false);
  }

  Future<void> _linkMyPhone() async {
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Привязать ваш номер'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Друзья из телефонной книги смогут найти вас в HAN Eat.',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Ваш номер',
                    hintText: '+7 900 123-45-67',
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.isEmpty) return 'Введите номер';
                    if (normalizePhoneE164(raw) == null) {
                      return 'Некорректный номер';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Привязать'),
            ),
          ],
        ),
      );
      if (saved != true || !mounted) return;

      await AuthService.linkPhone(phoneController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Номер привязан')),
      );
      setState(() {});
      await _fetchPhoneContacts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      phoneController.dispose();
    }
  }

  Future<void> _addPhoneContact() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Новый контакт'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Имя',
                      hintText: 'Иван Петров',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Введите имя';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Номер',
                      hintText: '+7 900 123-45-67',
                    ),
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      if (raw.isEmpty) return 'Введите номер';
                      if (normalizePhoneE164(raw) == null) {
                        return 'Некорректный номер';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );
      if (saved != true || !mounted) return;

      final name = nameController.text.trim();
      final phone = phoneController.text.trim();

      await PhoneContactsService.addContactToDevice(
        displayName: name,
        phoneRaw: phone,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb ? 'Контакт сохранён' : 'Контакт сохранён в телефоне',
          ),
        ),
      );
      await _fetchPhoneContacts();
      if (mounted) setState(() {});
    } on PhoneContactsPermissionDenied {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Нужен доступ к контактам. '
            'Настройки → HAN Eat → Контакты → разрешить изменения.',
          ),
        ),
      );
    } on PhoneContactsInvalidInput catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      nameController.dispose();
      phoneController.dispose();
    }
  }

  Future<void> _openChatWithUser(int userId) async {
    try {
      final conv = await ChatService.openDirectChat(userId);
      if (!context.mounted) return;
      await context.push(ChatThreadRoute.pathFor(conv), extra: conv);
      if (mounted) _fetchContacts();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _addHanEatContact(int userId) async {
    if (_contactActionUserId != null) return;
    setState(() => _contactActionUserId = userId);
    try {
      await ChatService.addContact(userId);
      if (!mounted) return;
      AppHaptics.light();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавлено в контакты')),
      );
      await _fetchContacts();
      await _fetchPhoneContacts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _contactActionUserId = null);
    }
  }

  Future<void> _removeHanEatContact(int userId, String name) async {
    if (_contactActionUserId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить контакт?'),
        content: Text('$name будет убран из списка «Мои контакты».'),
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
    if (confirmed != true || !mounted) return;
    setState(() => _contactActionUserId = userId);
    try {
      await ChatService.removeContact(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Контакт удалён')),
      );
      await _fetchContacts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _contactActionUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isContactsSubTabVisible) {
      return const SizedBox.shrink();
    }
    if (_loading && _items.isEmpty && _phoneBook.isEmpty && !_phonePermissionDenied) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty && _phoneBook.isEmpty) {
      return AppEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Не удалось загрузить контакты',
        subtitle: userVisibleError(_error!),
        action: FilledButton(onPressed: _loadAll, child: const Text('Повторить')),
      );
    }

    final user = AuthService.instance.currentUser;
    final showLinkPhone = user != null && !user.phoneLinked;
    final phoneBook = _visiblePhoneBook;
    final items = _visibleItems;
    final searching = _query.isNotEmpty;

    if (searching &&
        phoneBook.isEmpty &&
        items.isEmpty &&
        !_loading &&
        _error == null) {
      return ListView(
        padding: EdgeInsets.only(bottom: floatingBottomPadding(context)),
        children: const [
          SizedBox(height: 48),
          AppEmptyState(
            icon: Icons.search_off,
            title: 'Ничего не найдено',
            subtitle: 'Попробуйте другой запрос.',
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: EdgeInsets.only(bottom: floatingBottomPadding(context)),
        children: [
          if (showLinkPhone)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: Icon(
                  Icons.phone_android_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                title: Text(
                  'Привяжите номер',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Найдём друзей из телефонной книги и покажем, кто уже в HAN Eat',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer
                        .withValues(alpha: 0.85),
                  ),
                ),
                trailing: FilledButton.tonal(
                  onPressed: _linkMyPhone,
                  child: const Text('Привязать'),
                ),
              ),
            ),
          if (_syncingPhone && !_loading)
            const LinearProgressIndicator(minHeight: 2),
          if (_phonePermissionDenied)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.contacts_outlined),
                title: const Text('Доступ к контактам'),
                subtitle: const Text(
                  'Разрешите доступ к телефонной книге — друзья и приглашения появятся автоматически. '
                  'Если диалог не показывается, откройте Настройки → HAN Eat → Контакты.',
                ),
                trailing: _syncingPhone
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton(
                        onPressed: _retryPhonePermission,
                        child: const Text('Разрешить'),
                      ),
              ),
            ),
          if (kIsWeb && PhoneContactsService.supportsContactPicker)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.sync_outlined),
                title: const Text('Синхронизация контактов'),
                subtitle: Text(
                  _phoneBook.isEmpty
                      ? 'Выберите контакты из телефонной книги — покажем, кто уже в HAN Eat'
                      : 'Добавить ещё контакты из телефонной книги',
                ),
                trailing: _syncingPhone
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton(
                        onPressed: _importFromPhoneBook,
                        child: Text(_phoneBook.isEmpty ? 'Импорт' : 'Ещё'),
                      ),
              ),
            ),
          if (kIsWeb && !PhoneContactsService.supportsContactPicker)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Импорт с телефона'),
                subtitle: Text(
                  'В этом браузере нельзя прочитать телефонную книгу целиком. '
                  'Откройте HAN Eat в Chrome на Android или добавляйте номера вручную.',
                ),
              ),
            ),
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('Добавить контакт'),
              subtitle: Text(
                kIsWeb
                    ? 'Имя и номер человека, которого хотите добавить'
                    : 'Сохранится в телефонной книге',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _addPhoneContact,
            ),
          ),
          if (_phoneSyncError != null && _phoneBook.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Пока не удалось загрузить контакты. Подключение восстановится автоматически.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          if (phoneBook.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Телефонная книга (${phoneBook.length})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ...phoneBook.map((entry) {
              final matched = entry.matchedUser;
              if (matched != null) {
                return ListTile(
                  leading: ChatHubUserAvatar(user: matched.brief),
                  title: Text(entry.displayName),
                  subtitle: Text(
                    matched.name ?? '@${matched.username ?? matched.id}',
                  ),
                  trailing: matched.isContact
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : TextButton(
                          onPressed: _contactActionUserId == matched.id
                              ? null
                              : () => _addHanEatContact(matched.id),
                          child: const Text('В контакты'),
                        ),
                  onTap: () => _openChatWithUser(matched.id),
                );
              }
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.person_outline,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                title: Text(entry.displayName),
                subtitle: Text(entry.phoneE164),
                trailing: FilledButton.tonal(
                  onPressed: () => AppInviteService.inviteContact(
                    context,
                    displayName: entry.displayName,
                    phoneE164: entry.phoneE164,
                  ),
                  child: const Text('Пригласить'),
                ),
              );
            }),
            const Divider(height: 24),
          ],
          if (items.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Мои контакты',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ...items.map((contact) {
              return Column(
                children: [
                  ListTile(
                    leading: ChatHubUserAvatar(user: contact.user),
                    title: Text(contact.user.displayName),
                    subtitle: contact.user.username != null
                        ? Text('@${contact.user.username}')
                        : null,
                    trailing: PopupMenuButton<String>(
                      enabled: _contactActionUserId == null,
                      onSelected: (value) {
                        switch (value) {
                          case 'chat':
                            _openChatWithUser(contact.user.id);
                          case 'remove':
                            _removeHanEatContact(
                              contact.user.id,
                              contact.user.displayName,
                            );
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'chat',
                          child: Text('Написать'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Удалить из контактов'),
                        ),
                      ],
                    ),
                    onTap: () => _openChatWithUser(contact.user.id),
                  ),
                  const Divider(height: 1, indent: 72),
                ],
              );
            }),
          ],
          if (items.isEmpty &&
              phoneBook.isEmpty &&
              _error == null &&
              !_phonePermissionDenied &&
              !_loading &&
              !searching)
            Padding(
              padding: const EdgeInsets.all(24),
              child: AppEmptyState(
                icon: Icons.people_outline_rounded,
                title: 'Пока пусто',
                subtitle:
                    kIsWeb
                        ? 'Импортируйте контакты с телефона или добавьте номера вручную.'
                        : 'В телефонной книге нет номеров с кодом страны или добавьте людей через поиск.',
              ),
            ),
        ],
      ),
    );
  }
}
