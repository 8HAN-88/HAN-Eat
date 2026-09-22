import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/app_invite_service.dart';
import '../../../services/pending_referral_store.dart';
import '../../../services/revenue_share_service.dart';
import '../../../utils/api_error_parser.dart';

class PartnerProgramScreen extends StatefulWidget {
  const PartnerProgramScreen({super.key, this.focusExtraAds = false});

  final bool focusExtraAds;

  @override
  State<PartnerProgramScreen> createState() => _PartnerProgramScreenState();
}

class _PartnerProgramScreenState extends State<PartnerProgramScreen> {
  RevenueShareSnapshot? _snap;
  Object? _error;
  bool _busy = false;
  final _cardPhone = TextEditingController();
  final _cardName = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cardPhone.dispose();
    _cardName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var snap = await RevenueShareApi.me();
      if (snap.referredById == null) {
        final pending = await PendingReferralStore.peek();
        if (pending != null) {
          try {
            snap = await RevenueShareApi.applyCode(pending);
          } on Object {
            // Ссылка просрочена, своя или уже недействительна — оставляем снимок.
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    }
  }

  Future<void> _toggleExtra(bool value) async {
    setState(() => _busy = true);
    try {
      final snap = await RevenueShareApi.setExtraAds(value);
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка скопирована')),
    );
  }

  Future<void> _share() async {
    final snap = _snap;
    if (snap == null) return;
    final box = context.findRenderObject() as RenderBox?;
    await AppInviteService.shareInvite(
      context,
      ref: snap.referralCode,
      shareOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  Future<void> _convertStars() async {
    final snap = _snap;
    if (snap == null || !snap.canConvertStars || _busy) return;
    final stars = snap.convertibleStars;
    final amount = stars * snap.kopecksPerStar;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Обменять на звёзды'),
        content: Text(
          'Зачислить $stars ★ за ${RevenueShareSnapshot.rub(amount)}? '
          'Сразу на баланс, без банка. Остаток меньше 0,80 ₽ останется.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Зачислить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final next = await RevenueShareApi.convertToStars();
      if (!mounted) return;
      setState(() {
        _snap = next;
        _busy = false;
      });
      final credited = next.lastPayout?.amountStars ?? stars;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Зачислено $credited ★')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _requestCard() async {
    final snap = _snap;
    if (snap == null || !snap.canRequestCard || _busy) return;
    _cardPhone.clear();
    _cardName.clear();
    var packet = snap.minCardKopecks;
    final all = snap.availableKopecks;
    final packets = <int>{
      snap.minCardKopecks,
      if (all >= 100000) 100000,
      all,
    }.toList()
      ..sort();
    final payload =
        await showDialog<({int? amount, String phone, String name})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('На карту / СБП'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'От ${RevenueShareSnapshot.rub(snap.minCardKopecks)}. '
                  'Заявка в очередь, деньги сразу в холде.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in packets)
                      ChoiceChip(
                        selected: packet == value,
                        label: Text(
                          value == all &&
                                  value != snap.minCardKopecks &&
                                  value != 100000
                              ? 'Всё ${RevenueShareSnapshot.rub(value)}'
                              : RevenueShareSnapshot.rub(value),
                        ),
                        onSelected: (_) => setLocal(() => packet = value),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cardPhone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Телефон СБП',
                    hintText: '+7 900 000-00-00',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _cardName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Имя получателя',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final phone = _cardPhone.text.trim();
                final name = _cardName.text.trim();
                String? error;
                if (phone.length < 10) {
                  error = 'Укажите телефон СБП (не меньше 10 цифр)';
                } else if (name.length < 2) {
                  error = 'Укажите имя получателя';
                }
                if (error != null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(error)),
                  );
                  return;
                }
                Navigator.pop(
                  ctx,
                  (amount: packet, phone: phone, name: name),
                );
              },
              child: const Text('Отправить'),
            ),
          ],
        ),
      ),
    );
    if (payload == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final next = await RevenueShareApi.requestCardPayout(
        amountKopecks: payload.amount,
        phone: payload.phone,
        recipientName: payload.name,
      );
      if (!mounted) return;
      setState(() {
        _snap = next;
        _busy = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Заявка отправлена')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  String? _invitedBy(RevenueShareSnapshot? snap) {
    if (snap == null) return null;
    final name = snap.referredByName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final username = snap.referredByUsername?.trim();
    if (username != null && username.isNotEmpty) return '@$username';
    return null;
  }

  String _link(RevenueShareSnapshot? snap) {
    if (snap == null) return '…';
    if (snap.shareUrl.isNotEmpty) return snap.shareUrl;
    if (snap.referralCode.isEmpty) return '…';
    return AppInviteService.webInviteUrl(ref: snap.referralCode);
  }

  Widget _referralCard(RevenueShareSnapshot? snap) {
    final link = _link(snap);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ваша ссылка',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          SelectableText(
            link,
            style: const TextStyle(fontSize: 15, height: 1.35),
          ),
          const SizedBox(height: 8),
          Text(
            'Только по этой ссылке видно, что человек пришёл от вас. '
            'Привели: ${snap?.referredCount ?? 0}. '
            'Доля — 17,5% нетто с рекламы и подписки в течение года.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: snap == null ? null : _share,
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Поделиться'),
              ),
              OutlinedButton(
                onPressed:
                    snap == null || link == '…' ? null : () => _copy(link),
                child: const Text('Скопировать'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _extraAdsCard(RevenueShareSnapshot? snap) {
    return _card(
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Доп. реклама за долю'),
        subtitle: const Text(
          'Больше объявлений. 35% нетто с рекламы на вас. '
          'Пока включено, «без рекламы» у подписки не действует.',
        ),
        value: snap?.extraAdsEnabled ?? false,
        onChanged: _busy || snap == null ? null : _toggleExtra,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final extraAdsCard = _extraAdsCard(snap);
    final referralCard = _referralCard(snap);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.focusExtraAds
              ? 'Доп. реклама за долю'
              : 'Партнёрская программа',
        ),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(SettingsRoute.path);
            }
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(userVisibleError(_error!)),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            const Text(
              'У каждого своя ссылка. Друг открывает её, регистрируется — '
              'и мы точно знаем, что он пришёл от вас. '
              'Делим только чистую прибыль с рекламы и подписки. '
              'Звёзды и подарки не входят. Сначала вычитаются расходы '
              '(остаётся 70% нетто).',
            ),
            const SizedBox(height: 16),
            if (widget.focusExtraAds) ...[
              extraAdsCard,
              const SizedBox(height: 12),
              referralCard,
            ] else ...[
              referralCard,
              const SizedBox(height: 12),
              extraAdsCard,
            ],
            const SizedBox(height: 12),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Баланс',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text('Доступно: ${snap?.availableRub ?? '—'}'),
                  Text('В холде 14 дней: ${snap?.pendingRub ?? '—'}'),
                  Text('На выплате: ${snap?.payoutHoldRub ?? '—'}'),
                  Text('Уже выплачено: ${snap?.paidRub ?? '—'}'),
                  Text('Мне с рекламы: ${snap?.viewerRub ?? '—'}'),
                  Text('Мне как рефералу: ${snap?.referrerRub ?? '—'}'),
                  const SizedBox(height: 12),
                  Text(
                    'Обмен на звёзды — сразу, 1 ★ = 0,80 ₽. '
                    'На карту / СБП — от 500 ₽, после проверки.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _busy || snap == null || !snap.canConvertStars
                                ? null
                                : _convertStars,
                        icon: const Icon(Icons.star_outline, size: 18),
                        label: Text(
                          snap == null || snap.convertibleStars <= 0
                              ? 'Обменять на звёзды'
                              : 'Обменять · ${snap.convertibleStars} ★',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy || snap == null || !snap.canRequestCard
                            ? null
                            : _requestCard,
                        icon: const Icon(Icons.account_balance_wallet_outlined,
                            size: 18),
                        label: const Text('На карту / СБП'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (snap != null && snap.payouts.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Заявки',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    for (final payout in snap.payouts) ...[
                      Text(
                        '${payout.kindLabel} · ${payout.amountRub}'
                        '${payout.amountStars > 0 ? ' · ${payout.amountStars} ★' : ''}'
                        ' · ${payout.statusLabel}',
                      ),
                      const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
            ],
            if (_invitedBy(snap) != null) ...[
              const SizedBox(height: 12),
              Text('Вас пригласил: ${_invitedBy(snap)}'),
            ],
            if (_busy && snap == null)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}
