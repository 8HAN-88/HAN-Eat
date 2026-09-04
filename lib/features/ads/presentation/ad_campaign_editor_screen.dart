import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/ads_service.dart';
import '../../../services/channel_service.dart';
import '../../../services/media_upload_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import 'widgets/ad_preview_card.dart';

class AdCampaignEditorScreen extends StatefulWidget {
  const AdCampaignEditorScreen({super.key, this.campaignId});

  final int? campaignId;

  @override
  State<AdCampaignEditorScreen> createState() => _AdCampaignEditorScreenState();
}

class _AdCampaignEditorScreenState extends State<AdCampaignEditorScreen> {
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

  bool get _isNew => widget.campaignId == null;
  bool get _editable => _isNew || (_campaign?.isEditable ?? true);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
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
        _error = userVisibleError(e, fallback: 'Не удалось открыть кампанию');
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
    _advertiserName.text = campaign.creative.advertiserName ?? '';
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
    return AdCampaignDraft(
      name: _name.text.trim().isEmpty ? 'Новая кампания' : _name.text.trim(),
      surfaces: _surfaces.toList(),
      destinationType: _destinationType,
      destinationUrl: _url.text.trim(),
      destinationChannelId: _channelId,
      destinationPostId: int.tryParse(_postId.text.trim()),
      creative: AdCreativeDraft(
        title: _title.text.trim(),
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
      name: _name.text.trim().isEmpty ? 'Новая кампания' : _name.text.trim(),
      status: current?.status ?? 'draft',
      isLive: current?.isLive ?? false,
      surfaces: _surfaces.toList(),
      destinationType: _destinationType,
      destinationUrl: _url.text.trim(),
      destinationChannelId: _channelId,
      destinationPostId: int.tryParse(_postId.text.trim()),
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

  Future<void> _save({required bool submit}) async {
    if (_saving) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            submit
                ? (saved.status == 'approved'
                    ? 'Кампания одобрена и готова к показу'
                    : 'Отправлено на модерацию')
                : 'Черновик сохранён',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
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
        SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить фото'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новая реклама' : 'Кампания'),
      ),
      body: _buildBody(),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    if (_editable)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => unawaited(_save(submit: false)),
                          child: const Text('Черновик'),
                        ),
                      ),
                    if (_editable) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving || !_editable
                            ? null
                            : () => unawaited(_save(submit: true)),
                        child: Text(
                          _saving
                              ? 'Сохранение…'
                              : _editable
                                  ? 'Выложить'
                                  : _campaign?.statusLabel ?? '',
                        ),
                      ),
                    ),
                  ],
                ),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_campaign != null) ...[
          Text(
            _campaign!.statusLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if ((_campaign!.rejectionReason ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _campaign!.rejectionReason!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _name,
          enabled: _editable,
          decoration: const InputDecoration(
            labelText: 'Название кампании',
            hintText: 'Только для вас, клиенты его не видят',
          ),
        ),
        const SizedBox(height: 16),
        Text('Где показывать', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _surfaceChip('feed', 'Лента'),
            _surfaceChip('reels', 'Рилсы'),
            _surfaceChip('channel', 'Каналы'),
          ],
        ),
        const SizedBox(height: 16),
        Text('Куда вести', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'url', label: Text('Ссылка')),
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
              hintText: 'https://',
            ),
          )
        else if (_destinationType == 'channel')
          DropdownButtonFormField<int>(
            value: _myChannels.any((c) => c.id == _channelId) ? _channelId : null,
            decoration: const InputDecoration(labelText: 'Канал'),
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
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'ID поста',
              hintText: 'Число из ссылки на пост',
            ),
          ),
        const SizedBox(height: 20),
        Text('Объявление', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _advertiserName,
          enabled: _editable,
          decoration: const InputDecoration(
            labelText: 'Имя рекламодателя',
            hintText: 'Как подпишут карточку',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          enabled: _editable,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Заголовок'),
        ),
        TextField(
          controller: _body,
          enabled: _editable,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Текст'),
        ),
        TextField(
          controller: _cta,
          enabled: _editable,
          maxLength: 32,
          decoration: const InputDecoration(labelText: 'Кнопка'),
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
            (_imageUrl ?? '').isEmpty ? 'Добавить изображение' : 'Заменить изображение',
          ),
        ),
        const SizedBox(height: 20),
        Text('Как увидят в ленте', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        AdPreviewCard(campaign: _previewCampaign()),
      ],
    );
  }

  Widget _surfaceChip(String id, String label) {
    return FilterChip(
      label: Text(label),
      selected: _surfaces.contains(id),
      onSelected: !_editable
          ? null
          : (selected) {
              setState(() {
                if (selected) {
                  _surfaces.add(id);
                } else if (_surfaces.length > 1) {
                  _surfaces.remove(id);
                }
              });
            },
    );
  }
}
