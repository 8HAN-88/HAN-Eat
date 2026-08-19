import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/sticker_models.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/server_config.dart';
import '../../../services/sticker_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../services/subscription_status_cache.dart';
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
    if (pack == null) return;
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
    if (pack == null) return;
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

  Future<void> _showAddStickerMenu() async {
    if (_pack == null || _saving) return;
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

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final pack = _pack;
    if (pack == null) return;
    final items = [...pack.stickers];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    setState(() {
      _pack = StickerPack(
        id: pack.id,
        title: pack.title,
        slug: pack.slug,
        ownerUserId: pack.ownerUserId,
        isPublic: pack.isPublic,
        isInstalled: pack.isInstalled,
        stickers: items,
        stickersCount: pack.stickersCount,
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
                : () => Share.share(pack!.shareLink!),
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Поделиться паком',
          ),
          IconButton(
            onPressed: (_saving || pack == null) ? null : _editPack,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Редактировать',
          ),
        ],
      ),
      floatingActionButton: pack == null
          ? null
          : FloatingActionButton(
              onPressed: _saving ? null : _showAddStickerMenu,
              tooltip: 'Добавить стикер',
              child: const Icon(Icons.add),
            ),
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
                            child: Text(
                              '${pack.title} · ${pack.stickers.length} стик.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            pack.isPublic ? 'Публичный' : 'Приватный',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                        itemCount: pack.stickers.length,
                        onReorder: _onReorder,
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
                            title: Text(
                              item.emoji?.trim().isNotEmpty == true
                                  ? item.emoji!
                                  : 'Стикер #${item.id}',
                            ),
                            subtitle: Text(item.stickerType),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed:
                                  _saving ? null : () => _deleteSticker(item),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                )),
    );
  }
}
