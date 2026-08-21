import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/sticker_models.dart';
import '../../../services/server_config.dart';
import '../../../services/sticker_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/stars_pay_helper.dart';
import '../../subscription/creator_upsell.dart';

class StickerPackPreviewScreen extends StatefulWidget {
  const StickerPackPreviewScreen({
    super.key,
    required this.slug,
  });

  final String slug;

  @override
  State<StickerPackPreviewScreen> createState() =>
      _StickerPackPreviewScreenState();
}

class _StickerPackPreviewScreenState extends State<StickerPackPreviewScreen> {
  StickerPack? _pack;
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
      final pack = await StickerService.getPackBySlug(widget.slug);
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
    if (pack.isPremium && !hasFlexFeature('premium_stickers')) {
      await showCreatorUpsell(context);
      return;
    }
    final needsBuy =
        pack.priceStars > 0 && !pack.isOwned && !pack.isPurchased;
    if (needsBuy) {
      final ok = await confirmStarsSpend(
        context,
        title: 'Купить «${pack.title}»',
        body: [
          if (pack.ownerName.trim().isNotEmpty) 'Автор ${pack.ownerName}',
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
        await StickerService.buyPack(
          pack.id,
          expectedPriceStars: pack.priceStars,
        );
      } else {
        await StickerService.installPack(pack.id);
      }
      if (!mounted) return;
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
      await StickerService.uninstallPack(pack.id);
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
        title: const Text('Предпросмотр пака'),
        actions: [
          if (pack?.shareLink != null)
            IconButton(
              onPressed: () => Share.share(pack!.shareLink!),
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
                          if (pack.isPremium)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(
                                pack.isInstalled
                                    ? Icons.workspace_premium_outlined
                                    : Icons.lock_outline,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              pack.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          Text(
                            pack.ownerName.trim().isEmpty
                                ? '${pack.stickers.length} стик.'
                                : '${pack.stickers.length} стик. · ${pack.ownerName}',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: pack.stickers.length,
                        itemBuilder: (_, i) {
                          final s = pack.stickers[i];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              ServerConfig.resolveMediaUrl(s.mediaUrl),
                              fit: BoxFit.cover,
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
                                      : (pack.priceStars > 0 &&
                                              !pack.isPurchased)
                                          ? 'Купить ${pack.priceStars} ★'
                                          : 'Добавить стикерпак',
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
