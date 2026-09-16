import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var snap = await RevenueShareApi.me();
      if (snap.referredByName == null) {
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
      shareOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
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
                onPressed: snap == null || link == '…'
                    ? null
                    : () => _copy(link),
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
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(userVisibleError(_error!)),
              ),
            const Text(
              'У каждого своя ссылка. Друг открывает её, регистрируется — '
              'и мы точно знаем, что он пришёл от вас. '
              'Делим только чистую прибыль с рекламы и подписки. '
              'Звёзды, подарки и TON не входят. Сначала вычитаются расходы '
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
                  Text('Мне с рекламы: ${snap?.viewerRub ?? '—'}'),
                  Text('Мне как рефералу: ${snap?.referrerRub ?? '—'}'),
                ],
              ),
            ),
            if (snap?.referredByName != null) ...[
              const SizedBox(height: 12),
              Text('Вас пригласил: ${snap!.referredByName}'),
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
