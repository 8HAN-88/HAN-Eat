import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import '../../../services/paid_features_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/stars_pay_helper.dart';

class ChatInviteJoinScreen extends StatefulWidget {
  const ChatInviteJoinScreen({
    super.key,
    required this.token,
  });

  final String token;

  @override
  State<ChatInviteJoinScreen> createState() => _ChatInviteJoinScreenState();
}

class _ChatInviteJoinScreenState extends State<ChatInviteJoinScreen> {
  bool _loading = true;
  String? _error;
  int? _paidConversationId;
  int _paidPriceStars = 0;
  String? _paidTitle;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    if (AuthService.instance.currentUser == null) {
      if (mounted) context.go('/login');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _paidConversationId = null;
    });
    try {
      final result = await ChatService.joinGroupByInviteToken(widget.token);
      if (!mounted) return;
      if (result.status == 'requested') {
        setState(() {
          _loading = false;
          _error =
              'Заявка отправлена. Дождитесь одобрения администратора группы.';
        });
        return;
      }
      final conv = result.conversation;
      if (conv == null) {
        setState(() {
          _loading = false;
          _error = 'Не удалось открыть группу';
        });
        return;
      }
      context.go('/chats/thread/${conv.id}');
    } catch (e) {
      if (!mounted) return;
      final paid = _paidJoinFromError(e);
      setState(() {
        _loading = false;
        _error = userVisibleError(e);
        _paidConversationId = paid?.$1;
        _paidPriceStars = paid?.$2 ?? 0;
        _paidTitle = paid?.$3;
      });
    }
  }

  (int, int, String?)? _paidJoinFromError(Object error) {
    if (error is! ApiClientException) return null;
    if (error.code != 'group_paid_required' && error.statusCode != 402) {
      return null;
    }
    final details = error.details;
    final rawId = details?['conversation_id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId');
    if (id == null || id <= 0) return null;
    final rawPrice = details?['monthly_price_stars'];
    final price = rawPrice is num
        ? rawPrice.toInt()
        : int.tryParse('$rawPrice') ?? 0;
    final title = details?['title'] as String?;
    return (id, price, title);
  }

  Future<void> _subscribeAndJoin() async {
    final conversationId = _paidConversationId;
    if (conversationId == null) return;
    final price = _paidPriceStars;
    final title = (_paidTitle ?? '').trim();
    final ok = await confirmStarsSpend(
      context,
      title: 'Подписка на группу',
      body: title.isEmpty
          ? 'Доступ на 30 дней. С баланса спишется $price ★.'
          : '«$title» · доступ на 30 дней. С баланса спишется $price ★.',
      amountStars: price,
      confirmLabel: 'Оплатить',
    );
    if (!ok || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await PaidFeaturesService.subscribeGroup(conversationId);
      if (!mounted) return;
      await _join();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await showStarsRequiredSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paidId = _paidConversationId;
    return Scaffold(
      appBar: AppBar(title: const Text('Приглашение в группу')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 14),
                    Text('Вступаем в группу...'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      paidId != null
                          ? Icons.workspace_premium_outlined
                          : Icons.link_off_outlined,
                      size: 42,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _error ?? 'Не удалось обработать приглашение',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    if (paidId != null) ...[
                      FilledButton(
                        onPressed: _subscribeAndJoin,
                        child: Text(
                          _paidPriceStars > 0
                              ? 'Оплатить $_paidPriceStars ★ и вступить'
                              : 'Оплатить и вступить',
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    FilledButton.tonal(
                      onPressed: _join,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
