import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/ads_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import 'widgets/ad_preview_card.dart';

class AdsReviewScreen extends StatefulWidget {
  const AdsReviewScreen({super.key});

  @override
  State<AdsReviewScreen> createState() => _AdsReviewScreenState();
}

class _AdsReviewScreenState extends State<AdsReviewScreen> {
  bool _loading = true;
  String? _error;
  List<AdCampaign> _campaigns = const [];

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
      final campaigns = await AdsService.listReview();
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e, fallback: 'Не удалось загрузить очередь');
        _loading = false;
      });
    }
  }

  Future<void> _approve(AdCampaign campaign) async {
    try {
      await AdsService.approve(campaign.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Кампания одобрена')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _reject(AdCampaign campaign) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отклонить рекламу'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 400,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Причина для клиента',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.length < 2) return;
    try {
      await AdsService.reject(campaign.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Кампания отклонена')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Модерация рекламы'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Не удалось загрузить',
        subtitle: _error,
        action: FilledButton(onPressed: _load, child: const Text('Повторить')),
      );
    }
    if (_campaigns.isEmpty) {
      return const AppEmptyState(
        icon: Icons.verified_outlined,
        title: 'Очередь пуста',
        subtitle: 'Новые кампании клиентов появятся здесь после отправки.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _campaigns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final campaign = _campaigns[index];
        final advertiser = campaign.advertiser?.name ?? 'Клиент';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$advertiser · ${campaign.name}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            AdPreviewCard(campaign: campaign),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => unawaited(_reject(campaign)),
                    child: const Text('Отклонить'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => unawaited(_approve(campaign)),
                    child: const Text('Одобрить'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
