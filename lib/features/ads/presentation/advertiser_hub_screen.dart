import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/ads_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import '../ads_order.dart';

class AdvertiserHubScreen extends StatefulWidget {
  const AdvertiserHubScreen({super.key});

  @override
  State<AdvertiserHubScreen> createState() => _AdvertiserHubScreenState();
}

class _AdvertiserHubScreenState extends State<AdvertiserHubScreen> {
  bool _loading = true;
  bool _showArchived = false;
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
      final campaigns = await AdsService.listMine();
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e, fallback: 'Не удалось загрузить заявки');
        _loading = false;
      });
    }
  }

  Future<void> _openEditor({int? campaignId}) async {
    final changed = await context.push<bool>(
      campaignId == null
          ? AdsCampaignEditorRoute.path
          : AdsCampaignEditorRoute.pathFor(campaignId),
    );
    if (changed == true && mounted) {
      await _load();
    }
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  List<AdCampaign> get _visible {
    if (_showArchived) return _campaigns;
    return _campaigns.where((c) => c.status != 'archived').toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заказать рекламу'),
        actions: [
          IconButton(
            tooltip: 'Написать в поддержку',
            onPressed: () => context.push(adOrderSupportPath()),
            icon: const Icon(Icons.support_agent_outlined),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_openEditor()),
        icon: const Icon(Icons.add),
        label: const Text('Новая заявка'),
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
        action: FilledButton(
          onPressed: _load,
          child: const Text('Повторить'),
        ),
      );
    }

    final visible = _visible;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _HowItWorksCard(onOrder: () => unawaited(_openEditor())),
        const SizedBox(height: 16),
        if (_campaigns.any((c) => c.status == 'archived'))
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('Показать архив'),
              selected: _showArchived,
              onSelected: (v) => setState(() => _showArchived = v),
            ),
          ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: AppEmptyState(
              icon: Icons.campaign_outlined,
              title: 'Пока нет заявок',
              subtitle:
                  'Соберите карточку за три шага — куда показывать, что показать и куда вести. Мы проверим и включим показы.',
              action: FilledButton(
                onPressed: () => unawaited(_openEditor()),
                child: const Text('Заказать рекламу'),
              ),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          Text(
            'Мои заявки',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          for (final campaign in visible) ...[
            _OrderTile(
              campaign: campaign,
              onOpen: () => unawaited(_openEditor(campaignId: campaign.id)),
              onPause: campaign.canPause
                  ? () => unawaited(_runAction(
                        () => AdsService.pause(campaign.id),
                        'Показы на паузе',
                      ))
                  : null,
              onResume: campaign.canResume
                  ? () => unawaited(_runAction(
                        () => AdsService.resume(campaign.id),
                        'Показы снова включены',
                      ))
                  : null,
              onArchive: campaign.canArchive
                  ? () => unawaited(_runAction(
                        () => AdsService.archive(campaign.id),
                        'Заявка в архиве',
                      ))
                  : null,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard({required this.onOrder});

  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Реклама в HanWe',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Покажем вашу карточку в рекомендациях, рилсах или на стенах каналов. Это не буст своих постов — отдельное объявление для клиентов.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            const _StepLine(
              index: 1,
              title: 'Соберите объявление',
              subtitle: 'Картинка, заголовок, кнопка и куда вести',
            ),
            const _StepLine(
              index: 2,
              title: 'Отправьте заявку',
              subtitle: 'Мы проверим текст и ссылку',
            ),
            const _StepLine(
              index: 3,
              title: 'Следите за статусом здесь',
              subtitle: 'После одобрения показы включатся сами',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onOrder,
                child: const Text('Заказать рекламу'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({
    required this.index,
    required this.title,
    required this.subtitle,
  });

  final int index;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            child: Text('$index', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.campaign,
    required this.onOpen,
    this.onPause,
    this.onResume,
    this.onArchive,
  });

  final AdCampaign campaign;
  final VoidCallback onOpen;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = campaign.creative.title.trim().isNotEmpty
        ? campaign.creative.title
        : campaign.name;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: campaign.status == 'rejected'
                          ? scheme.errorContainer
                          : scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      campaign.statusLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'open':
                          onOpen();
                        case 'pause':
                          onPause?.call();
                        case 'resume':
                          onResume?.call();
                        case 'archive':
                          onArchive?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'open',
                        child: Text(campaign.isEditable ? 'Дополнить' : 'Открыть'),
                      ),
                      if (onPause != null)
                        const PopupMenuItem(
                          value: 'pause',
                          child: Text('Пауза'),
                        ),
                      if (onResume != null)
                        const PopupMenuItem(
                          value: 'resume',
                          child: Text('Возобновить'),
                        ),
                      if (onArchive != null)
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('В архив'),
                        ),
                    ],
                  ),
                ],
              ),
              Text(
                campaign.surfacesLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(campaign.clientNextStep),
            ],
          ),
        ),
      ),
    );
  }
}
