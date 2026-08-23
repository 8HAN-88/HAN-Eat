import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/sticker_models.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/server_config.dart';
import '../../../services/sticker_service.dart';
import '../../../services/share_link_service.dart';
import '../../../services/custom_emoji_registry.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/highlighted_text.dart';
import '../../../widgets/stars_pay_helper.dart';
import '../../subscription/creator_upsell.dart';

class StickerPackManageScreen extends StatefulWidget {
  const StickerPackManageScreen({
    super.key,
    required this.packId,
  });

  final int packId;

  @override
  State<StickerPackManageScreen> createState() =>
      _StickerPackManageScreenState();
}

class _StickerPackManageScreenState extends State<StickerPackManageScreen> {
  StickerPack? _pack;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pack = await StickerService.getPack(widget.packId);
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

  Future<void> _editPack() async {
    final pack = _pack;
    if (pack == null || !pack.isOwned) return;
    final titleCtrl = TextEditingController(text: pack.title);
    var isPublic = pack.isPublic;
    var isPremium = pack.isPremium;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Настройки пака'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              SwitchListTile(
                value: isPublic,
                onChanged: (v) => setStateDialog(() => isPublic = v),
                title: const Text('Публичный'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: isPremium,
                onChanged: (v) {
                  if (v && !hasFlexFeature('premium_stickers')) {
                    Navigator.pop(ctx, false);
                    showCreatorUpsell(context);
                    return;
                  }
                  setStateDialog(() => isPremium = v);
                },
                title: const Text('Премиум-пак'),
                subtitle: const Text('Установка и отправка с уровня 43'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      final updated = await StickerService.updatePack(
        packId: pack.id,
        title: titleCtrl.text.trim(),
        isPublic: isPublic,
        isPremium: isPremium,
      );
      if (!mounted) return;
      setState(() {
        _pack = updated;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _deleteSticker(StickerItem item) async {
    final pack = _pack;
    if (pack == null || !pack.isOwned) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить стикер?'),
        content: const Text('Стикер будет удалён из пака.'),
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
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await StickerService.deleteSticker(
        packId: pack.id,
        stickerId: item.id,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addStaticSticker() async {
    final pack = _pack;
    if (pack == null || _saving) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 768,
    );
    if (!mounted || picked == null) return;
    setState(() => _saving = true);
    try {
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: picked,
        fileType: 'image',
      );
      final url = uploaded.url?.trim();
      if (url == null || url.isEmpty) {
        throw StateError('upload_missing_url');
      }
      await StickerService.addStickerToPack(
        packId: pack.id,
        mediaUrl: url,
        stickerType: 'static',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addAnimatedSticker() async {
    if (SubscriptionStatusCache.peek()?.hasFeature('animated_stickers') !=
        true) {
      await showCreatorUpsell(context);
      return;
    }
    final pack = _pack;
    if (pack == null || _saving) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const [
        'gif',
        'webp',
        'webm',
        'mp4',
        'mov',
        'json',
        'lottie',
      ],
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final xFile = kIsWeb
        ? (picked.bytes == null
            ? null
            : XFile.fromData(
                picked.bytes!,
                name: picked.name,
              ))
        : (picked.path == null ? null : XFile(picked.path!));
    if (xFile == null) return;
    final lower = picked.name.toLowerCase();
    final fileType = lower.endsWith('.webm') ||
            lower.endsWith('.mp4') ||
            lower.endsWith('.mov')
        ? 'video'
        : lower.endsWith('.json') || lower.endsWith('.lottie')
            ? 'document'
            : 'image';
    setState(() => _saving = true);
    try {
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: xFile,
        fileType: fileType,
      );
      final url = uploaded.url?.trim();
      if (url == null || url.isEmpty) {
        throw StateError('upload_missing_url');
      }
      await StickerService.addStickerToPack(
        packId: pack.id,
        mediaUrl: url,
        stickerType: 'animated',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setSalePrice() async {
    final pack = _pack;
    if (pack == null || !pack.isOwned) return;
    final ctrl = TextEditingController(
      text: pack.priceStars > 0 ? '${pack.priceStars}' : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Цена в магазине'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Stars (0 — снять с витрины)',
            helperText: 'Комиссия 5%, до 20 ★ бесплатно. Снять пак можно без flex.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final price = int.tryParse(ctrl.text.trim()) ?? 0;
    if (price > 0 && !hasFlexFeature('sticker_pack_sell')) {
      await showCreatorUpsell(context);
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await StickerService.listPackForSale(
        packId: pack.id,
        priceStars: price < 0 ? 0 : price,
      );
      if (!mounted) return;
      setState(() {
        _pack = updated;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _showAddStickerMenu() async {
    if (_pack == null || !_pack!.isOwned || _saving) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Статический стикер'),
              subtitle: const Text('Из галереи'),
              onTap: () => Navigator.pop(ctx, 'static'),
            ),
            ListTile(
              leading: const Icon(Icons.gif_box_outlined),
              title: const Text('Анимированный стикер'),
              subtitle: const Text('GIF, WebP, WebM, Lottie…'),
              onTap: () => Navigator.pop(ctx, 'animated'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'static') {
      await _addStaticSticker();
    } else if (choice == 'animated') {
      await _addAnimatedSticker();
    }
  }

  Future<void> _buy() async {
    final pack = _pack;
    if (pack == null || pack.isOwned || pack.isPurchased) return;
    if (pack.priceStars <= 0) return;
    final ok = await confirmStarsSpend(
      context,
      title: 'Купить «${previewTextWithCustomEmoji(pack.title)}»',
      body: pack.ownerName.trim().isEmpty
          ? '${pack.priceStars} ★'
          : 'Автор ${previewTextWithCustomEmoji(pack.ownerName)} · комиссия ${pack.feeStars} ★',
      amountStars: pack.priceStars,
      confirmLabel: 'Купить',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await StickerService.buyPack(
        pack.id,
        expectedPriceStars: pack.priceStars,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      if (offerPackStoreIfRequired(context, e)) return;
      await showStarsRequiredSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _installFree() async {
    final pack = _pack;
    if (pack == null) return;
    if (pack.isPremium && !hasFlexFeature('premium_stickers')) {
      await showCreatorUpsell(context);
      return;
    }
    setState(() => _saving = true);
    try {
      await StickerService.installPack(pack.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      if (offerPackStoreIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uninstall() async {
    final pack = _pack;
    if (pack == null || pack.isOwned || !pack.isInstalled) return;
    setState(() => _saving = true);
    try {
      await StickerService.uninstallPack(pack.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final pack = _pack;
    if (pack == null || !pack.isOwned) return;
    final items = [...pack.stickers];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    setState(() {
      _pack = pack.copyWith(
        stickers: items,
        stickersCount: items.length,
      );
    });
    try {
      await StickerService.reorderStickers(
        packId: pack.id,
        stickerIds: items.map((e) => e.id).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление стикерпаком'),
        actions: [
          IconButton(
            onPressed: (_saving || pack?.shareLink == null)
                ? null
                : () => Share.share(
                    ShareLinkService.packShareText(
                      pack!.shareLink!,
                      isPublic: pack.isPublic,
                    ),
                  ),
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Поделиться паком',
          ),
          if (pack?.isOwned == true)
            IconButton(
              onPressed: _saving ? null : _setSalePrice,
              icon: const Icon(Icons.sell_outlined),
              tooltip: 'Цена в магазине',
            ),
          if (pack?.isOwned == true)
            IconButton(
              onPressed: _saving ? null : _editPack,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Редактировать',
            ),
        ],
      ),
      floatingActionButton: pack?.isOwned == true
          ? FloatingActionButton(
              onPressed: _saving ? null : _showAddStickerMenu,
              tooltip: 'Добавить стикер',
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (pack == null
              ? const Center(child: Text('Стикерпак не найден'))
              : Column(
                  children: [
                    if (_saving) const LinearProgressIndicator(minHeight: 2),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: HighlightedText(
                              text:
                                  '${pack.title} · ${pack.stickers.length} стик.',
                              style: Theme.of(context).textTheme.titleMedium ??
                                  const TextStyle(fontSize: 16),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            pack.priceStars > 0
                                ? '${pack.priceStars} ★'
                                : (pack.isPublic ? 'Публичный' : 'Приватный'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (!pack.isOwned &&
                        !pack.isPurchased &&
                        pack.isOnSale)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ? null : _buy,
                            child: Text('Купить ${pack.priceStars} ★'),
                          ),
                        ),
                      )
                    else if (!pack.isOwned &&
                        !pack.isInstalled &&
                        (pack.priceStars <= 0 || pack.isPurchased))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ? null : _installFree,
                            child: const Text('Установить'),
                          ),
                        ),
                      )
                    else if (!pack.isOwned && pack.isInstalled)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _saving ? null : _uninstall,
                            child: const Text('Удалить из своих'),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                        itemCount: pack.stickers.length,
                        onReorder: pack.isOwned ? _onReorder : (_, __) {},
                        itemBuilder: (context, index) {
                          final item = pack.stickers[index];
                          return ListTile(
                            key: ValueKey('sticker_${item.id}'),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                ServerConfig.resolveMediaUrl(item.mediaUrl),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                            title: HighlightedText(
                              text: item.emoji?.trim().isNotEmpty == true
                                  ? item.emoji!
                                  : 'Стикер #${item.id}',
                              style: Theme.of(context).textTheme.bodyLarge ??
                                  const TextStyle(fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(item.stickerType),
                            trailing: pack.isOwned
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: _saving
                                        ? null
                                        : () => _deleteSticker(item),
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                )),
    );
  }
}
