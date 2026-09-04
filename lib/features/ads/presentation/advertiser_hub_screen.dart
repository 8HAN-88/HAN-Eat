import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/ads_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

class AdvertiserHubScreen extends StatefulWidget {
  const AdvertiserHubScreen({super.key});

  @override
  State<AdvertiserHubScreen> createState() => _AdvertiserHubScreenState();
}

class _AdvertiserHubScreenState extends State<AdvertiserHubScreen> {
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
      final campaigns = await AdsService.listMine();
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e, fallback: 'Не удалось загрузить рекламу');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Реклама'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_openEditor()),
        icon: const Icon(Icons.add),
        label: const Text('Новая кампания'),
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
    if (_campaigns.isEmpty) {
      return AppEmptyState(
        icon: Icons.campaign_outlined,
        title: 'Пока нет кампаний',
        subtitle:
            'Соберите объявление, выберите ленту, рилсы или каналы и отправьте на модерацию.',
        action: FilledButton(
          onPressed: () => unawaited(_openEditor()),
          child: const Text('Разместить рекламу'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _campaigns.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Text(
            'Кабинет рекламодателя. Продвижение своих постов за Stars — отдельно, в инструментах автора.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          );
        }
        final campaign = _campaigns[index - 1];
        return _CampaignTile(
          campaign: campaign,
          onOpen: () => unawaited(_openEditor(campaignId: campaign.id)),
          onPause: campaign.canPause
              ? () => unawaited(_runAction(
                    () => AdsService.pause(campaign.id),
                    'Кампания на паузе',
                  ))
              : null,
          onResume: campaign.canResume
              ? () => unawaited(_runAction(
                    () => AdsService.resume(campaign.id),
                    'Кампания снова в эфире',
                  ))
              : null,
          onArchive: campaign.canArchive
              ? () => unawaited(_runAction(
                    () => AdsService.archive(campaign.id),
                    'Кампания в архиве',
                  ))
              : null,
        );
      },
    );
  }
}

class _CampaignTile extends StatelessWidget {
  const _CampaignTile({
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
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.campaign_outlined,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      campaign.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${campaign.statusLabel} · ${campaign.surfacesLabel}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if ((campaign.rejectionReason ?? '').trim().isNotEmpty)
                      Text(
                        campaign.rejectionReason!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                      ),
                  ],
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
                  const PopupMenuItem(value: 'open', child: Text('Открыть')),
                  if (onPause != null)
                    const PopupMenuItem(value: 'pause', child: Text('Пауза')),
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
        ),
      ),
    );
  }
}
