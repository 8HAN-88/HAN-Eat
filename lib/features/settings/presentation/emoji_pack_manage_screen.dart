import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/emoji_pack_models.dart';
import '../../../services/emoji_pack_service.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/server_config.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/stars_pay_helper.dart';
import '../../subscription/creator_upsell.dart';

class EmojiPackManageScreen extends StatefulWidget {
  const EmojiPackManageScreen({super.key, required this.packId});

  final int packId;

  @override
  State<EmojiPackManageScreen> createState() => _EmojiPackManageScreenState();
}

class _EmojiPackManageScreenState extends State<EmojiPackManageScreen> {
  EmojiPack? _pack;
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
      final pack = await EmojiPackService.getPack(widget.packId);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _loading = false;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _addEmoji() async {
    final pack = _pack;
    if (pack == null || !pack.isOwned || _saving) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 256,
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
      await EmojiPackService.addEmoji(packId: pack.id, mediaUrl: url);
      await _load();
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEmoji(CustomEmojiItem item) async {
    final pack = _pack;
    if (pack == null || !pack.isOwned) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить эмодзи?'),
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
      await EmojiPackService.deleteEmoji(packId: pack.id, emojiId: item.id);
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

  Future<void> _setPrice() async {
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
            helperText: 'Комиссия 5%, до 20 ★ не берётся. Снять пак можно бесплатно.',
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
    if (price > 0 && !hasFlexFeature('emoji_pack_publish')) {
      await showCreatorUpsell(context);
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await EmojiPackService.listPackForSale(
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

  Future<void> _buy() async {
    final pack = _pack;
    if (pack == null || pack.isOwned || pack.isPurchased) return;
    if (pack.priceStars <= 0) return;
    final ok = await confirmStarsSpend(
      context,
      title: 'Купить «${pack.title}»',
      body: 'Автор ${pack.authorLabel} · комиссия ${pack.feeStars} ★',
      amountStars: pack.priceStars,
      confirmLabel: 'Купить',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await EmojiPackService.buyPack(pack.id);
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
    setState(() => _saving = true);
    try {
      await EmojiPackService.installPack(pack.id);
      await _load();
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

  Future<void> _editPack() async {
    final pack = _pack;
    if (pack == null || !pack.isOwned) return;
    final titleCtrl = TextEditingController(text: pack.title);
    var isPublic = pack.isPublic;
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
      final updated = await EmojiPackService.updatePack(
        packId: pack.id,
        title: titleCtrl.text.trim(),
        isPublic: isPublic,
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

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final pack = _pack;
    if (pack == null || !pack.isOwned) return;
    final items = [...pack.items];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    setState(() {
      _pack = pack.copyWith(items: items, itemsCount: items.length);
    });
    try {
      await EmojiPackService.reorderEmojis(
        packId: pack.id,
        emojiIds: items.map((e) => e.id).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
      await _load();
    }
  }

  Future<void> _uninstall() async {
    final pack = _pack;
    if (pack == null || pack.isOwned || !pack.isInstalled) return;
    setState(() => _saving = true);
    try {
      await EmojiPackService.uninstallPack(pack.id);
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

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Эмодзи-пак'),
        actions: [
          if (pack?.shareLink != null)
            IconButton(
              onPressed: () => Share.share(pack!.shareLink!),
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Поделиться паком',
            ),
          if (pack?.isOwned == true)
            IconButton(
              onPressed: _saving ? null : _setPrice,
              icon: const Icon(Icons.sell_outlined),
              tooltip: 'Цена',
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
              onPressed: _saving ? null : _addEmoji,
              tooltip: 'Добавить эмодзи',
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pack == null
              ? const Center(child: Text('Пак не найден'))
              : Column(
                  children: [
                    if (_saving) const LinearProgressIndicator(minHeight: 2),
                    ListTile(
                      title: Text(pack.title),
                      subtitle: Text(
                        [
                          'Автор ${pack.authorLabel}',
                          '${pack.items.length} эмодзи',
                          if (pack.priceStars > 0) '${pack.priceStars} ★',
                        ].join(' · '),
                      ),
                    ),
                    if (!pack.isOwned && !pack.isPurchased && pack.priceStars > 0)
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
                        pack.priceStars <= 0)
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
                      child: pack.isOwned
                          ? ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                              itemCount: pack.items.length,
                              onReorder: _onReorder,
                              itemBuilder: (context, i) {
                                final item = pack.items[i];
                                return ListTile(
                                  key: ValueKey('emoji_${item.id}'),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      ServerConfig.resolveMediaUrl(
                                        item.mediaUrl,
                                      ),
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(
                                        Icons.broken_image_outlined,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    item.shortcode?.isNotEmpty == true
                                        ? item.shortcode!
                                        : '#${item.id}',
                                  ),
                                  trailing: IconButton(
                                    onPressed: _saving
                                        ? null
                                        : () => _deleteEmoji(item),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                );
                              },
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
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
                  ],
                ),
    );
  }
}
