import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../models/emoji_pack_models.dart';
import '../../../models/sticker_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/emoji_pack_service.dart';
import '../../../services/server_config.dart';
import '../../../services/sticker_service.dart';
import '../../../services/custom_emoji_registry.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/highlighted_text.dart';
import '../../../widgets/stars_pay_helper.dart';
import '../../chat/presentation/sticker_pack_manage_screen.dart';
import '../../subscription/creator_upsell.dart';
import 'emoji_pack_manage_screen.dart';

class PackStoreScreen extends StatefulWidget {
  const PackStoreScreen({super.key});

  @override
  State<PackStoreScreen> createState() => _PackStoreScreenState();
}

class _PackStoreScreenState extends State<PackStoreScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<StickerPack> _stickers = const [];
  List<EmojiPack> _emojis = const [];
  List<StickerPack> _myStickers = const [];
  List<EmojiPack> _myEmojis = const [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _search.text.trim();
      final stickersMarket = await StickerService.listMarketplace(query: q);
      final stickersCatalog = await StickerService.listCatalog(query: q);
      final emojisMarket = await EmojiPackService.listMarketplace(query: q);
      final emojisCatalog = await EmojiPackService.listCatalog(query: q);
      final myStickers = await StickerService.listMyPacks();
      final myEmojis = await EmojiPackService.listMyPacks();
      final stickerSeen = <int>{};
      final stickers = <StickerPack>[
        for (final p in [...stickersMarket, ...stickersCatalog])
          if (stickerSeen.add(p.id)) p,
      ];
      final emojiSeen = <int>{};
      final emojis = <EmojiPack>[
        for (final p in [...emojisMarket, ...emojisCatalog])
          if (emojiSeen.add(p.id)) p,
      ];
      if (!mounted) return;
      setState(() {
        _stickers = stickers;
        _emojis = emojis;
        _myStickers = myStickers;
        _myEmojis = myEmojis;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e);
      });
    }
  }

  String _key(String kind, int id) => '$kind:$id';

  Future<void> _buySticker(StickerPack pack) async {
    final me = AuthService.instance.currentUser?.id;
    if (me != null && me == pack.ownerUserId) return;
    if (_busy.contains(_key('s', pack.id))) return;
    if (pack.priceStars <= 0 || pack.isPurchased) {
      setState(() => _busy.add(_key('s', pack.id)));
      try {
        await StickerService.installPack(pack.id);
        if (!mounted) return;
        await _load();
      } catch (e) {
        if (!mounted) return;
        if (offerFlexIfRequired(context, e)) return;
        if (offerPackStoreIfRequired(context, e)) return;
        await showStarsRequiredSnack(context, e);
      } finally {
        if (mounted) setState(() => _busy.remove(_key('s', pack.id)));
      }
      return;
    }
    final ok = await confirmStarsSpend(
      context,
      title: 'Купить «${previewTextWithCustomEmoji(pack.title)}»',
      body: pack.ownerName.trim().isEmpty
          ? '${pack.priceStars} ★ · комиссия площадки ${pack.feeStars} ★'
          : 'Автор ${previewTextWithCustomEmoji(pack.ownerName)} · ${pack.priceStars} ★, комиссия ${pack.feeStars} ★',
      amountStars: pack.priceStars,
      confirmLabel: 'Купить',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(_key('s', pack.id)));
    try {
      await StickerService.buyPack(
        pack.id,
        expectedPriceStars: pack.priceStars,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '«${previewTextWithCustomEmoji(pack.title)}» установлен',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (offerPackStoreIfRequired(context, e)) return;
      await showStarsRequiredSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(_key('s', pack.id)));
    }
  }

  Future<void> _buyEmoji(EmojiPack pack) async {
    final me = AuthService.instance.currentUser?.id;
    if (me != null && me == pack.ownerUserId) return;
    if (_busy.contains(_key('e', pack.id))) return;
    if (pack.priceStars <= 0 || pack.isPurchased) {
      setState(() => _busy.add(_key('e', pack.id)));
      try {
        await EmojiPackService.installPack(pack.id);
        if (!mounted) return;
        await _load();
        if (!mounted) return;
        if (!hasFlexFeature('custom_emoji')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Пак установлен. Чтобы вставлять эмодзи в сообщения, нужен уровень 69',
              ),
              action: SnackBarAction(
                label: 'Подписка',
                onPressed: () {
                  if (context.mounted) {
                    context.push(FlexSubscriptionRoute.path);
                  }
                },
              ),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        if (offerFlexIfRequired(context, e)) return;
        if (offerPackStoreIfRequired(context, e)) return;
        await showStarsRequiredSnack(context, e);
      } finally {
        if (mounted) setState(() => _busy.remove(_key('e', pack.id)));
      }
      return;
    }
    final ok = await confirmStarsSpend(
      context,
      title: 'Купить «${previewTextWithCustomEmoji(pack.title)}»',
      body:
          'Автор ${previewTextWithCustomEmoji(pack.authorLabel)} · ${pack.priceStars} ★, комиссия ${pack.feeStars} ★',
      amountStars: pack.priceStars,
      confirmLabel: 'Купить',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(_key('e', pack.id)));
    try {
      await EmojiPackService.buyPack(
        pack.id,
        expectedPriceStars: pack.priceStars,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      if (!hasFlexFeature('custom_emoji')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Пак куплен. Чтобы вставлять эмодзи в сообщения, нужен уровень 69',
            ),
            action: SnackBarAction(
              label: 'Подписка',
              onPressed: () {
                if (context.mounted) {
                  context.push(FlexSubscriptionRoute.path);
                }
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          content: Text(
            '«${previewTextWithCustomEmoji(pack.title)}» установлен',
          ),
        ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (offerPackStoreIfRequired(context, e)) return;
      await showStarsRequiredSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(_key('e', pack.id)));
    }
  }

  Future<String?> _askPackTitle(String title) async {
    final titleCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    final text = titleCtrl.text.trim();
    return text.length < 2 ? null : text;
  }

  Future<void> _showCreateMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Стикерпак'),
              subtitle: const Text('Выставить на продажу можно с уровня 71'),
              onTap: () => Navigator.pop(ctx, 'sticker'),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: const Text('Эмодзи-пак'),
              subtitle: const Text('Публикация с уровня 70'),
              onTap: () => Navigator.pop(ctx, 'emoji'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'sticker') {
      await _createStickerPack();
    } else if (choice == 'emoji') {
      await _createEmojiPack();
    }
  }

  Future<void> _createStickerPack() async {
    final title = await _askPackTitle('Новый стикерпак');
    if (title == null) return;
    try {
      final pack = await StickerService.createPack(title: title);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => StickerPackManageScreen(packId: pack.id),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _createEmojiPack() async {
    if (!hasFlexFeature('emoji_pack_publish')) {
      await showCreatorUpsell(context);
      return;
    }
    final title = await _askPackTitle('Новый эмодзи-пак');
    if (title == null) return;
    try {
      final pack = await EmojiPackService.createPack(title: title);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EmojiPackManageScreen(packId: pack.id),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Магазин паков'),
        actions: [
          IconButton(
            tooltip: 'Кошелёк Stars',
            onPressed: () => context.push(StarsWalletRoute.path),
            icon: const Icon(Icons.stars_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Стикеры'),
            Tab(text: 'Эмодзи'),
            Tab(text: 'Мои'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateMenu,
        icon: const Icon(Icons.add),
        label: const Text('Создать пак'),
      ),
      body: AppGradientBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Поиск по названию',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Покупка открыта всем за Stars. Публикация пака — платная функция flex. Комиссия площадки 5%, до 20 ★ бесплатно.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _refreshable(_stickerList()),
                  _refreshable(_emojiList()),
                  _refreshable(_mineList()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refreshable(Widget child) {
    return RefreshIndicator(onRefresh: _load, child: child);
  }

  Widget _stickerList() {
    if (_loading) return _loadingList();
    if (_error != null) return _errorList();
    if (_stickers.isEmpty) {
      return _empty('Пока никто не выставил стикерпак за Stars.');
    }
    final me = AuthService.instance.currentUser?.id;
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        12,
        4,
        12,
        88 + floatingBottomPadding(context),
      ),
      itemCount: _stickers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final pack = _stickers[index];
        final mine = me != null && me == pack.ownerUserId;
        return _PackCard(
          title: pack.title,
          author: pack.ownerName,
          countLabel: '${pack.stickersCount} стик.',
          priceStars: pack.priceStars,
          feeStars: pack.feeStars,
          thumbs: pack.stickers.map((s) => s.mediaUrl).toList(),
          owned: mine || pack.isInstalled,
          reinstall: pack.isPurchased && !pack.isInstalled,
          busy: _busy.contains(_key('s', pack.id)),
          onOpen: () async {
            await context.push(StickerPackPreviewRoute.pathFor(pack.slug));
            if (mounted) await _load();
          },
          onBuy: mine ? null : () => _buySticker(pack),
        );
      },
    );
  }

  Widget _emojiList() {
    if (_loading) return _loadingList();
    if (_error != null) return _errorList();
    if (_emojis.isEmpty) {
      return _empty('Пока нет платных эмодзи-паков. Создайте свой.');
    }
    final me = AuthService.instance.currentUser?.id;
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        12,
        4,
        12,
        88 + floatingBottomPadding(context),
      ),
      itemCount: _emojis.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final pack = _emojis[index];
        final mine = me != null && me == pack.ownerUserId;
        return _PackCard(
          title: pack.title,
          author: pack.authorLabel,
          countLabel: '${pack.itemsCount} эмодзи',
          priceStars: pack.priceStars,
          feeStars: pack.feeStars,
          thumbs: pack.items.map((s) => s.mediaUrl).toList(),
          owned: mine || pack.isInstalled,
          reinstall: pack.isPurchased && !pack.isInstalled,
          busy: _busy.contains(_key('e', pack.id)),
          onOpen: () async {
            await context.push(EmojiPackPreviewRoute.pathFor(pack.slug));
            if (mounted) await _load();
          },
          onBuy: mine ? null : () => _buyEmoji(pack),
        );
      },
    );
  }

  Widget _mineList() {
    if (_loading) return _loadingList();
    if (_error != null) return _errorList();
    final me = AuthService.instance.currentUser?.id ?? -1;
    final ownedStickers =
        _myStickers.where((p) => p.isOwned || p.ownerUserId == me).toList();
    final boughtStickers = _myStickers
        .where((p) => !p.isOwned && p.ownerUserId != me && (p.isPurchased || p.isInstalled))
        .toList();
    final ownedEmojis = _myEmojis.where((p) => p.isOwned).toList();
    final boughtEmojis = _myEmojis
        .where((p) => !p.isOwned && (p.isPurchased || p.isInstalled))
        .toList();
    final items = <Widget>[
      const ListTile(
        title: Text('Мои стикерпаки'),
        subtitle: Text('Выставить на витрину можно с уровня 71'),
      ),
      if (ownedStickers.isEmpty)
        const ListTile(title: Text('Пока нет своих стикерпаков')),
      for (final pack in ownedStickers)
        ListTile(
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: HighlightedText(
            text: pack.title,
            style: Theme.of(context).textTheme.bodyLarge ??
                const TextStyle(fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            pack.isOnSale
                ? 'В магазине · ${pack.priceStars} ★'
                : (pack.priceStars > 0
                    ? 'Снято с витрины · ${pack.priceStars} ★'
                    : 'Не продаётся'),
          ),
          onTap: () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => StickerPackManageScreen(packId: pack.id),
              ),
            );
            await _load();
          },
        ),
      const Divider(),
      const ListTile(
        title: Text('Мои эмодзи-паки'),
        subtitle: Text('Публикация с уровня 70'),
      ),
      if (ownedEmojis.isEmpty)
        const ListTile(title: Text('Пока нет своих эмодзи-паков')),
      for (final pack in ownedEmojis)
        ListTile(
          leading: const Icon(Icons.emoji_emotions_outlined),
          title: HighlightedText(
            text: pack.title,
            style: Theme.of(context).textTheme.bodyLarge ??
                const TextStyle(fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            pack.isOnSale
                ? 'В магазине · ${pack.priceStars} ★'
                : (pack.priceStars > 0
                    ? 'Снято с витрины · ${pack.priceStars} ★'
                    : 'Не продаётся'),
          ),
          onTap: () async {
            await context.push(EmojiPackManageRoute.pathFor(pack.id));
            await _load();
          },
        ),
      if (boughtStickers.isNotEmpty || boughtEmojis.isNotEmpty) ...[
        const Divider(),
        const ListTile(
          title: Text('Купленные'),
          subtitle: Text('Можно установить снова без повторной оплаты'),
        ),
        for (final pack in boughtStickers)
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: HighlightedText(
            text: pack.title,
            style: Theme.of(context).textTheme.bodyLarge ??
                const TextStyle(fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
            subtitle: Text(pack.isInstalled ? 'Установлен' : 'Снят · установить снова'),
            trailing: pack.isInstalled
                ? null
                : TextButton(
                    onPressed: () => _buySticker(pack),
                    child: const Text('Установить'),
                  ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StickerPackManageScreen(packId: pack.id),
                ),
              );
              if (mounted) await _load();
            },
          ),
        for (final pack in boughtEmojis)
          ListTile(
            leading: const Icon(Icons.emoji_emotions_outlined),
            title: HighlightedText(
            text: pack.title,
            style: Theme.of(context).textTheme.bodyLarge ??
                const TextStyle(fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
            subtitle: Text(pack.isInstalled ? 'Установлен' : 'Снят · установить снова'),
            trailing: pack.isInstalled
                ? null
                : TextButton(
                    onPressed: () => _buyEmoji(pack),
                    child: const Text('Установить'),
                  ),
            onTap: () async {
              await context.push(EmojiPackManageRoute.pathFor(pack.id));
              if (mounted) await _load();
            },
          ),
      ],
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: 88 + floatingBottomPadding(context)),
      children: items,
    );
  }

  Widget _loadingList() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 80),
        Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _errorList() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: FilledButton(onPressed: _load, child: const Text('Повторить')),
        ),
      ],
    );
  }

  Widget _empty(String text) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      children: [
        const Icon(Icons.storefront_outlined, size: 48),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
      ],
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.title,
    required this.author,
    required this.countLabel,
    required this.priceStars,
    required this.feeStars,
    required this.thumbs,
    required this.owned,
    this.reinstall = false,
    required this.busy,
    required this.onOpen,
    this.onBuy,
  });

  final String title;
  final String author;
  final String countLabel;
  final int priceStars;
  final int feeStars;
  final List<String> thumbs;
  final bool owned;
  final bool reinstall;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: HighlightedText(
                      text: title,
                      style: Theme.of(context).textTheme.titleMedium ??
                          const TextStyle(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('$priceStars ★'),
                ],
              ),
              const SizedBox(height: 2),
              HighlightedText(
                text: [
                  if (author.trim().isNotEmpty) 'Автор $author',
                  countLabel,
                  if (feeStars > 0) 'комиссия $feeStars ★',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ) ??
                    TextStyle(color: scheme.onSurfaceVariant),
              ),
              if (thumbs.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: thumbs.take(8).length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        ServerConfig.resolveMediaUrl(thumbs[i]),
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 52,
                          height: 52,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: owned || busy || onBuy == null ? null : onBuy,
                  child: Text(
                    owned
                        ? 'Установлен'
                        : (reinstall
                            ? 'Установить'
                            : (priceStars > 0
                                ? 'Купить $priceStars ★'
                                : 'Установить')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
