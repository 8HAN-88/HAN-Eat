import 'package:flutter/material.dart';

import '../../../../models/chat_models.dart';
import '../../../../services/chat_service.dart';
import '../../../../utils/api_error_parser.dart';
import '../../../subscription/creator_upsell.dart';
import '../../../../widgets/app_avatar.dart';

Future<void> showChatMessageReadersSheet(
  BuildContext context, {
  required int conversationId,
  required int messageId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ChatMessageReadersSheet(
      conversationId: conversationId,
      messageId: messageId,
    ),
  );
}

class _ChatMessageReadersSheet extends StatefulWidget {
  const _ChatMessageReadersSheet({
    required this.conversationId,
    required this.messageId,
  });

  final int conversationId;
  final int messageId;

  @override
  State<_ChatMessageReadersSheet> createState() =>
      _ChatMessageReadersSheetState();
}

class _ChatMessageReadersSheetState extends State<_ChatMessageReadersSheet> {
  bool _loading = true;
  Object? _error;
  List<ChatUserBrief> _readers = const [];
  int _otherCount = 0;

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
      final result = await ChatService.listMessageReaders(
        conversationId: widget.conversationId,
        messageId: widget.messageId,
      );
      if (!mounted) return;
      setState(() {
        _readers = result.readers;
        _otherCount = result.otherMemberCount;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = _loading
        ? 'Загрузка…'
        : (_readers.isEmpty
            ? 'Пока никто не прочитал'
            : 'Прочитали ${_readers.length}'
                '${_otherCount > 0 ? ' из $_otherCount' : ''}');

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.42,
        minChildSize: 0.28,
        maxChildSize: 0.85,
        builder: (context, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Кто прочитал',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
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
                                  Text(
                                    userVisibleError(_error!),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _load,
                                    child: const Text('Повторить'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _readers.isEmpty
                            ? ListView(
                                controller: scrollController,
                                children: const [
                                  SizedBox(height: 48),
                                  Icon(Icons.done_all, size: 40),
                                  SizedBox(height: 12),
                                  Text(
                                    'Ещё никто не отметил сообщение как прочитанное',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: _readers.length,
                                itemBuilder: (context, index) {
                                  final user = _readers[index];
                                  return ListTile(
                                    leading: AppUserAvatar(
                                      imageUrl: user.avatarUrl,
                                      displayName: user.displayName,
                                      radius: 22,
                                    ),
                                    title: Text(user.displayName),
                                    subtitle: user.username != null &&
                                            user.username!.trim().isNotEmpty
                                        ? Text(
                                            user.username!.startsWith('@')
                                                ? user.username!
                                                : '@${user.username}',
                                          )
                                        : null,
                                  );
                                },
                              ),
              ),
            ],
          );
        },
      ),
    );
  }
}
