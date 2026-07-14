import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/sticker_models.dart';
import '../../../services/server_config.dart';
import '../../../services/sticker_service.dart';
import '../../../utils/api_error_parser.dart';

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
      final updated = await StickerService.updatePack(
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
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
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
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
