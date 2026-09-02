import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../models/chat_models.dart';
import '../../../services/chat_service.dart';
import '../../../services/paid_features_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_avatar.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/stars_pay_helper.dart';

/// Telegram-like received Star gifts: keep, convert, upgrade, transfer.
class StarGiftsInventoryScreen extends StatefulWidget {
  const StarGiftsInventoryScreen({super.key});

  @override
  State<StarGiftsInventoryScreen> createState() =>
      _StarGiftsInventoryScreenState();
}

class _StarGiftsInventoryScreenState extends State<StarGiftsInventoryScreen> {
  bool _loading = true;
  String? _error;
  List<UserStarGift> _gifts = const [];
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gifts = await PaidFeaturesService.listMyGifts();
      if (!mounted) return;
      setState(() {
        _gifts = gifts;
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

  Future<void> _saveOrder() async {
    if (_gifts.length < 2) return;
    try {
      final next = await PaidFeaturesService.reorderGifts(
        _gifts.map((g) => g.id).toList(),
      );
      if (!mounted) return;
      setState(() => _gifts = next);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Порядок подарков сохранён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  void _moveGift(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _gifts.length) return;
    setState(() {
      final copy = [..._gifts];
      final item = copy.removeAt(index);
      copy.insert(next, item);
      _gifts = copy;
    });
    unawaited(_saveOrder());
  }

  Future<void> _convert(UserStarGift gift) async {
    if (_busy.contains(gift.id) || !gift.canConvert) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Конвертировать подарок'),
        content: Text(
          '«${gift.title}» будет убран с профиля. Вы получите ${gift.stars} ★ на баланс.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Получить ${gift.stars} ★'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(gift.id));
    try {
      await PaidFeaturesService.convertGift(gift.id);
      if (!mounted) return;
      setState(() {
        _gifts = _gifts.where((g) => g.id != gift.id).toList(growable: false);
        _busy.remove(gift.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('+${gift.stars} ★ на балансе')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_convert(gift)),
          ),
        ),
      );
    }
  }

  Future<void> _keep(UserStarGift gift) async {
    if (_busy.contains(gift.id)) return;
    setState(() => _busy.add(gift.id));
    try {
      final next = await PaidFeaturesService.keepGift(gift.id);
      if (!mounted) return;
      setState(() {
        _gifts = _gifts
            .map((g) => g.id == next.id ? next : g)
            .toList(growable: false);
        _busy.remove(gift.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_keep(gift)),
          ),
        ),
      );
    }
  }

  Future<void> _toggleDisplay(UserStarGift gift) async {
    if (_busy.contains(gift.id) || gift.status == 'converted') return;
    setState(() => _busy.add(gift.id));
    try {
      final next = await PaidFeaturesService.setGiftDisplayed(
        gift.id,
        displayed: !gift.isDisplayed,
      );
      if (!mounted) return;
      setState(() {
        _gifts = _gifts
            .map((g) => g.id == next.id ? next : g)
            .toList(growable: false);
        _busy.remove(gift.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_toggleDisplay(gift)),
          ),
        ),
      );
    }
  }

  Future<void> _upgrade(UserStarGift gift) async {
    if (_busy.contains(gift.id) || !gift.canUpgrade) return;
    final ok = await confirmStarsSpend(
      context,
      title: 'Улучшить до коллекционного',
      body:
          '«${gift.title}» получит уникальный номер. Стоимость улучшения: ${gift.upgradeStars} ★.',
      amountStars: gift.upgradeStars,
      confirmLabel: 'Улучшить',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(gift.id));
    try {
      final result = await PaidFeaturesService.upgradeGift(gift.id);
      if (!mounted) return;
      setState(() {
        _gifts = _gifts
            .map((g) => g.id == result.gift.id ? result.gift : g)
            .toList(growable: false);
        _busy.remove(gift.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.gift.serialLabel.isNotEmpty
                ? 'Коллекционный ${result.gift.serialLabel}'
                : 'Подарок улучшен',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      await showStarsRequiredSnack(context, e);
    }
  }

  Future<void> _transfer(UserStarGift gift) async {
    if (_busy.contains(gift.id) || !gift.canTransfer) return;
    final fee = gift.transferStars > 0
        ? gift.transferStars
        : (gift.isCollectible ? (gift.stars ~/ 10).clamp(25, 999999) : 0);
    final toUserId = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _GiftTransferUserPicker(
        giftTitle: gift.title,
        feeStars: fee,
      ),
    );
    if (toUserId == null || !mounted) return;
    if (fee > 0) {
      final ok = await confirmStarsSpend(
        context,
        title: 'Передать подарок',
        body: '«${gift.title}» будет передан другому пользователю.',
        amountStars: fee,
        confirmLabel: 'Передать',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy.add(gift.id));
    try {
      await PaidFeaturesService.transferGift(gift.id, toUserId: toUserId);
      if (!mounted) return;
      setState(() {
        _gifts = _gifts.where((g) => g.id != gift.id).toList(growable: false);
        _busy.remove(gift.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подарок передан')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      await showStarsRequiredSnack(context, e);
    }
  }

  Future<void> _sell(UserStarGift gift) async {
    if (_busy.contains(gift.id) || !gift.canSell) return;
    final controller = TextEditingController(
      text: '${gift.listedStars ?? gift.stars}',
    );
    final next = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выставить на витрину'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Цена в ★',
            hintText: 'Например: 250',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final price = int.tryParse(controller.text.trim()) ?? 0;
              Navigator.pop(ctx, price);
            },
            child: const Text('Выставить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || !mounted) return;
    if (next < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите цену от 1 ★')),
      );
      return;
    }
    setState(() => _busy.add(gift.id));
    try {
      final updated = await PaidFeaturesService.listGiftForSale(
        gift.id,
        listedStars: next,
      );
      if (!mounted) return;
      setState(() {
        _gifts = _gifts
            .map((g) => g.id == updated.id ? updated : g)
            .toList(growable: false);
        _busy.remove(gift.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('На витрине за $next ★')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_sell(gift)),
          ),
        ),
      );
    }
  }

  Future<void> _unlist(UserStarGift gift) async {
    if (_busy.contains(gift.id) || !gift.isListed) return;
    setState(() => _busy.add(gift.id));
    try {
      final updated = await PaidFeaturesService.unlistGift(gift.id);
      if (!mounted) return;
      setState(() {
        _gifts = _gifts
            .map((g) => g.id == updated.id ? updated : g)
            .toList(growable: false);
        _busy.remove(gift.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_unlist(gift)),
          ),
        ),
      );
    }
  }

  Future<void> _wear(UserStarGift gift) async {
    if (_busy.contains(gift.id) || !gift.canWear) return;
    final nextWorn = !gift.isWorn;
    setState(() => _busy.add(gift.id));
    try {
      final updated = await PaidFeaturesService.setGiftWorn(
        gift.id,
        worn: nextWorn,
      );
      if (!mounted) return;
      setState(() {
        _gifts = _gifts
            .map((g) {
              if (g.id == updated.id) return updated;
              if (nextWorn && g.isWorn) {
                return UserStarGift(
                  id: g.id,
                  ownerId: g.ownerId,
                  stars: g.stars,
                  slug: g.slug,
                  title: g.title,
                  emoji: g.emoji,
                  status: g.status,
                  senderId: g.senderId,
                  senderName: g.senderName,
                  senderUsername: g.senderUsername,
                  giftId: g.giftId,
                  messageId: g.messageId,
                  note: g.note,
                  isDisplayed: g.isDisplayed,
                  isCollectible: g.isCollectible,
                  isAnonymous: g.isAnonymous,
                  serial: g.serial,
                  transferredFromUserId: g.transferredFromUserId,
                  listedStars: g.listedStars,
                  listedAt: g.listedAt,
                  isWorn: false,
                  displayOrder: g.displayOrder,
                  sellerName: g.sellerName,
                  sellerUsername: g.sellerUsername,
                  upgradeStars: g.upgradeStars,
                  transferStars: g.transferStars,
                  totalSupply: g.totalSupply,
                  convertedAt: g.convertedAt,
                  createdAt: g.createdAt,
                );
              }
              return g;
            })
            .toList(growable: false);
        _busy.remove(gift.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои подарки'),
        actions: [
          if (_gifts.length > 1)
            IconButton(
              tooltip: 'Сохранить порядок',
              onPressed: _saveOrder,
              icon: const Icon(Icons.swap_vert_rounded),
            ),
          IconButton(
            tooltip: 'Витрина',
            onPressed: () => context.push(StarGiftsMarketplaceRoute.path),
            icon: const Icon(Icons.storefront_outlined),
          ),
        ],
      ),
      body: AppGradientBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: const Text('Повторить'),
            ),
          ),
        ],
      );
    }
    if (_gifts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24,
          64,
          24,
          24 + floatingBottomPadding(context),
        ),
        children: [
          const Icon(Icons.card_giftcard_rounded, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Пока нет подарков.\nКогда вам пришлют Stars Gift — он появится здесь.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: () => context.push(StarGiftsMarketplaceRoute.path),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Витрина подарков'),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        16 + floatingBottomPadding(context),
      ),
      itemCount: _gifts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final gift = _gifts[index];
        final busy = _busy.contains(gift.id);
        final scheme = Theme.of(context).colorScheme;
        final statusLabel = gift.isListed
            ? 'На витрине · ${gift.listedStars} ★'
            : gift.isCollectible
                ? (gift.serialLabel.isNotEmpty
                    ? 'Коллекционный ${gift.serialLabel}'
                    : 'Коллекционный')
                : (gift.status == 'kept' ? 'В профиле' : 'Ожидает решения');
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(gift.emoji, style: const TextStyle(fontSize: 36)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gift.title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${gift.stars} ★ · $statusLabel',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          if (gift.senderLabel.isNotEmpty)
                            Text(
                              gift.isAnonymous && gift.senderId != null
                                  ? 'От ${gift.senderLabel} · имя скрыто на профиле'
                                  : 'От ${gift.senderLabel}',
                              style: TextStyle(
                                color: scheme.secondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        IconButton(
                          tooltip: 'Выше',
                          onPressed: index == 0
                              ? null
                              : () => _moveGift(index, -1),
                          icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                        IconButton(
                          tooltip: 'Ниже',
                          onPressed: index == _gifts.length - 1
                              ? null
                              : () => _moveGift(index, 1),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                      ],
                    ),
                    if (gift.isDisplayed)
                      Icon(Icons.visibility_rounded, color: scheme.primary)
                    else
                      Icon(
                        Icons.visibility_off_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
                if (gift.note != null && gift.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    gift.note!.trim(),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (gift.status == 'held')
                      FilledButton.tonal(
                        onPressed: busy ? null : () => unawaited(_keep(gift)),
                        child: const Text('Оставить'),
                      ),
                    if (gift.canConvert)
                      FilledButton(
                        onPressed:
                            busy ? null : () => unawaited(_convert(gift)),
                        child: Text('В ★ · ${gift.stars}'),
                      ),
                    if (gift.canUpgrade)
                      FilledButton.tonal(
                        onPressed:
                            busy ? null : () => unawaited(_upgrade(gift)),
                        child: Text('Улучшить · ${gift.upgradeStars} ★'),
                      ),
                    if (gift.canTransfer)
                      OutlinedButton(
                        onPressed:
                            busy ? null : () => unawaited(_transfer(gift)),
                        child: Text(
                          gift.transferStars > 0
                              ? 'Передать · ${gift.transferStars} ★'
                              : 'Передать',
                        ),
                      ),
                    if (gift.canSell && !gift.isListed)
                      OutlinedButton(
                        onPressed: busy ? null : () => unawaited(_sell(gift)),
                        child: const Text('Продать'),
                      ),
                    if (gift.isListed)
                      OutlinedButton(
                        onPressed: busy ? null : () => unawaited(_unlist(gift)),
                        child: const Text('Снять с витрины'),
                      ),
                    if (gift.canWear)
                      OutlinedButton(
                        onPressed: busy ? null : () => unawaited(_wear(gift)),
                        child: Text(gift.isWorn ? 'Снять с профиля' : 'Надеть'),
                      ),
                    OutlinedButton(
                      onPressed:
                          busy ? null : () => unawaited(_toggleDisplay(gift)),
                      child: Text(
                        gift.isDisplayed ? 'Скрыть' : 'В профиль',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GiftTransferUserPicker extends StatefulWidget {
  const _GiftTransferUserPicker({
    required this.giftTitle,
    required this.feeStars,
  });

  final String giftTitle;
  final int feeStars;

  @override
  State<_GiftTransferUserPicker> createState() =>
      _GiftTransferUserPickerState();
}

class _GiftTransferUserPickerState extends State<_GiftTransferUserPicker> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<ChatUserSearchItem> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_search(value));
    });
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChatService.searchUsers(q);
      if (!mounted) return;
      setState(() {
        _results = items;
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'Кому передать «${widget.giftTitle}»?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (widget.feeStars > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Комиссия передачи: ${widget.feeStars} ★',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Поиск по имени или @username',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _onQueryChanged,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!, textAlign: TextAlign.center),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: () =>
                                        unawaited(_search(_controller.text)),
                                    child: const Text('Повторить'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _results.isEmpty
                            ? const Center(
                                child: Text('Начните вводить имя'),
                              )
                            : ListView.builder(
                                itemCount: _results.length,
                                itemBuilder: (context, index) {
                                  final item = _results[index];
                                  final name =
                                      item.name?.trim().isNotEmpty == true
                                          ? item.name!.trim()
                                          : (item.username ?? 'Пользователь');
                                  return ListTile(
                                    leading: AppUserAvatar(
                                      imageUrl: item.avatarUrl,
                                      displayName: name,
                                      radius: 20,
                                    ),
                                    title: Text(name),
                                    subtitle: item.username != null
                                        ? Text('@${item.username}')
                                        : null,
                                    onTap: () =>
                                        Navigator.pop(context, item.id),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
