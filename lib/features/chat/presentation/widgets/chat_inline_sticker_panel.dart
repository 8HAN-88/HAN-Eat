import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../models/emoji_pack_models.dart';
import '../../../../models/sticker_models.dart';
import '../../../../services/custom_emoji_registry.dart';
import '../../../../services/emoji_pack_service.dart';
import '../../../../services/server_config.dart';
import '../../../../services/sticker_service.dart';
import '../../../subscription/creator_upsell.dart';
import '../../application/chat_recent_stickers_store.dart';

enum _InlineStickerTab { recent, favorites, pack, emoji }

/// Compact sticker picker above the composer (Telegram-style).
class ChatInlineStickerPanel extends StatefulWidget {
  const ChatInlineStickerPanel({
    super.key,
    required this.onPick,
    this.onInsertCustomEmoji,
    this.onOpenFull,
    this.height = 268,
  });

  final void Function(String mediaUrl, {String? emoji}) onPick;
  final ValueChanged<int>? onInsertCustomEmoji;
  final VoidCallback? onOpenFull;
  final double height;

  @override
  State<ChatInlineStickerPanel> createState() => _ChatInlineStickerPanelState();
}

class _ChatInlineStickerPanelState extends State<ChatInlineStickerPanel> {
  List<StickerPack> _packs = const [];
  List<EmojiPack> _emojiPacks = const [];
  List<ChatRecentStickerEntry> _recent = const [];
  List<ChatRecentStickerEntry> _favorites = const [];
  bool _loading = true;
  String? _error;
  _InlineStickerTab _tab = _InlineStickerTab.recent;
  int? _selectedPackId;
  int? _selectedEmojiPackId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final packs = await StickerService.listMyPacks();
      List<EmojiPack> emojiPacks = const [];
      try {
        emojiPacks = await EmojiPackService.listMyPacks();
      } catch (_) {}
      final recent = await ChatRecentStickersStore.loadRecent();
      final favorites = await ChatRecentStickersStore.loadFavorites();
      if (!mounted) return;
      setState(() {
        _packs =
            packs.where((p) => p.isInstalled || p.stickers.isNotEmpty).toList();
        _emojiPacks = emojiPacks.where((p) => p.canUse).toList();
        _recent = recent;
        _favorites = favorites;
        _loading = false;
        if (_tab == _InlineStickerTab.recent &&
            _recent.isEmpty &&
            _favorites.isNotEmpty) {
          _tab = _InlineStickerTab.favorites;
        } else if (_tab == _InlineStickerTab.recent &&
            _recent.isEmpty &&
            _packs.isNotEmpty) {
          _tab = _InlineStickerTab.pack;
          _selectedPackId = _packs.first.id;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить стикеры';
      });
    }
  }

  List<_StickerThumb> get _items {
    switch (_tab) {
      case _InlineStickerTab.recent:
        return [
          for (final e in _recent)
            if (e.mediaUrl.trim().isNotEmpty)
              _StickerThumb(
                mediaUrl: e.mediaUrl,
                emoji: e.emoji,
                stickerId: e.stickerId,
                stickerType: e.stickerType,
              ),
        ];
      case _InlineStickerTab.favorites:
        return [
          for (final e in _favorites)
            if (e.mediaUrl.trim().isNotEmpty)
              _StickerThumb(
                mediaUrl: e.mediaUrl,
                emoji: e.emoji,
                stickerId: e.stickerId,
                stickerType: e.stickerType,
              ),
        ];
      case _InlineStickerTab.pack:
        for (final pack in _packs) {
          if (pack.id != _selectedPackId) continue;
          return [
            for (final s in pack.stickers)
              if (s.mediaUrl.trim().isNotEmpty)
                _StickerThumb(
                  mediaUrl: s.mediaUrl,
                  emoji: s.emoji,
                  stickerId: s.id,
                  stickerType: s.stickerType,
                ),
          ];
        }
        return const [];
      case _InlineStickerTab.emoji:
        for (final pack in _emojiPacks) {
          if (pack.id != _selectedEmojiPackId) continue;
          return [
            for (final s in pack.items)
              if (s.mediaUrl.trim().isNotEmpty)
                _StickerThumb(
                  mediaUrl: s.mediaUrl,
                  customEmojiId: s.id,
                ),
          ];
        }
        return const [];
    }
  }

  Future<void> _pick(_StickerThumb item) async {
    final customId = item.customEmojiId;
    if (customId != null && customId > 0) {
      if (!hasFlexFeature('custom_emoji')) {
        await showCreatorUpsell(context);
        return;
      }
      final allowed = _emojiPacks.any(
        (pack) =>
            pack.canUse && pack.items.any((item) => item.id == customId),
      );
      if (!allowed) {
        if (context.mounted) {
          offerPackStoreIfRequired(context, 'pack_purchase_required');
        }
        return;
      }
      widget.onInsertCustomEmoji?.call(customId);
      return;
    }
    unawaited(
      ChatRecentStickersStore.remember(
        mediaUrl: item.mediaUrl,
        emoji: item.emoji,
        stickerType: item.stickerType,
        stickerId: item.stickerId,
      ),
    );
    widget.onPick(item.mediaUrl, emoji: item.emoji);
  }

  Future<void> _toggleFavorite(_StickerThumb item) async {
    late final bool added;
    try {
      added = await ChatRecentStickersStore.toggleFavorite(
        mediaUrl: item.mediaUrl,
        emoji: item.emoji,
        stickerType: item.stickerType,
        stickerId: item.stickerId,
      );
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      if (offerPackStoreIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      return;
    }
    final favorites = await ChatRecentStickersStore.loadFavorites();
    if (!mounted) return;
    setState(() => _favorites = favorites);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Добавлено в избранные стикеры' : 'Убрано из избранных',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  String get _emptyLabel {
    switch (_tab) {
      case _InlineStickerTab.recent:
        return 'Нет недавних стикеров';
      case _InlineStickerTab.favorites:
        return 'Нет избранных · долгий тап по стикеру';
      case _InlineStickerTab.pack:
        return 'В паке пока пусто';
      case _InlineStickerTab.emoji:
        return 'Нет установленных эмодзи-паков';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1A2632) : scheme.surface,
      child: SizedBox(
        height: widget.height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
              child: Row(
                children: [
                  Text(
                    _tab == _InlineStickerTab.emoji ? 'Эмодзи' : 'Стикеры',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (widget.onOpenFull != null)
                    TextButton(
                      onPressed: widget.onOpenFull,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Все'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: TextButton(
                            onPressed: _load,
                            child: Text(_error!),
                          ),
                        )
                      : _items.isEmpty
                          ? Center(
                              child: Text(
                                _emptyLabel,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                              ),
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                final url = ServerConfig.resolveMediaUrl(
                                  item.mediaUrl,
                                );
                                final isFavorite = _favorites.any(
                                  (e) => e.mediaUrl == item.mediaUrl,
                                );
                                return InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => unawaited(_pick(item)),
                                  onLongPress: item.customEmojiId != null
                                      ? null
                                      : () => unawaited(_toggleFavorite(item)),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(
                                        url,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.broken_image_outlined,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (isFavorite)
                                        const Align(
                                          alignment: Alignment.topRight,
                                          child: Padding(
                                            padding: EdgeInsets.all(2),
                                            child: Icon(
                                              Icons.star_rounded,
                                              size: 14,
                                              color: Color(0xFFFFC107),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _PackChip(
                    selected: _tab == _InlineStickerTab.recent,
                    label: '⏱',
                    onTap: () => setState(() {
                      _tab = _InlineStickerTab.recent;
                      _selectedPackId = null;
                    }),
                  ),
                  _PackChip(
                    selected: _tab == _InlineStickerTab.favorites,
                    label: '★',
                    onTap: () => setState(() {
                      _tab = _InlineStickerTab.favorites;
                      _selectedPackId = null;
                    }),
                  ),
                  for (final pack in _packs)
                    _PackChip(
                      selected: _tab == _InlineStickerTab.pack &&
                          _selectedPackId == pack.id,
                      label: pack.title.isEmpty
                          ? '#'
                          : avatarLetterWithCustomEmoji(pack.title),
                      onTap: () => setState(() {
                        _tab = _InlineStickerTab.pack;
                        _selectedPackId = pack.id;
                        _selectedEmojiPackId = null;
                      }),
                    ),
                  for (final pack in _emojiPacks)
                    _PackChip(
                      selected: _tab == _InlineStickerTab.emoji &&
                          _selectedEmojiPackId == pack.id,
                      label: pack.title.isEmpty
                          ? 'Э'
                          : avatarLetterWithCustomEmoji(pack.title),
                      onTap: () => setState(() {
                        _tab = _InlineStickerTab.emoji;
                        _selectedEmojiPackId = pack.id;
                        _selectedPackId = null;
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerThumb {
  const _StickerThumb({
    required this.mediaUrl,
    this.emoji,
    this.stickerId,
    this.stickerType,
    this.customEmojiId,
  });

  final String mediaUrl;
  final String? emoji;
  final int? stickerId;
  final String? stickerType;
  final int? customEmojiId;
}

class _PackChip extends StatelessWidget {
  const _PackChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.18)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
