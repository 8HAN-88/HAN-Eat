import 'package:flutter/material.dart';

import '../services/product_analytics.dart';
import '../services/report_service.dart';
import '../utils/api_error_parser.dart';

/// Диалог «Пожаловаться» с причинами из ТЗ.
Future<bool?> showReportContentDialog(
  BuildContext context, {
  required Future<void> Function(String reason, String? comment) onSubmit,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _ReportContentDialog(onSubmit: onSubmit),
  );
}

class _ReportContentDialog extends StatefulWidget {
  const _ReportContentDialog({required this.onSubmit});

  final Future<void> Function(String reason, String? comment) onSubmit;

  @override
  State<_ReportContentDialog> createState() => _ReportContentDialogState();
}

class _ReportContentDialogState extends State<_ReportContentDialog> {
  static const _reasons = <String, String>{
    'spam': 'Спам',
    'harassment': 'Оскорбления',
    'nsfw': 'NSFW',
    'violence': 'Насилие',
    'misinformation': 'Ложная информация',
    'scam': 'Мошенничество',
    'inappropriate': 'Неподходящий контент',
    'other': 'Другое',
  };

  String _reason = 'spam';
  final _comment = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Пожаловаться'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Причина'),
            const SizedBox(height: 8),
            ..._reasons.entries.map(
              (e) => RadioListTile<String>(
                title: Text(e.value),
                value: e.key,
                groupValue: _reason,
                onChanged: _loading
                    ? null
                    : (v) {
                        if (v != null) setState(() => _reason = v);
                      },
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            TextField(
              controller: _comment,
              decoration: const InputDecoration(
                labelText: 'Комментарий (необязательно)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              enabled: !_loading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Отправить'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final c = _comment.text.trim();
      await widget.onSubmit(
        _reason,
        c.isEmpty ? null : c,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiClientException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось отправить жалобу'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось отправить жалобу'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

Future<void> _showReportSuccess(BuildContext context) {
  return Future.microtask(() {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Жалоба отправлена. Спасибо.')),
    );
  });
}

Future<void> _logReportSubmitted({
  required String entityType,
  required int entityId,
  required String reason,
}) {
  return ProductAnalytics.logEvent(
    eventType: 'report_submitted',
    entityType: entityType,
    entityId: entityId,
    metadata: {'reason': reason},
  );
}

/// Жалоба на пост через API.
Future<void> reportPostWithDialog(BuildContext context, int postId) async {
  String? submittedReason;
  final ok = await showReportContentDialog(
    context,
    onSubmit: (reason, comment) async {
      submittedReason = reason;
      await ReportService.reportPost(
        postId: postId,
        reason: reason,
        comment: comment,
      );
    },
  );
  if (ok == true) {
    await _logReportSubmitted(
      entityType: 'post',
      entityId: postId,
      reason: submittedReason ?? 'other',
    );
    await _showReportSuccess(context);
  }
}

/// Жалоба на комментарий через API.
Future<void> reportCommentWithDialog(BuildContext context, int commentId) async {
  String? submittedReason;
  final ok = await showReportContentDialog(
    context,
    onSubmit: (reason, comment) async {
      submittedReason = reason;
      await ReportService.reportComment(
        commentId: commentId,
        reason: reason,
        comment: comment,
      );
    },
  );
  if (ok == true) {
    await _logReportSubmitted(
      entityType: 'comment',
      entityId: commentId,
      reason: submittedReason ?? 'other',
    );
    await _showReportSuccess(context);
  }
}

/// Жалоба на рилс: API-пост по числовому id, иначе Firestore community video.
Future<void> reportReelOrVideoWithDialog(
  BuildContext context,
  String videoDocId,
) async {
  final postId = int.tryParse(videoDocId);
  if (postId != null) {
    await reportPostWithDialog(context, postId);
    return;
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Жалоба на это видео недоступна: обновите приложение или откройте рилс из ленты API.',
      ),
    ),
  );
}

/// Жалоба на канал через API.
Future<void> reportChannelWithDialog(BuildContext context, int channelId) async {
  String? submittedReason;
  final ok = await showReportContentDialog(
    context,
    onSubmit: (reason, comment) async {
      submittedReason = reason;
      await ReportService.reportChannel(
        channelId: channelId,
        reason: reason,
        comment: comment,
      );
    },
  );
  if (ok == true) {
    await _logReportSubmitted(
      entityType: 'channel',
      entityId: channelId,
      reason: submittedReason ?? 'other',
    );
    await _showReportSuccess(context);
  }
}
