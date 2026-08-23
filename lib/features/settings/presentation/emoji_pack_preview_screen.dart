import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/emoji_pack_models.dart';
import '../../../services/custom_emoji_registry.dart';
import '../../../services/emoji_pack_service.dart';
import '../../../services/server_config.dart';
import '../../../services/share_link_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/highlighted_text.dart';
import '../../../widgets/stars_pay_helper.dart';
import '../../subscription/creator_upsell.dart';

class EmojiPackPreviewScreen extends StatefulWidget {
  const EmojiPackPreviewScreen({
    super.key,
    required this.slug,
  });

  final String slug;

  @override
  State<EmojiPackPreviewScreen> createState() => _EmojiPackPreviewScreenState();
}

class _EmojiPackPreviewScreenState extends State<EmojiPackPreviewScreen> {
  EmojiPack? _pack;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pack = await EmojiPackService.getPackBySlug(widget.slug);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _install() async {
    final pack = _pack;
    if (pack == null) return;
    final needsBuy =
        pack.isOnSale && !pack.isOwned && !pack.isPurchased;
    if (needsBuy) {
      final ok = await confirmStarsSpend(
        context,
        title: 'Купить «${previewTextWithCustomEmoji(pack.title)}»',
        body: [
          if (pack.authorLabel.trim().isNotEmpty)
            'Автор ${previewTextWithCustomEmoji(pack.authorLabel)}',
          '${pack.priceStars} ★',
          if (pack.feeStars > 0) 'комиссия ${pack.feeStars} ★',
        ].join(' · '),
        amountStars: pack.priceStars,
        confirmLabel: 'Купить',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (needsBuy) {
        await EmojiPackService.buyPack(
          pack.id,
          expectedPriceStars: pack.priceStars,
        );
      } else {
        await EmojiPackService.installPack(pack.id);
      }
      if (!mounted) return;
      if (!hasFlexFeature('custom_emoji')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Пак установлен. Чтобы вставлять эмодзи в сообщения, нужен уровень 69',
            ),
          ),
        );
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      if (offerPackStoreIfRequired(context, e)) return;
      await showStarsRequiredSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uninstall() async {
    final pack = _pack;
    if (pack == null || pack.isOwned || !pack.isInstalled) return;
    setState(() => _busy = true);
    try {
      await EmojiPackService.uninstallPack(pack.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Эмодзи-пак'),
        actions: [
          if (pack?.shareLink != null)
            IconButton(
              onPressed: () => Share.share(
                ShareLinkService.packShareText(
                  pack!.shareLink!,
                  isPublic: pack.isPublic,
                ),
              ),
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Поделиться паком',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (pack == null
              ? const Center(child: Text('Пак не найден'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: HighlightedText(
                              text: pack.title,
                              style: Theme.of(context).textTheme.titleLarge ??
                                  const TextStyle(fontSize: 22),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          HighlightedText(
                            text: pack.ownerName.trim().isEmpty
                                ? '${pack.items.length} эмодзи'
                                : '${pack.items.length} эмодзи · ${pack.authorLabel}',
                            style: Theme.of(context).textTheme.bodyMedium ??
                                const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: pack.items.length,
                        itemBuilder: (_, i) {
                          final item = pack.items[i];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              ServerConfig.resolveMediaUrl(item.mediaUrl),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : (pack.isOwned
                                    ? null
                                    : pack.isInstalled
                                        ? _uninstall
                                        : (pack.priceStars > 0 &&
                                                !pack.isPurchased &&
                                                !pack.isOnSale)
                                            ? null
                                            : _install),
                            icon: Icon(
                              pack.isInstalled && !pack.isOwned
                                  ? Icons.remove_circle_outline
                                  : Icons.download_for_offline_outlined,
                            ),
                            label: Text(
                              pack.isOwned
                                  ? 'Ваш пак'
                                  : pack.isInstalled
                                      ? 'Удалить из своих'
                                      : (pack.isOnSale && !pack.isPurchased)
                                          ? 'Купить ${pack.priceStars} ★'
                                          : (pack.priceStars > 0 &&
                                                  !pack.isPurchased)
                                              ? 'Сейчас не продаётся'
                                              : 'Добавить эмодзи-пак',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )),
    );
  }
}
