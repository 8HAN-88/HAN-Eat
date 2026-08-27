import 'package:flutter/material.dart';

import '../../../../models/chat_poll.dart';
import '../../../../services/chat_service.dart';
import '../../../../utils/api_error_parser.dart';
import '../../../../widgets/app_avatar.dart';
import '../../../../widgets/highlighted_text.dart';

Future<void> showChatPollVotersSheet(
  BuildContext context, {
  required int conversationId,
  required int messageId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ChatPollVotersSheet(
      conversationId: conversationId,
      messageId: messageId,
    ),
  );
}

class _ChatPollVotersSheet extends StatefulWidget {
  const _ChatPollVotersSheet({
    required this.conversationId,
    required this.messageId,
  });

  final int conversationId;
  final int messageId;

  @override
  State<_ChatPollVotersSheet> createState() => _ChatPollVotersSheetState();
}

class _ChatPollVotersSheetState extends State<_ChatPollVotersSheet> {
  bool _loading = true;
  String? _error;
  ChatPollVotersResult? _result;

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
      final result = await ChatService.listPollVoters(
        conversationId: widget.conversationId,
        messageId: widget.messageId,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e, fallback: 'Не удалось загрузить голоса');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, controller) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error != null) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.all(24),
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _load,
                    child: const Text('Повторить'),
                  ),
                ),
              ],
            );
          }
          if (result == null || result.total == 0) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.all(24),
              children: const [
                Text('Пока никто не проголосовал', textAlign: TextAlign.center),
              ],
            );
          }
          return ListView(
            controller: controller,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Голоса · ${result.total}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final option in result.options) ...[
                if (option.voters.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: HighlightedText(
                      text: option.text,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final voter in option.voters)
                    ListTile(
                      leading: AppUserAvatar(
                        radius: 18,
                        imageUrl: voter.avatarUrl,
                        displayName: voter.displayName,
                      ),
                      title: HighlightedText(
                        text: voter.displayName,
                        style: Theme.of(context).textTheme.bodyLarge ??
                            const TextStyle(fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: voter.username == null
                          ? null
                          : Text(
                              voter.username!.startsWith('@')
                                  ? voter.username!
                                  : '@${voter.username}',
                            ),
                    ),
                ],
              ],
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }
}
