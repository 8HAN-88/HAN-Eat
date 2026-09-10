import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/app_router.dart';
import '../../../../services/ads_service.dart';
import '../../../../utils/api_error_parser.dart';
import '../../ads_order.dart';
import 'ad_preview_card.dart';

class FeedAdCard extends StatefulWidget {
  const FeedAdCard({
    super.key,
    required this.item,
    this.onHidden,
  });

  final FeedAdItem item;
  final VoidCallback? onHidden;

  @override
  State<FeedAdCard> createState() => _FeedAdCardState();
}

class _FeedAdCardState extends State<FeedAdCard> {
  var _impressed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_impress());
  }

  Future<void> _impress() async {
    if (_impressed || widget.item.campaignId <= 0) return;
    _impressed = true;
    try {
      await AdsService.recordEvent(
        campaignId: widget.item.campaignId,
        kind: 'impression',
        surface: widget.item.surface,
      );
    } catch (_) {}
  }

  Future<void> _open() async {
    try {
      await AdsService.recordEvent(
        campaignId: widget.item.campaignId,
        kind: 'click',
        surface: widget.item.surface,
      );
    } catch (_) {}
    if (!mounted) return;
    final item = widget.item;
    if (item.destinationType == 'channel' && item.destinationChannelId != null) {
      context.push(ChannelDetailRoute.pathFor(item.destinationChannelId!));
      return;
    }
    if (item.destinationType == 'post' && item.destinationPostId != null) {
      context.push(PostFeedRoute.pathFor(item.destinationPostId!));
      return;
    }
    final raw = normalizeAdDestinationUrl(item.destinationUrl ?? '');
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка объявления недоступна')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _hide() async {
    try {
      await AdsService.hide(widget.item.campaignId);
      widget.onHidden?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdPreviewCard(
      campaign: widget.item.asCampaign,
      onCta: () => unawaited(_open()),
      onHide: () => unawaited(_hide()),
    );
  }
}
