import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snap = await RevenueShareApi.me();
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

  Future<void> _apply() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final snap = await RevenueShareApi.applyCode(code);
      if (!mounted) return;
      _codeCtrl.clear();
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
      const SnackBar(content: Text('Скопировано')),
    );
  }

  Widget _referralCard(RevenueShareSnapshot? snap) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Реферальный код',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          SelectableText(
            snap?.referralCode.isNotEmpty == true
                ? snap!.referralCode
                : '…',
            style: const TextStyle(fontSize: 22, letterSpacing: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            'Привели: ${snap?.referredCount ?? 0}. '
            'Доля реферала — 17,5% нетто с рекламы и подписки '
            'приведённого человека в течение года.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed:
                    snap == null ? null : () => _copy(snap.referralCode),
                child: const Text('Код'),
              ),
              OutlinedButton(
                onPressed: snap == null || snap.shareUrl.isEmpty
                    ? null
                    : () => _copy(snap.shareUrl),
                child: const Text('Ссылка'),
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
            const SizedBox(height: 12),
            if (snap?.referredByName != null)
              Text('Вас пригласил: ${snap!.referredByName}')
            else
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Есть код друга? Можно привязать 7 дней после регистрации.',
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(hintText: 'Код'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy ? null : _apply,
                      child: const Text('Привязать'),
                    ),
                  ],
                ),
              ),
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
