import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/sticker_models.dart';
import '../../../services/server_config.dart';
import '../../../services/sticker_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

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
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_load()),
          ),
        ),
      );
    }
  }

  Future<void> _install() async {
    final pack = _pack;
    if (pack == null) return;
    setState(() => _busy = true);
    try {
      await StickerService.installPack(pack.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_install()),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Предпросмотр пака'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (pack == null
              ? AppEmptyState(
                  icon: Icons.sticky_note_2_outlined,
                  title: 'Пак не найден',
                  subtitle: 'Ссылка устарела или пак удалили',
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Повторить'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Назад'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              pack.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          Text('${pack.stickers.length} стик.'),
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
                            onPressed:
                                _busy || pack.isInstalled ? null : _install,
                            icon:
                                const Icon(Icons.download_for_offline_outlined),
                            label: Text(
                              pack.isInstalled
                                  ? 'Уже установлен'
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
