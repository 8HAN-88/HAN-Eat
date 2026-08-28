// Новая карточка поста для нового API
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/post_model.dart';
import '../../../models/post.dart' show PollData;
import '../../../services/like_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/repost_service.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../services/auth_service.dart';
import '../../../services/comment_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/session_snackbar.dart';
import '../../../widgets/telegram_photo_grid.dart';
import '../../../utils/number_formatter.dart';
import '../../../utils/post_display_title.dart';
import '../../../widgets/post_card_container.dart';
import '../../../widgets/feed_video_player.dart';
import '../../../services/server_config.dart';
import '../../../widgets/share_action_sheet.dart';
import '../../../widgets/post_poll_section.dart';
import 'package:go_router/go_router.dart';
import '../../../app/app_router.dart';
import '../../../services/api_service.dart';
import '../../../services/post_service.dart';
import '../../../services/feed_cache_service.dart';
import '../../../services/feed_analytics_service.dart';
import '../../../services/paid_features_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../comments/presentation/show_post_comments_sheet.dart';
import 'widgets/paid_content_paywall_card.dart';
import 'widgets/show_post_likers_sheet.dart';
import '../../../widgets/stars_pay_helper.dart';

int? _repostOriginalPostIdFromBody(Map<String, dynamic>? body) {
  final raw = body?['repost_original_post_id'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

String? _channelRepostUserCommentFromPost(PostModel post) {
  final body = post.body;
  final fromBody = body?['repost_to_channel_comment'];
  if (fromBody is String && fromBody.trim().isNotEmpty) return fromBody.trim();
  final desc = post.description;
  if (desc == null || desc.trim().isEmpty) return null;
  final blocks = desc.split(RegExp(r'\n\n+', multiLine: true));
  if (blocks.isEmpty) return null;
  final first = blocks.first.trim();
  if (first.isEmpty || first.startsWith('Репост:')) return null;
  return first;
}


class NewPostCard extends StatefulWidget {
  final PostModel post;
  final Future<void> Function()? onCommentTap;
  final VoidCallback? onAuthorTap;

  /// После удаления поста (обновить список родителя).
  final VoidCallback? onPostDeleted;

  /// Без шапки (аватар, имя, ⋯ сверху) — как карточки в канале; меню переносится в нижний ряд.
  final bool hideFeedHeader;

  const NewPostCard({
    super.key,
    required this.post,
    this.onCommentTap,
    this.onAuthorTap,
    this.onPostDeleted,
    this.hideFeedHeader = false,
  });

  @override
  State<NewPostCard> createState() => _NewPostCardState();
}

class _NewPostCardState extends State<NewPostCard>
    with SingleTickerProviderStateMixin {
  static int? _cachedCurrentUserId;
  static Future<int?>? _currentUserIdLoad;

  late PostModel _displayPost;
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isSaved = false;
  bool _isReposted = false;
  int _repostsCount = 0;
  int _displayCommentsCount = 0;
  bool _isLoading = false;
  bool _isLiking = false;
  bool _isOpeningComments = false;
  bool _isSaving = false;
  bool _isReposting = false;
  bool _isSendingDonation = false;
  bool _isBoosting = false;
  int? _currentUserId;
  bool _showLikeAnimation = false;
  bool _captionExpanded = false;
  late final AnimationController _likeAnimationController;
  late final Animation<double> _likeScaleAnimation;
  late final Animation<double> _likeOpacityAnimation;

  int? _feedChannelRepostOrigIdCache;
  Future<PostModel?>? _feedChannelRepostOrigFuture;

  void _syncFeedChannelRepostFuture() {
    final id = _repostOriginalPostIdFromBody(widget.post.body);
    if (id == null) {
      _feedChannelRepostOrigIdCache = null;
      _feedChannelRepostOrigFuture = null;
      return;
    }
    if (_feedChannelRepostOrigIdCache != id) {
      _feedChannelRepostOrigIdCache = id;
      _feedChannelRepostOrigFuture = ApiService.getPostById(id);
    }
  }

  @override
  void initState() {
    super.initState();
    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _likeScaleAnimation = Tween<double>(begin: 0.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _likeAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    _likeOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _likeAnimationController,
        curve: const Interval(0.5, 1.0),
      ),
    );
    _displayPost = widget.post;
    if (_likesViaPostApi) {
      _isLiked = widget.post.isLiked;
      _likesCount = widget.post.likesCount;
    } else {
      _isLiked = false;
      _likesCount = 0;
    }
    _isSaved = widget.post.isSaved ?? false;
    _isReposted = widget.post.isReposted ?? false;
    _repostsCount = widget.post.repostsCount;
    _displayCommentsCount = widget.post.commentsCount;
    _currentUserId =
        AuthService.instance.currentUser?.id ?? _cachedCurrentUserId;
    if (_currentUserId == null) {
      _loadCurrentUserId();
    }
    _syncFeedChannelRepostFuture();
  }

  @override
  void dispose() {
    _likeAnimationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapLike() {
    if (!_isLiked && !_isLiking) {
      unawaited(_toggleLike());
    }
    setState(() => _showLikeAnimation = true);
    _likeAnimationController.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() => _showLikeAnimation = false);
      _likeAnimationController.reset();
    });
  }

  Widget _withDoubleTapLikeOverlay(Widget media) {
    return Stack(
      alignment: Alignment.center,
      children: [
        media,
        if (_showLikeAnimation)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _likeAnimationController,
              builder: (context, child) {
                return Opacity(
                  opacity: _likeOpacityAnimation.value,
                  child: Transform.scale(
                    scale: _likeScaleAnimation.value,
                    child: child,
                  ),
                );
              },
              child: const Icon(
                Icons.favorite,
                color: Colors.white,
                size: 100,
                shadows: [
                  Shadow(blurRadius: 14, color: Colors.black54),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant NewPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _feedChannelRepostOrigIdCache = null;
      _feedChannelRepostOrigFuture = null;
      _displayPost = widget.post;
    } else if (oldWidget.post != widget.post) {
      _displayPost = applyIncomingPostPreservingLocalPoll(
        _displayPost,
        widget.post,
      );
    }
    if (_likesViaPostApi) {
      _isLiked = widget.post.isLiked;
      _likesCount = widget.post.likesCount;
    } else {
      _isLiked = false;
      _likesCount = 0;
    }
    _isSaved = widget.post.isSaved ?? false;
    _isReposted = widget.post.isReposted ?? false;
    _repostsCount = widget.post.repostsCount;
    _displayCommentsCount = widget.post.commentsCount;
    _syncFeedChannelRepostFuture();
  }

  Future<void> _loadCurrentUserId() async {
    try {
      _currentUserIdLoad ??= AuthService.getCurrentUser().then((user) {
        _cachedCurrentUserId = user?.id;
        return _cachedCurrentUserId;
      });
      final userId = await _currentUserIdLoad;
      if (mounted) {
        setState(() => _currentUserId = userId);
      }
    } catch (e) {
      // Игнорируем ошибки
    } finally {
      _currentUserIdLoad = null;
    }
  }

  bool get _isAuthor =>
      _currentUserId != null && _currentUserId == _displayPost.userId;

  Future<void> _reloadDisplayPost() async {
    try {
      final fresh = await ApiService.getPostById(widget.post.id);
      if (fresh != null && mounted) {
        setState(() {
          _displayPost = fresh;
          _displayCommentsCount = fresh.commentsCount;
          _isLiked = fresh.isLiked;
          _likesCount = fresh.likesCount;
          _isSaved = fresh.isSaved ?? false;
          _isReposted = fresh.isReposted ?? false;
          _repostsCount = fresh.repostsCount;
        });
      }
    } catch (_) {}
  }

  Future<void> _purchasePaidContent() async {
    if (_isLoading) return;
    final ok = await confirmStarsSpend(
      context,
      title: 'Открыть контент',
      body: 'Разовый доступ к эксклюзивному посту автора.',
      amountStars: _displayPost.priceStars,
      confirmLabel: 'Купить',
    );
    if (!ok || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await PaidFeaturesService.purchaseContent(_displayPost.id);
      await _reloadDisplayPost();
      if (!mounted) return;
      final unlocked = _displayPost.copyWith(purchased: true);
      setState(() => _displayPost = unlocked);
      try {
        await FeedCacheService.instance.upsertPostModelInCache(unlocked);
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Контент открыт')),
      );
    } catch (e) {
      if (!mounted) return;
      await showStarsRequiredSnack(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onPollUpdated(PollData poll) {
    final body = Map<String, dynamic>.from(_displayPost.body ?? {});
    body['poll'] = poll.toJson();
    setState(() {
      _displayPost = _displayPost.copyWith(body: body);
    });
  }



  bool get _likesViaPostApi => true;

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }



  Future<void> _refreshCommentsCount() async {
    try {
      final total = await CommentService.getCommentsTotal(widget.post.id);
      if (mounted) {
        setState(() => _displayCommentsCount = total);
      }
    } catch (_) {}
  }


  Future<void> _toggleLike() async {
    if (_isLiking) return;


    setState(() {
      _isLiking = true;
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });

    try {
      final response = _isLiked
          ? await LikeService.likePost(widget.post.id)
          : await LikeService.unlikePost(widget.post.id);

      setState(() {
        _likesCount = response.likesCount;
      });
    } catch (e) {
      // Откатываем изменения при ошибке
      setState(() {
        _isLiked = !_isLiked;
        _likesCount += _isLiked ? 1 : -1;
      });

      if (mounted) {
        showErrorSnackBar(
          context,
          e,
          fallback: 'Не удалось поставить лайк',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLiking = false);
      }
    }
  }

  Future<void> _toggleSave() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _isSaved = !_isSaved;
    });

    try {
      if (_isSaved) {
        await SavedPostsService.savePost(widget.post.id);
      } else {
        await SavedPostsService.unsavePost(widget.post.id);
      }
    } catch (e) {
      // Откатываем изменения при ошибке
      setState(() {
        _isSaved = !_isSaved;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(userVisibleError(e, fallback: 'Не удалось сохранить'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _toggleRepost() async {
    if (_isReposting) return;

    if (_isReposted) {
      // Если уже репостнуто, просто удаляем
      setState(() {
        _isReposting = true;
        _isReposted = false;
        _repostsCount = (_repostsCount - 1).clamp(0, double.infinity).toInt();
      });

      try {
        await RepostService.deleteRepost(widget.post.id);
      } catch (e) {
        // Откатываем изменения при ошибке
        setState(() {
          _isReposted = true;
          _repostsCount += 1;
        });

        if (mounted) {
          showErrorSnackBar(
            context,
            e,
            fallback: 'Не удалось убрать репост',
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isReposting = false);
        }
      }
      return;
    }

    // Показываем диалог для репоста с комментарием
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _RepostDialog(),
    );

    if (result == null) return; // Пользователь отменил

    final comment = result['comment'] as String?;

    setState(() {
      _isReposting = true;
      _isReposted = true;
      _repostsCount += 1;
    });

    try {
      await RepostService.createRepost(
        postId: widget.post.id,
        comment: comment,
      );
    } catch (e) {
      // Откатываем изменения при ошибке
      setState(() {
        _isReposted = false;
        _repostsCount = (_repostsCount - 1).clamp(0, double.infinity).toInt();
      });

      if (mounted) {
        showErrorSnackBar(
          context,
          e,
          fallback: 'Не удалось сделать репост',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isReposting = false);
      }
    }
  }

  Future<void> _openShareSheet() async {
    await ShareActionSheet.showForPost(
      context,
      post: widget.post,
      onRepostToWall: _toggleRepost,
    );
  }

  Future<void> _showReportDialog() async {
    await reportPostWithDialog(context, widget.post.id);
  }

  Future<void> _onOverflowMenuSelected(String value) async {
    if (value == 'report') {
      _showReportDialog();
    } else if (value == 'edit') {
      if (widget.post.channelId == null) {
        final updated = await context.push<bool>(
          EditProfilePostRoute.pathFor(widget.post.id),
        );
        if (updated == true) await _reloadDisplayPost();
      } else {
        await context.push(
          '/channel/${widget.post.channelId}/post/${widget.post.id}/edit',
          extra: widget.post.toJson(),
        );
        await _reloadDisplayPost();
      }
    } else if (value == 'delete') {
      await _confirmAndDeletePost();
    } else if (value == 'boost') {
      await _showBoostDialog();
    } else if (value == 'donate') {
      await _showDonateDialog();
    }
  }

  Future<void> _showDonateDialog() async {
    if (_isAuthor || _isSendingDonation) return;
    final amountController = TextEditingController(text: '25');
    final messageController = TextEditingController();
    final authorName = _displayPost.author?.name.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          authorName == null || authorName.isEmpty
              ? 'Поддержать автора'
              : 'Поддержать $authorName',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Сумма в звёздах',
                helperText: 'От 1 до 100 000 ★',
                prefixIcon: Icon(Icons.stars_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Сообщение автору',
                hintText: 'Спасибо за классный пост!',
                prefixIcon: Icon(Icons.favorite_border_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.volunteer_activism_rounded, size: 18),
            label: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final amount = int.tryParse(amountController.text.trim()) ?? 0;
    if (amount <= 0 || amount > 100000) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите сумму от 1 до 100 000 ★')),
      );
      return;
    }

    setState(() => _isSendingDonation = true);
    try {
      final result = await PaidFeaturesService.donate(
        recipientId: _displayPost.userId,
        amountStars: amount,
        message: messageController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Донат отправлен. Баланс: ${result.balance} ★'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (isStarsRequiredError(e)) {
        await showStarsRequiredSnack(context, e, fallback: 'Не удалось отправить донат');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingDonation = false);
    }
  }

  Future<void> _showBoostDialog() async {
    if (_isBoosting) return;
    const presets = <int>[50, 100, 250, 500];
    var amount = 100;
    var days = 7;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Бустить пост'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Бюджет'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in presets)
                    ChoiceChip(
                      selected: amount == n,
                      label: Text('$n ★'),
                      onSelected: (_) => setLocal(() => amount = n),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Срок'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final d in const [3, 7, 14])
                    ChoiceChip(
                      selected: days == d,
                      label: Text('$d дн.'),
                      onSelected: (_) => setLocal(() => days = d),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Запустить · $amount ★'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await confirmStarsSpend(
      context,
      title: 'Запустить буст',
      body: 'Пост будет продвигаться $days дн. за $amount ★.',
      amountStars: amount,
      confirmLabel: 'Буст',
    );
    if (!ok || !mounted) return;
    setState(() => _isBoosting = true);
    try {
      await PaidFeaturesService.boostPost(
        postId: _displayPost.id,
        amountStars: amount,
        durationDays: days,
      );
      await _reloadDisplayPost();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Буст запущен')),
      );
    } catch (e) {
      if (!mounted) return;
      if (isStarsRequiredError(e)) {
        await showStarsRequiredSnack(context, e, fallback: 'Не удалось запустить буст');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isBoosting = false);
    }
  }

  Future<void> _confirmAndDeletePost() async {
    if (widget.post.channelId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить пост?'),
        content: const Text(
          'Вы уверены, что хотите удалить этот пост? Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await PostService.deletePost(widget.post.id);
      try {
        await FeedCacheService.instance
            .removePostFromCache(widget.post.id.toString());
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пост удалён')),
      );
      widget.onPostDeleted?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось удалить пост'),
          ),
        ),
      );
    }
  }

  List<PopupMenuEntry<String>> _overflowMenuEntries() {
    return [
      if (_isAuthor && widget.post.channelId == null) ...[
        const PopupMenuItem(
          value: 'boost',
          child: Row(
            children: [
              Icon(Icons.rocket_launch_outlined, size: 20),
              SizedBox(width: 8),
              Text('Бустить за звёзды'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20),
              SizedBox(width: 8),
              Text('Редактировать'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: Colors.red),
              SizedBox(width: 8),
              Text('Удалить', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
      if (!_isAuthor) ...[
        const PopupMenuItem(
          value: 'donate',
          child: Row(
            children: [
              Icon(Icons.volunteer_activism_outlined, size: 20),
              SizedBox(width: 8),
              Text('Поддержать автора'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'report',
          child: Row(
            children: [
              Icon(Icons.flag_outlined, size: 20),
              SizedBox(width: 8),
              Text('Пожаловаться'),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _buildOverflowMenuButton({required double iconSize}) {
    final entries = _overflowMenuEntries();
    if (entries.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: iconSize),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onSelected: _onOverflowMenuSelected,
      itemBuilder: (context) => entries,
    );
  }

  /// Репост в канал в ленте: обёртка с [repost_original_post_id] — показываем оригинал.
  Widget _buildFeedChannelRepostBody(PostModel wrapper) {
    final scheme = Theme.of(context).colorScheme;
    final comment = _channelRepostUserCommentFromPost(wrapper);

    return FutureBuilder<PostModel?>(
      future: _feedChannelRepostOrigFuture,
      builder: (context, snap) {
        final orig = snap.data;
        final loading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;

        String sourceName(PostModel? o) {
          if (o == null) return '';
          return o.channel?.name ?? o.author?.name ?? 'Пост';
        }

        String? sourceAvatar(PostModel? o) {
          if (o == null) return null;
          final u = o.channel?.avatarUrl ?? o.author?.avatarUrl;
          if (u == null || u.isEmpty) return null;
          return u;
        }

        void openSource(PostModel? o) {
          if (o == null) return;
          if (o.channel != null) {
            context.push('/channel/${o.channel!.id}');
          } else {
            context.push('/profile?userId=${o.userId}');
          }
        }

        final name = sourceName(orig);
        final url = sourceAvatar(orig);
        final initial =
            name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.repeat, size: 18, color: scheme.primary),
                  ),
                  const SizedBox(width: 8),
                  if (loading)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    )
                  else if (orig != null) ...[
                    GestureDetector(
                      onTap: () => openSource(orig),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: scheme.surfaceContainerHighest,
                        backgroundImage: url != null
                            ? ResizeImage(
                                CachedNetworkImageProvider(
                                  ServerConfig.resolvePublisherAvatarUrl(url),
                                ),
                                width: 64,
                              )
                            : null,
                        child: url == null
                            ? Text(
                                initial,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Репост',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (!loading && orig != null) ...[
                          const SizedBox(height: 2),
                          GestureDetector(
                            onTap: () => openSource(orig),
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (comment != null && comment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  comment,
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
              ),
            const SizedBox(height: 6),
            if (!loading && orig == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Builder(
                  builder: (context) {
                    final id = _repostOriginalPostIdFromBody(wrapper.body);
                    if (id == null) return const SizedBox.shrink();
                    return OutlinedButton.icon(
                      onPressed: () {
                        FeedAnalyticsService.openDetail(
                          wrapper,
                          source: 'post_card',
                          target: 'original_post',
                        );
                        context.push('/post/$id');
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Открыть оригинал'),
                    );
                  },
                ),
              )
            else if (orig != null) ...[
              _withDoubleTapLikeOverlay(_buildMedia(orig)),
              if (resolvePostDisplayTitle(title: orig.title, body: orig.body) != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Text(
                    displayTitleForPost(orig),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (orig.description != null &&
                  orig.description!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text(
                    orig.description!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'только что';
        }
        return '${difference.inMinutes} мин назад';
      }
      return '${difference.inHours} ч назад';
    } else if (difference.inDays == 1) {
      return 'вчера';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн назад';
    } else {
      try {
        return DateFormat('d MMM', 'ru').format(date);
      } catch (e) {
        return DateFormat('d MMM').format(date);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _displayPost;
    final scheme = Theme.of(context).colorScheme;
    final author = post.author; // Автор оригинального поста
    final repostedBy = post.repostedBy; // Тот, кто репостнул
    final channel = post.channel;

    // Логика отображения автора:
    // 1. Если пост репостнут - в шапке показываем того, кто репостнул, ниже - оригинального автора
    // 2. Если пост из канала (channelId != null) - показываем канал
    // 3. Иначе - показываем автора поста
    final isRepost = repostedBy != null;
    final isFromChannel = post.channelId != null || post.communityId != null;
    final isFeedChannelRepostWrapper =
        _repostOriginalPostIdFromBody(post.body) != null;

    // Определяем оригинального автора поста (канал или пользователь)
    String? originalAuthorName;
    String? originalAuthorAvatar;
    bool originalAuthorIsChannel = false;

    if (isFromChannel) {
      // Оригинальный автор - канал
      originalAuthorName = channel?.name ?? 'Канал';
      originalAuthorAvatar = channel?.avatarUrl;
      originalAuthorIsChannel = true;
    } else {
      // Оригинальный автор - пользователь
      originalAuthorName = author?.name ?? post.author?.name;
      originalAuthorAvatar = author?.avatarUrl ?? post.author?.avatarUrl;
      originalAuthorIsChannel = false;
    }

    // Имя и аватар для шапки
    String displayName;
    String? displayAvatar;

    if (isRepost) {
      // Репост - в шапке показываем того, кто репостнул
      displayName = repostedBy.name;
      displayAvatar = repostedBy.avatarUrl;
    } else if (isFromChannel) {
      // Пост из канала - показываем канал
      displayName = channel?.name ?? 'Канал';
      displayAvatar = channel?.avatarUrl;
    } else {
      // Пост из профиля пользователя - показываем автора
      displayName = author?.name ?? post.author?.name ?? 'Неизвестный';
      displayAvatar = author?.avatarUrl ?? post.author?.avatarUrl;
    }

    final displayInitial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final hasFeedVideo =
        post.videoUrl != null && post.videoUrl!.trim().isNotEmpty;

    return PostCardContainer(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Компактная метка репоста (шапка скрыта — иначе репост неотличим от обычного поста)
          if (widget.hideFeedHeader && isRepost)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.repeat,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          if (originalAuthorIsChannel &&
                              post.channelId != null) {
                            context.push('/channel/${post.channelId}');
                          } else {
                            context.push('/profile?userId=${post.userId}');
                          }
                        },
                        child: CircleAvatar(
                          radius: 16,
                          backgroundImage: originalAuthorAvatar != null &&
                                  originalAuthorAvatar.isNotEmpty
                              ? ResizeImage(
                                  CachedNetworkImageProvider(
                                    ServerConfig.resolvePublisherAvatarUrl(
                                      originalAuthorAvatar,
                                    ),
                                  ),
                                  width: 64,
                                )
                              : null,
                          child: originalAuthorAvatar == null ||
                                  originalAuthorAvatar.isEmpty
                              ? Text(
                                  (originalAuthorName != null &&
                                          originalAuthorName.isNotEmpty)
                                      ? originalAuthorName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () {
                                context
                                    .push('/profile?userId=${repostedBy.id}');
                              },
                              child: Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Репост · '),
                                    TextSpan(
                                      text: repostedBy.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (repostedBy.comment != null &&
                                repostedBy.comment!.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                repostedBy.comment!.trim(),
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (!widget.hideFeedHeader && !hasFeedVideo)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Аватар (того, кто репостнул, или канала, или автора)
                  GestureDetector(
                    onTap: widget.onAuthorTap,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundImage: displayAvatar != null
                          ? ResizeImage(
                              CachedNetworkImageProvider(
                                ServerConfig.resolvePublisherAvatarUrl(
                                  displayAvatar,
                                ),
                              ),
                              width: 80,
                            )
                          : null,
                      child: displayAvatar == null
                          ? Text(
                              displayInitial,
                              style: const TextStyle(fontSize: 18),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Имя и время
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: widget.onAuthorTap,
                                child: Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    letterSpacing: -0.15,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '· ${_formatDate(post.publishedAt ?? post.createdAt)}',
                              maxLines: 1,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            // Показываем бейдж "Канал" только для постов из каналов (не репостов)
                            if (isFromChannel && !isRepost) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Канал',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Если репост, показываем оригинального автора со стрелочкой
                        if (isRepost && originalAuthorName != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              // Стрелочка вниз
                              Icon(
                                Icons.arrow_downward,
                                size: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              // Аватар оригинального автора (кликабельный)
                              GestureDetector(
                                onTap: () {
                                  // Если оригинальный автор - канал, открываем канал
                                  if (originalAuthorIsChannel &&
                                      post.channelId != null) {
                                    context.push('/channel/${post.channelId}');
                                  } else if (!originalAuthorIsChannel) {
                                    // Если оригинальный автор - пользователь, открываем профиль
                                    context
                                        .push('/profile?userId=${post.userId}');
                                  }
                                },
                                child: originalAuthorAvatar != null
                                    ? CircleAvatar(
                                        radius: 10,
                                        backgroundImage: ResizeImage(
                                          CachedNetworkImageProvider(
                                            ServerConfig
                                                .resolvePublisherAvatarUrl(
                                              originalAuthorAvatar,
                                            ),
                                          ),
                                          width: 40,
                                        ),
                                      )
                                    : CircleAvatar(
                                        radius: 10,
                                        backgroundColor: Colors.grey[400],
                                        child: Text(
                                          originalAuthorName[0].toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 6),
                              // Имя оригинального автора (кликабельное)
                              GestureDetector(
                                onTap: () {
                                  // Если оригинальный автор - канал, открываем канал
                                  if (originalAuthorIsChannel &&
                                      post.channelId != null) {
                                    context.push('/channel/${post.channelId}');
                                  } else if (!originalAuthorIsChannel) {
                                    // Если оригинальный автор - пользователь, открываем профиль
                                    context
                                        .push('/profile?userId=${post.userId}');
                                  }
                                },
                                child: Text(
                                  originalAuthorName,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (originalAuthorIsChannel) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color:
                                        scheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    'Канал',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: scheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (repostedBy.comment != null &&
                              repostedBy.comment!.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              repostedBy.comment!.trim(),
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ]
                        // Для постов из каналов показываем описание канала или "Канал"
                        else if (isFromChannel && !isFeedChannelRepostWrapper)
                          Text(
                            channel?.description ?? 'Канал',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        // Для постов из профиля показываем username автора
                        else if (author?.username != null)
                          Text(
                            '@${author!.username}',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ViewsBadge(count: _formatCount(post.viewsCount)),
                      const SizedBox(width: 6),
                      _buildOverflowMenuButton(iconSize: 24),
                    ],
                  ),
                ],
              ),
            ),
          if (isFeedChannelRepostWrapper)
            _buildFeedChannelRepostBody(post)
          else if (post.isPaid && !post.purchased)
            _buildPaidContentPaywall(post)
          else ...[
            _withDoubleTapLikeOverlay(
              _buildMedia(
                post,
                feedVideoAuthor: hasFeedVideo
                    ? FeedVideoAuthorInfo(
                        name: displayName,
                        avatarUrl: displayAvatar,
                        metaText:
                            _formatDate(post.publishedAt ?? post.createdAt),
                        viewsText: _formatCount(post.viewsCount),
                        subtitle: isFromChannel && !isRepost
                            ? (channel?.description ?? 'Канал')
                            : (author?.username != null
                                ? '@${author!.username}'
                                : null),
                        isChannel: isFromChannel && !isRepost,
                        onTap: widget.onAuthorTap,
                      )
                    : null,
              ),
            ),
            if (post.linkUrl != null && post.linkUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: InkWell(
                  onTap: () => _openLink(post.linkUrl!),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (post.linkImage != null &&
                            post.linkImage!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl:
                                    ServerConfig.resolvePublisherAvatarUrl(
                                  post.linkImage!,
                                ),
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                memCacheWidth: 800,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            const Icon(Icons.link, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                post.linkTitle ?? post.linkUrl!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        if (post.linkDescription != null &&
                            post.linkDescription!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              post.linkDescription!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (post.linkDomain != null &&
                            post.linkDomain!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              post.linkDomain!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (post.poll != null)
              PostPollSection(
                postId: post.id,
                poll: post.poll!,
                canClose: _isAuthor,
                onPollUpdated: _onPollUpdated,
              ),
          ],
          // Действия (Instagram-стиль: кнопки → лайки → подпись → комментарии)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _FeedActionButton(
                      icon: _isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: _formatCount(_likesCount),
                      color: _isLiked ? const Color(0xFFFF3040) : null,
                      busy: _isLiking,
                      onTap: _isLiking ? null : _toggleLike,
                    ),
                    const SizedBox(width: 12),
                    _FeedActionButton(
                      icon: Icons.mode_comment_outlined,
                      label: _formatCount(_displayCommentsCount),
                      busy: _isOpeningComments,
                      onTap: () {
                        if (_isOpeningComments) return;
                        unawaited(_openComments());
                      },
                    ),
                    const SizedBox(width: 12),
                    _FeedActionButton(
                      icon: Icons.near_me_outlined,
                      label: _formatCount(_repostsCount),
                      onTap: _isReposting ? null : _openShareSheet,
                    ),
                    if (!_isAuthor) ...[
                      const SizedBox(width: 12),
                      _FeedActionButton(
                        icon: Icons.volunteer_activism_outlined,
                        label: 'Донат',
                        color: scheme.primary,
                        onTap: _isSendingDonation ? null : _showDonateDialog,
                      ),
                    ],
                    const Spacer(),
                    if (widget.hideFeedHeader) ...[
                      _buildOverflowMenuButton(iconSize: 28),
                      const SizedBox(width: 4),
                    ],
                    _FeedIconButton(
                      icon: _isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: _isSaved ? scheme.primary : null,
                      onTap: _isSaving ? null : _toggleSave,
                    ),
                  ],
                ),
                if (_likesCount > 0) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: !_likesViaPostApi
                        ? null
                        : () => unawaited(
                              showPostLikersSheet(
                                context,
                                postId: widget.post.id,
                              ),
                            ),
                    child: _buildLikedByLine(scheme),
                  ),
                ],
                if (resolvePostDisplayTitle(title: post.title, body: post.body) !=
                        null ||
                    (post.description != null &&
                        post.description!.trim().isNotEmpty)) ...[
                  const SizedBox(height: 6),
                  _buildInstagramCaption(
                    authorName: displayName,
                    title: resolvePostDisplayTitle(
                      title: post.title,
                      body: post.body,
                    ),
                    description: post.description,
                  ),
                ],
                if (widget.post.previewComments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final preview in widget.post.previewComments.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: GestureDetector(
                        onTap: () => unawaited(_openComments()),
                        child: RichText(
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.3,
                              color: scheme.onSurface,
                            ),
                            children: [
                              TextSpan(
                                text: '${preview.authorName} ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(text: preview.text),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
                if (_displayCommentsCount > 0) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => unawaited(_openComments()),
                    child: Text(
                      _displayCommentsCount == 1
                          ? 'Смотреть комментарий'
                          : 'Смотреть все комментарии ($_displayCommentsCount)',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openComments() async {
    if (_isOpeningComments) return;
    if (!mounted) return;
    setState(() => _isOpeningComments = true);
    try {
      FeedAnalyticsService.openDetail(
        widget.post,
        source: 'post_card',
        target: 'comments',
      );
      if (widget.onCommentTap != null) {
        await widget.onCommentTap!.call();
      } else {
        await showPostCommentsSheet(
          context,
          postId: widget.post.id,
          post: widget.post,
          onCommentsCountChanged: (n) {
            if (mounted) setState(() => _displayCommentsCount = n);
          },
        );
      }
      await _refreshCommentsCount();
    } finally {
      if (mounted) {
        setState(() => _isOpeningComments = false);
      }
    }
  }

  Widget _buildLikedByLine(ColorScheme scheme) {
    final names = [
      for (final l in widget.post.previewLikers)
        if (l.name.trim().isNotEmpty) l.name.trim(),
    ].take(2).toList();
    final others =
        (_likesCount - (_isLiked ? 1 : 0) - names.length).clamp(0, 1 << 30);

    final style = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13.5,
      color: scheme.onSurface,
      height: 1.25,
    );

    String line;
    if (names.isEmpty) {
      if (_isLiked) {
        line = _likesCount <= 1
            ? 'Нравится вам'
            : 'Нравится вам и ещё ${_formatCount(_likesCount - 1)}';
      } else {
        line = _likesCount == 1
            ? '1 отметка «Нравится»'
            : '${_formatCount(_likesCount)} отметок «Нравится»';
      }
    } else if (_isLiked) {
      final first = names.first;
      final second = names.length > 1 ? names[1] : null;
      if (second != null) {
        line = others > 0
            ? 'Нравится вам, $first, $second и ещё ${_formatCount(others)}'
            : 'Нравится вам, $first и $second';
      } else {
        line = others > 0
            ? 'Нравится вам, $first и ещё ${_formatCount(others)}'
            : 'Нравится вам и $first';
      }
    } else {
      final first = names.first;
      final second = names.length > 1 ? names[1] : null;
      if (second != null) {
        line = others > 0
            ? 'Нравится $first, $second и ещё ${_formatCount(others)}'
            : 'Нравится $first и $second';
      } else {
        line = others > 0
            ? 'Нравится $first и ещё ${_formatCount(others)}'
            : 'Нравится $first';
      }
    }

    return Text(line, style: style);
  }

  Widget _buildInstagramCaption({
    required String authorName,
    String? title,
    String? description,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[
      if (title != null && title.trim().isNotEmpty) title.trim(),
      if (description != null && description.trim().isNotEmpty)
        description.trim(),
    ];
    final full = parts.join('\n');
    if (full.isEmpty) return const SizedBox.shrink();

    const previewLimit = 120;
    final needsMore = full.length > previewLimit;
    final shown = !_captionExpanded && needsMore
        ? '${full.substring(0, previewLimit).trimRight()}…'
        : full;

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: scheme.onSurface,
        ),
        children: [
          TextSpan(
            text: '$authorName ',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(text: shown),
          if (needsMore && !_captionExpanded)
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => setState(() => _captionExpanded = true),
                child: Text(
                  ' ещё',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Используем утилиту для форматирования чисел
  String _formatCount(int count) => NumberFormatter.formatCount(count);


  String _getProxyUrl(String originalUrl) {
    return ServerConfig.resolveRecipeImageUrl(originalUrl);
  }

  /// Построить виджет для отображения медиа поста
  Widget _buildPaidContentPaywall(PostModel post) {
    final mediaCount = post.body?['media_count'] as int? ?? 0;
    return PaidContentPaywallCard(
      priceStars: post.priceStars,
      mediaCount: mediaCount,
      isLoading: _isLoading,
      onPurchase: _purchasePaidContent,
    );
  }

  Widget _buildMedia(
    PostModel post, {
    FeedVideoAuthorInfo? feedVideoAuthor,
  }) {
    // Получаем медиа из body
    final body = post.body;
    if (body == null) {
      if (post.videoUrl != null &&
          post.videoUrl!.isNotEmpty &&
          feedVideoAuthor != null) {
        return FeedVideoPlayer(
          videoUrl: post.videoUrl!,
          thumbnailUrl: post.videoThumbnail,
          author: feedVideoAuthor,
          onDoubleTap: _handleDoubleTapLike,
          onOpenFullscreen: () {
            FeedAnalyticsService.openDetail(
              post,
              source: 'post_card',
              target: 'reel_fullscreen',
            );
            context.push(ReelsFullscreenRoute.path, extra: post);
          },
        );
      }
      return const SizedBox.shrink();
    }

    final media = body['media'] as List<dynamic>?;

    // Если media пустой, пытаемся собрать превью из известных полей body.
    List<dynamic>? effectiveMedia = media;
    if (media == null || media.isEmpty) {
      final imageUrl = _extractLegacyBodyImageUrl(body);
      if (imageUrl != null && imageUrl.isNotEmpty) {
        effectiveMedia = [
          {
            'type': 'image',
            'url': imageUrl,
          }
        ];
      } else if (post.videoUrl != null && post.videoUrl!.isNotEmpty) {
        effectiveMedia = [
          {
            'type': 'video',
            'url': post.videoUrl,
            if (post.videoThumbnail != null)
              'thumbnail_url': post.videoThumbnail,
          }
        ];
      }
    }

    if (effectiveMedia == null || effectiveMedia.isEmpty) {
      return const SizedBox.shrink();
    }

    // Показываем изображения для всех типов постов, если они есть (как в Telegram)
    final images = effectiveMedia.where((m) => m['type'] == 'image').toList();
    if (images.isNotEmpty) {
      // Обработчик клика для открытия детальной страницы поста
      void onMediaTap() {
        if (post.channelId != null) {
          // Если пост из канала, открываем детальную страницу поста канала
          FeedAnalyticsService.openDetail(
            post,
            source: 'post_card',
            target: 'channel_post',
          );
          context.push('/channel/${post.channelId}/post/${post.id}');
        }
        // Для обычных постов пока просто ничего не делаем (можно добавить роут позже)
      }

      // Извлекаем URL изображений (с proxy для legacy CDN при необходимости)
      final imageUrls = images
          .map((img) => img['url'] as String?)
          .whereType<String>()
          .where((url) => url.isNotEmpty)
          .map((url) => _getProxyUrl(url))
          .toList();

      if (imageUrls.isNotEmpty) {
        final screenWidth = MediaQuery.of(context).size.width;
        final reelHeight = screenWidth * 16 / 9;
        return TelegramPhotoGrid(
          imageUrls: imageUrls,
          maxHeight: reelHeight,
          singleAspectRatio: 9 / 16,
          borderRadius: BorderRadius.circular(18),
          onDoubleTap: _handleDoubleTapLike,
          enableFullscreen: true,
        );
      }
    }

    // Показываем видео для всех типов постов, если они есть (Instagram-style inline autoplay)
    final videos = effectiveMedia.where((m) => m['type'] == 'video').toList();
    if (videos.isNotEmpty) {
      final rawVideoUrl = videos[0]['url'] as String;
      final rawThumbnailUrl = videos[0]['thumbnail_url'] as String? ??
          body['thumbnail_url'] as String?;
      final videoUrl = ServerConfig.resolveMediaUrl(rawVideoUrl);
      final thumbnailUrl = rawThumbnailUrl != null
          ? ServerConfig.resolveMediaUrl(rawThumbnailUrl)
          : null;
      if (feedVideoAuthor != null) {
        return FeedVideoPlayer(
          videoUrl: videoUrl,
          thumbnailUrl: thumbnailUrl,
          author: feedVideoAuthor,
          onDoubleTap: _handleDoubleTapLike,
          onOpenFullscreen: () {
            FeedAnalyticsService.openDetail(
              post,
              source: 'post_card',
              target: 'reel_fullscreen',
            );
            context.push(ReelsFullscreenRoute.path, extra: post);
          },
        );
      }
      return FeedVideoPlayer(
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        author: FeedVideoAuthorInfo(
          name: post.author?.name ?? 'Автор',
          metaText: _formatDate(post.publishedAt ?? post.createdAt),
          viewsText: _formatCount(post.viewsCount),
        ),
        onDoubleTap: _handleDoubleTapLike,
        onOpenFullscreen: () {
          FeedAnalyticsService.openDetail(
            post,
            source: 'post_card',
            target: 'reel_fullscreen',
          );
          context.push(ReelsFullscreenRoute.path, extra: post);
        },
      );
    }

    return const SizedBox.shrink();
  }

  String? _extractLegacyBodyImageUrl(Map<String, dynamic> body) =>
      extractLegacyBodyImageUrl(body);

}

class _ViewsBadge extends StatelessWidget {
  const _ViewsBadge({required this.count});

  final String count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            count,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
          ),
        ],
      ),
    );
  }
}

class _FeedActionButton extends StatelessWidget {
  const _FeedActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: busy
                  ? SizedBox(
                      key: const ValueKey('busy'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: fg,
                      ),
                    )
                  : Icon(
                      icon,
                      key: const ValueKey('icon'),
                      size: 27,
                      color: onTap == null ? scheme.outline : fg,
                    ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: onTap == null ? scheme.outline : scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedIconButton extends StatelessWidget {
  const _FeedIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 29,
          color: onTap == null ? scheme.outline : (color ?? scheme.onSurface),
        ),
      ),
    );
  }
}

class _RepostDialog extends StatefulWidget {
  const _RepostDialog();

  @override
  State<_RepostDialog> createState() => _RepostDialogState();
}

class _RepostDialogState extends State<_RepostDialog> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Репостнуть пост?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(
              labelText: 'Комментарий (опционально)',
              hintText: 'Добавьте комментарий к репосту...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop({
              'comment': _commentController.text.trim().isEmpty
                  ? null
                  : _commentController.text.trim(),
            });
          },
          child: const Text('Репостнуть'),
        ),
      ],
    );
  }
}
