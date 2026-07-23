import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Preview selected gallery media, add a caption, then send (Telegram-style).
Future<ChatMediaComposeResult?> showChatMediaCompose(
  BuildContext context, {
  required List<XFile> files,
}) {
  if (files.isEmpty) return Future.value(null);
  return showModalBottomSheet<ChatMediaComposeResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ChatMediaComposeSheet(files: files),
  );
}

class ChatMediaComposeResult {
  const ChatMediaComposeResult({
    required this.files,
    required this.caption,
    this.schedule = false,
  });

  final List<XFile> files;
  final String caption;
  final bool schedule;
}

class _ChatMediaComposeSheet extends StatefulWidget {
  const _ChatMediaComposeSheet({required this.files});

  final List<XFile> files;

  @override
  State<_ChatMediaComposeSheet> createState() => _ChatMediaComposeSheetState();
}

class _ChatMediaComposeSheetState extends State<_ChatMediaComposeSheet> {
  late final PageController _page;
  late final TextEditingController _caption;
  late List<XFile> _files;
  final Map<int, Uint8List?> _previews = {};
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _files = List<XFile>.from(widget.files);
    _page = PageController();
    _caption = TextEditingController();
    unawaited(_loadPreviews());
  }

  Future<void> _loadPreviews() async {
    for (var i = 0; i < _files.length; i++) {
      try {
        final file = _files[i];
        final name = file.name.toLowerCase();
        final isVideo = name.endsWith('.mp4') ||
            name.endsWith('.mov') ||
            name.endsWith('.webm') ||
            (file.mimeType?.startsWith('video/') ?? false);
        if (isVideo) {
          _previews[i] = null;
          continue;
        }
        final bytes = await file.readAsBytes();
        if (bytes.lengthInBytes > 12 * 1024 * 1024) {
          _previews[i] = null;
        } else {
          _previews[i] = bytes;
        }
      } catch (_) {
        _previews[i] = null;
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _page.dispose();
    _caption.dispose();
    super.dispose();
  }

  bool _isVideo(XFile file) {
    final name = file.name.toLowerCase();
    final mime = file.mimeType ?? '';
    return mime.startsWith('video/') ||
        name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.avi');
  }

  void _removeCurrent() {
    if (_files.length <= 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _files.removeAt(_index);
      _previews.clear();
      if (_index >= _files.length) _index = _files.length - 1;
    });
    unawaited(_loadPreviews());
    _page.jumpToPage(_index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Material(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.78,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                      Expanded(
                        child: Text(
                          _files.length == 1
                              ? 'Отправить'
                              : 'Отправить ${_files.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Удалить',
                        onPressed: _removeCurrent,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    itemCount: _files.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      if (_isVideo(file)) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.videocam_rounded,
                                size: 64,
                                color: scheme.primary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                file.name.isEmpty ? 'Видео' : file.name,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }
                      final bytes = _previews[index];
                      if (bytes == null) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      return InteractiveViewer(
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      );
                    },
                  ),
                ),
                if (_files.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${_index + 1} / ${_files.length}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _caption,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: 'Подпись…',
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.55),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Отложить',
                        onPressed: () {
                          Navigator.pop(
                            context,
                            ChatMediaComposeResult(
                              files: List<XFile>.from(_files),
                              caption: _caption.text.trim(),
                              schedule: true,
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.schedule_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                        ),
                        onPressed: () {
                          Navigator.pop(
                            context,
                            ChatMediaComposeResult(
                              files: List<XFile>.from(_files),
                              caption: _caption.text.trim(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
