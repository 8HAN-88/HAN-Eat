import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_router.dart';
import '../../../services/ads_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/channel_service.dart';
import '../../../services/media_upload_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import '../ads_order.dart';
import 'widgets/ad_preview_card.dart';

class AdCampaignEditorScreen extends StatefulWidget {
  const AdCampaignEditorScreen({super.key, this.campaignId});

  final int? campaignId;

  @override
  State<AdCampaignEditorScreen> createState() => _AdCampaignEditorScreenState();
}

class _AdCampaignEditorScreenState extends State<AdCampaignEditorScreen> {
  final _page = PageController();
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _cta = TextEditingController(text: 'Подробнее');
  final _advertiserName = TextEditingController();
  final _url = TextEditingController();
  final _postId = TextEditingController();
  final _imagePicker = ImagePicker();

  AdCampaign? _campaign;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String? _error;
  String _destinationType = 'url';
  final Set<String> _surfaces = {'feed'};
  String? _imageUrl;
  int? _channelId;
  List<Channel> _myChannels = const [];
  int _step = 0;

  bool get _isNew => widget.campaignId == null;
  bool get _editable => _isNew || (_campaign?.isEditable ?? true);

  @override
  void initState() {
    super.initState();
    _advertiserName.text = AuthService.instance.currentUser?.name ?? '';
    _bootstrap();
  }

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    _title.dispose();
    _body.dispose();
    _cta.dispose();
    _advertiserName.dispose();
    _url.dispose();
    _postId.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final channelsFuture = ChannelService.listChannels(mine: true, limit: 50);
      if (widget.campaignId != null) {
        final campaign = await AdsService.getCampaign(widget.campaignId!);
        _applyCampaign(campaign);
      }
      try {
        final channels = await channelsFuture;
        _myChannels = channels.items;
      } catch (_) {
        _myChannels = const [];
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e, fallback: 'Не удалось открыть заявку');
        _loading = false;
      });
    }
  }

  void _applyCampaign(AdCampaign campaign) {
    _campaign = campaign;
    _name.text = campaign.name;
    _title.text = campaign.creative.title;
    _body.text = campaign.creative.body;
    _cta.text = campaign.creative.ctaLabel;
    _advertiserName.text = campaign.creative.advertiserName?.trim().isNotEmpty == true
        ? campaign.creative.advertiserName!
        : (AuthService.instance.currentUser?.name ?? '');
    _url.text = campaign.destinationUrl ?? '';
    _postId.text = campaign.destinationPostId?.toString() ?? '';
    _destinationType = campaign.destinationType;
    _imageUrl = campaign.creative.imageUrl;
    _channelId = campaign.destinationChannelId;
    _surfaces
      ..clear()
      ..addAll(campaign.surfaces.isEmpty ? const ['feed'] : campaign.surfaces);
  }

  AdCampaignDraft _draft() {
    final title = _title.text.trim();
    return AdCampaignDraft(
      name: _name.text.trim().isEmpty ? title : _name.text.trim(),
      surfaces: _surfaces.toList(),
      destinationType: _destinationType,
      destinationUrl: _url.text.trim(),
      destinationChannelId: _channelId,
      destinationPostId: parseAdPostId(_postId.text),
      creative: AdCreativeDraft(
        title: title,
        body: _body.text.trim(),
        ctaLabel: _cta.text.trim().isEmpty ? 'Подробнее' : _cta.text.trim(),
        imageUrl: _imageUrl,
        advertiserName: _advertiserName.text.trim(),
      ),
    );
  }

  AdCampaign _previewCampaign() {
    final current = _campaign;
    return AdCampaign(
      id: current?.id ?? 0,
      advertiserId: current?.advertiserId ?? 0,
      name: _title.text.trim().isEmpty ? 'Новая реклама' : _title.text.trim(),
      status: current?.status ?? 'draft',
      isLive: current?.isLive ?? false,
      surfaces: _surfaces.toList(),
      destinationType: _destinationType,
      destinationUrl: _url.text.trim(),
      destinationChannelId: _channelId,
      destinationPostId: parseAdPostId(_postId.text),
      creative: AdCreative(
        id: current?.creative.id,
        title: _title.text.trim(),
        body: _body.text.trim(),
        ctaLabel: _cta.text.trim().isEmpty ? 'Подробнее' : _cta.text.trim(),
        imageUrl: _imageUrl,
        advertiserName: _advertiserName.text.trim(),
      ),
    );
  }

  List<AdOrderIssue> _issues() {
    return validateAdOrder(
      surfaces: _surfaces,
      title: _title.text,
      body: _body.text,
      imageUrl: _imageUrl,
      destinationType: _destinationType,
      destinationUrl: _url.text,
      channelId: _channelId,
      postIdRaw: _postId.text,
    );
  }

  String? _stepBlocker(int step) {
    final issues = _issues();
    if (step == 0 && issues.any((e) => e.field == 'surfaces')) {
      return issues.firstWhere((e) => e.field == 'surfaces').message;
    }
    if (step == 1) {
      final hit = issues.where((e) => e.field == 'title' || e.field == 'creative');
      if (hit.isNotEmpty) return hit.first.message;
    }
    if (step == 2) {
      final hit = issues.where((e) => e.field == 'destination');
      if (hit.isNotEmpty) return hit.first.message;
    }
    return null;
  }

  Future<void> _goTo(int step) async {
    setState(() => _step = step);
    if (_page.hasClients) {
      await _page.animateToPage(
        step,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _save({required bool submit}) async {
    if (_saving) return;
    if (submit) {
      final issues = _issues();
      if (issues.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(issues.first.message)),
        );
        if (issues.first.field == 'surfaces') {
          await _goTo(0);
        } else if (issues.first.field == 'destination') {
          await _goTo(2);
        } else {
          await _goTo(1);
        }
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final draft = _draft();
      AdCampaign saved;
      if (_campaign == null) {
        saved = await AdsService.create(draft);
        _campaign = saved;
      } else if (_editable) {
        saved = await AdsService.update(_campaign!.id, draft);
      } else {
        saved = _campaign!;
      }
      if (submit) {
        saved = await AdsService.submit(saved.id, draft);
      }
      if (!mounted) return;
      _applyCampaign(saved);
      setState(() => _saving = false);
      await _showResult(saved, submitted: submit);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _showResult(AdCampaign saved, {required bool submitted}) async {
    final title = submitted
        ? (saved.status == 'approved'
            ? 'Реклама принята'
            : 'Заявка отправлена')
        : 'Черновик сохранён';
    final body = submitted
        ? saved.clientNextStep
        : 'Можете вернуться и дописать позже. Заявка появится в списке.';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (image == null) return;
      setState(() => _uploading = true);
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: image,
        fileType: 'image',
      );
      final url = uploaded.url;
      if (url == null || url.isEmpty) {
        throw Exception('Не удалось получить URL изображения');
      }
      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e, fallback: 'Не удалось загрузить фото')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новая заявка' : 'Заявка'),
      ),
      body: _buildBody(),
      bottomNavigationBar: _loading || _error != null ? null : _bottomBar(),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
          children: [
            if (_campaign != null && !_editable)
              Text(
                _campaign!.clientNextStep,
                textAlign: TextAlign.center,
              ),
            if (_campaign != null && !_editable) const SizedBox(height: 8),
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => unawaited(_goTo(_step - 1)),
                      child: const Text('Назад'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () {
                            if (_step < 2) {
                              final block = _editable ? _stepBlocker(_step) : null;
                              if (block != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(block)),
                                );
                                return;
                              }
                              unawaited(_goTo(_step + 1));
                              return;
                            }
                            if (!_editable) {
                              Navigator.of(context).pop();
                              return;
                            }
                            unawaited(_save(submit: true));
                          },
                    child: Text(
                      _saving
                          ? 'Отправка…'
                          : _step < 2
                              ? 'Далее'
                              : _editable
                                  ? 'Отправить заявку'
                                  : 'Закрыть',
                    ),
                  ),
                ),
              ],
            ),
            if (_editable && _step == 2)
              TextButton(
                onPressed: _saving ? null : () => unawaited(_save(submit: false)),
                child: const Text('Сохранить черновик'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Не удалось открыть',
        subtitle: _error,
        action: FilledButton(
          onPressed: _bootstrap,
          child: const Text('Повторить'),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: (_step + 1) / 3),
              const SizedBox(height: 8),
              Text(
                switch (_step) {
                  0 => 'Шаг 1 из 3 · Где показывать',
                  1 => 'Шаг 2 из 3 · Объявление',
                  _ => 'Шаг 3 из 3 · Куда вести',
                },
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_campaign != null) ...[
                const SizedBox(height: 4),
                Text(_campaign!.statusLabel),
                if ((_campaign!.rejectionReason ?? '').trim().isNotEmpty)
                  Text(
                    _campaign!.rejectionReason!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ],
          ),
        ),
        Expanded(
          child: PageView(
            controller: _page,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (i) => setState(() => _step = i),
            children: [
              _stepWhere(),
              _stepCreative(),
              _stepDestination(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepWhere() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'Выберите места. Можно несколько — одно объявление подойдёт для всех.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _placeTile(
          id: 'feed',
          title: 'Лента рекомендаций',
          subtitle: 'Карточка между постами, как в Instagram',
          icon: Icons.dynamic_feed_outlined,
        ),
        _placeTile(
          id: 'reels',
          title: 'Рилсы',
          subtitle: 'Вертикальный ролик в ленте рилсов',
          icon: Icons.video_library_outlined,
        ),
        _placeTile(
          id: 'channel',
          title: 'Стены каналов',
          subtitle: 'Тихое объявление между постами канала',
          icon: Icons.campaign_outlined,
        ),
      ],
    );
  }

  Widget _placeTile({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _surfaces.contains(id);
    return Card(
      child: CheckboxListTile(
        value: selected,
        onChanged: !_editable
            ? null
            : (value) {
                setState(() {
                  if (value == true) {
                    _surfaces.add(id);
                  } else if (_surfaces.length > 1) {
                    _surfaces.remove(id);
                  }
                });
              },
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _stepCreative() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        TextField(
          controller: _advertiserName,
          enabled: _editable,
          decoration: const InputDecoration(
            labelText: 'Как подписать рекламодателя',
            hintText: 'Название компании или имя',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          enabled: _editable,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Заголовок',
            hintText: 'Коротко, что предлагаете',
          ),
        ),
        TextField(
          controller: _body,
          enabled: _editable,
          maxLength: 500,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Текст',
            hintText: 'Пара предложений для карточки',
          ),
        ),
        TextField(
          controller: _cta,
          enabled: _editable,
          maxLength: 32,
          decoration: const InputDecoration(
            labelText: 'Текст кнопки',
            hintText: 'Подробнее, Заказать, Открыть',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: !_editable || _uploading ? null : () => unawaited(_pickImage()),
          icon: _uploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined),
          label: Text(
            (_imageUrl ?? '').isEmpty
                ? 'Добавить изображение'
                : 'Заменить изображение',
          ),
        ),
        const SizedBox(height: 16),
        Text('Так увидят в ленте', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        AdPreviewCard(campaign: _previewCampaign()),
      ],
    );
  }

  Widget _stepDestination() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'Куда открыть, если человек нажмёт кнопку',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'url', label: Text('Сайт')),
            ButtonSegment(value: 'channel', label: Text('Канал')),
            ButtonSegment(value: 'post', label: Text('Пост')),
          ],
          selected: {_destinationType},
          onSelectionChanged: (next) {
            if (!_editable) return;
            setState(() => _destinationType = next.first);
          },
        ),
        const SizedBox(height: 12),
        if (_destinationType == 'url')
          TextField(
            controller: _url,
            enabled: _editable,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Ссылка',
              hintText: 'https://ваш-сайт.ru',
            ),
          )
        else if (_destinationType == 'channel')
          _myChannels.isEmpty
              ? Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Своих каналов пока нет'),
                    subtitle: const Text(
                      'Создайте канал или поставьте обычную ссылку на сайт',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(CreateChannelRoute.path),
                  ),
                )
              : DropdownButtonFormField<int>(
                  value: _myChannels.any((c) => c.id == _channelId)
                      ? _channelId
                      : null,
                  decoration: const InputDecoration(labelText: 'Ваш канал'),
                  items: [
                    for (final channel in _myChannels)
                      DropdownMenuItem(
                        value: channel.id,
                        child: Text(channel.name),
                      ),
                  ],
                  onChanged: _editable
                      ? (value) => setState(() => _channelId = value)
                      : null,
                )
        else
          TextField(
            controller: _postId,
            enabled: _editable,
            decoration: const InputDecoration(
              labelText: 'Ссылка или номер поста',
              hintText: 'https://haneat.app/… или 123',
            ),
          ),
        const SizedBox(height: 20),
        Text('Проверьте перед отправкой', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        AdPreviewCard(campaign: _previewCampaign()),
        const SizedBox(height: 8),
        Text(
          'После отправки модератор проверит объявление. Статус заявки будет в разделе «Заказать рекламу».',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
