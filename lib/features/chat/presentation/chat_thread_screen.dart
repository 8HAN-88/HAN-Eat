import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';

import '../../../core/share/system_share.dart';

import '../../bots/data/bot_inline_service.dart';
import '../../bots/presentation/inline_suggestions.dart';
import '../../miniapps/data/miniapps_service.dart';
import '../../miniapps/presentation/miniapp_webview_screen.dart';
import '../../bots/data/bot_models.dart';
import '../../../services/api_service.dart';
import '../../calls/call_message_labels.dart';
import '../../calls/presentation/call_coordinator.dart';

import '../../../app/app_router.dart';
import '../../../core/theme/color_schemes.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/network/feed_load_helper.dart';
import '../../../core/network/haneat_http_client.dart';
import '../../../core/platform/device_location.dart';
import '../../../core/platform/web_page_visibility.dart';
import '../../../models/chat_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/subscription_status_cache.dart';
import '../../subscription/creator_upsell.dart';
import '../../../services/api_reachability_service.dart';
import '../../../services/chat_cache_service.dart';
import '../../../services/chat_media_outbox_service.dart';
import '../../../services/feed_sync_service.dart';
import '../../../services/paid_features_service.dart';
import '../../../services/product_analytics.dart';
import '../../../services/chat_service.dart';
import '../../../services/chat_stream_service.dart';
import '../../../services/user_realtime_service.dart';
import '../../../services/phone_contacts_service.dart';
import '../../../services/share_link_service.dart';
import '../../../utils/chat_time_format.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/media_download_helper.dart';
import '../../../utils/session_snackbar.dart';
import '../../../widgets/app_avatar.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/chat_link_preview.dart';
import '../../../widgets/fullscreen_image_viewer.dart';
import '../../../widgets/custom_emoji_view.dart';
import '../../../widgets/highlighted_text.dart';
import '../../../services/custom_emoji_registry.dart';
import '../../../services/emoji_pack_service.dart';
import '../../../models/emoji_pack_models.dart';
import '../../../widgets/chat_bubble_accent.dart';
import '../../../widgets/chat_wallpaper.dart';
import '../../../widgets/telegram_ui.dart';
import '../application/active_chat_session.dart';
import '../application/chat_auto_delete.dart';
import '../application/anonymous_admin.dart';
import '../application/chat_mentions.dart';
import '../application/chat_reaction_jumps.dart';
import '../application/chat_reaction_optimistic.dart';
import '../application/chat_search_date.dart';
import '../application/chat_message_integrate.dart';
import '../application/chat_inbox_optimistic.dart';
import '../application/chat_open_direct.dart';
import '../application/chat_ready_outgoing.dart';
import '../application/chat_thread_prefetch.dart';
import '../application/chat_private_reply.dart';
import '../application/chat_realtime_signals.dart';
import '../application/chat_voice_playback_coordinator.dart';
import '../application/chats_hub_refresh_provider.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/server_config.dart';
import '../../../services/chat_thread_ui_prefs.dart';
import '../../../utils/presence_format.dart';
import '../../../utils/video_player_helper.dart';
import '../../../widgets/inline_video_player.dart';
import '../../../widgets/chat_target_picker_sheet.dart';
import '../../../widgets/chat_sticker_tile.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../widgets/stars_pay_helper.dart';
import 'widgets/chat_message_action_overlay.dart';
import 'widgets/message_effect_overlay.dart';
import 'widgets/chat_message_selection_toolbar.dart';
import '../application/chat_recent_files_store.dart';
import '../application/chat_recent_gifs_store.dart';
import 'widgets/chat_attach_sheet.dart';
import 'widgets/chat_contact_bubble.dart';
import 'widgets/chat_location_bubble.dart';
import 'widgets/chat_story_reply_bubble.dart';
import '../application/live_location_session.dart';
import 'widgets/chat_message_readers_sheet.dart';
import 'widgets/chat_message_reactors_sheet.dart';
import 'widgets/chat_mute_duration_sheet.dart';
import 'widgets/chat_video_note_bubble.dart';
import 'widgets/chat_inline_sticker_panel.dart';
import 'widgets/chat_media_compose_sheet.dart';
import 'widgets/chat_checklist_bubble.dart';
import 'widgets/chat_poll_bubble.dart';
import 'widgets/chat_poll_voters_sheet.dart';
import 'widgets/create_chat_checklist_sheet.dart';
import 'widgets/create_chat_poll_sheet.dart';
import 'widgets/paid_media_lock_bubble.dart';
import 'widgets/star_gift_picker_sheet.dart';
import '../widgets/chat_voice_mic_button.dart';
import '../widgets/chat_voice_waveform.dart';
import 'chat_group_info_screen.dart';
import 'chat_media_gallery_screen.dart';
import 'manual_retry_utils.dart';
import 'chat_voice_bubble.dart';

/// Загружает чат с API, если не передан в [extra] (push / deep link).
class ChatThreadLoaderScreen extends ConsumerStatefulWidget {
  const ChatThreadLoaderScreen({
    super.key,
    required this.conversationId,
    this.initialConversation,
    this.initialPeer,
    this.initialJumpMessageId,
    this.initialDraftText,
    this.initialPrivateReply,
  });

  final int conversationId;
  final ChatConversation? initialConversation;
  final ChatUserBrief? initialPeer;
  final int? initialJumpMessageId;
  final String? initialDraftText;
  final ChatPrivateReplyQuote? initialPrivateReply;

  @override
  ConsumerState<ChatThreadLoaderScreen> createState() =>
      _ChatThreadLoaderScreenState();
}

class _ChatThreadLoaderScreenState
    extends ConsumerState<ChatThreadLoaderScreen> {
  ChatConversation? _conversation;
  bool _loading = false;
  bool _openedFromStub = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _conversation = widget.initialConversation;
    if (_conversation == null && widget.initialPeer != null) {
      _conversation = ChatConversation(
        id: widget.conversationId,
        type: 'direct',
        peer: widget.initialPeer,
        updatedAt: DateTime.now(),
      );
    }
    _conversation ??= ChatCacheService.peekConversation(widget.conversationId);
    if (_conversation == null) {
      _conversation = ChatConversation(
        id: widget.conversationId,
        type: 'direct',
        updatedAt: DateTime.now(),
      );
      _openedFromStub = true;
    }
    if (widget.conversationId > 0) {
      unawaited(ChatThreadPrefetch.warm(widget.conversationId));
    }
    unawaited(_hydrateConversation());
  }

  Future<void> _resolveConversation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _hydrateConversation();
    if (mounted && _conversation == null) {
      setState(() => _loading = false);
    }
  }

  Future<void> _hydrateConversation() async {
    if (_openedFromStub) {
      final disk = await ChatCacheService.loadConversations();
      if (disk != null) {
        for (final chat in disk) {
          if (chat.id != widget.conversationId) continue;
          if (!mounted) return;
          setState(() {
            _conversation = chat;
            _openedFromStub = false;
            _loading = false;
            _error = null;
          });
          break;
        }
      }
    }
    try {
      final peerId = widget.initialPeer?.id ??
          widget.initialConversation?.peer?.id ??
          _conversation?.peer?.id;
      final conv = (widget.conversationId <= 0 && peerId != null && peerId > 0)
          ? await ChatOpenDirect.resolve(peerId)
          : await ChatService.getConversation(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _conversation = conv;
        _openedFromStub = false;
        _loading = false;
        _error = null;
      });
      unawaited(ChatCacheService.upsertConversation(conv));
      if (conv.id > 0) {
        unawaited(ChatThreadPrefetch.warm(conv.id));
      }
    } catch (e) {
      if (!mounted) return;
      if (_openedFromStub) {
        setState(() {
          _error = e;
          _conversation = null;
          _loading = false;
        });
      }
    }
  }

  void _refreshHub() {
    ref.read(chatsHubRefreshProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    if (_conversation != null) {
      return PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _refreshHub();
        },
        child: ChatThreadScreen(
          conversation: _conversation!,
          initialJumpMessageId: widget.initialJumpMessageId,
          initialDraftText: widget.initialDraftText,
          initialPrivateReply: widget.initialPrivateReply,
        ),
      );
    }
    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(),
      body: AppEmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'Чат не найден',
        subtitle: _error != null
            ? userVisibleError(_error!)
            : 'Нет доступа к диалогу',
        action: FilledButton(
          onPressed: _resolveConversation,
          child: const Text('Повторить'),
        ),
      ),
    );
  }
}

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversation,
    this.initialJumpMessageId,
    this.initialDraftText,
    this.initialPrivateReply,
  });

  final ChatConversation conversation;
  final int? initialJumpMessageId;
  final String? initialDraftText;
  final ChatPrivateReplyQuote? initialPrivateReply;

  int get conversationId => conversation.id;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

bool _chatIsGifMediaUrl(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return path.endsWith('.gif');
}

enum _ThreadSearchFilter {
  all,
  text,
  media,
  files,
  links,
  mine,
}

class _SearchSenderOption {
  const _SearchSenderOption({
    required this.value,
    required this.label,
    this.senderId,
  });

  final int value;
  final String label;
  final int? senderId;
}

class _ChatThreadScreenState extends State<ChatThreadScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _threadSearchController = TextEditingController();
  final _threadSearchFocusNode = FocusNode();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _loadError;
  bool _sending = false;
  double? _uploadProgress;
  String _sendingStatus = 'Отправка…';
  final Map<int, _PendingTextSend> _failedTextSends = {};
  final Map<int, DateTime> _failedTextAutoRetryUntil = {};
  final Map<int, Timer> _failedTextAutoRetryTimers = {};
  final Map<int, String> _failedTextAutoRetryReason = {};
  final List<_PendingTextSend> _textOutboundQueue = [];
  bool _textDrainActive = false;
  final Set<String> _inFlightTextClientIds = {};
  final List<ChatReadyOutgoing> _readyOutboundQueue = [];
  final Map<int, ChatReadyOutgoing> _failedReadySends = {};
  final Set<String> _inFlightReadyClientIds = {};
  final List<_PendingMediaSend> _mediaOutboundQueue = [];
  bool _mediaDrainActive = false;
  _PendingMediaSend? _pendingMediaRetry;
  final Set<String> _inFlightMediaClientIds = {};
  final Map<int, _PendingMediaSend> _pendingMediaByTempId = {};
  final Map<String, int> _pendingMediaTempIdByClientId = {};
  final Map<String, double> _pendingMediaProgressByClientId = {};
  final Set<String> _cancelledPendingMediaClientIds = {};
  final Set<int> _unlockingMessageIds = {};
  bool _voiceSending = false;
  List<ChatSavedTag> _savedTags = const [];
  int? _activeSavedTagId;
  bool _hasMore = false;
  int? _nextCursor;
  Timer? _pollTimer;
  bool _pollInFlight = false;
  Timer? _presenceTimer;
  Timer? _typingDebounce;
  Timer? _recordingPresenceTimer;
  Timer? _inlineDebounce;
  List<InlineResult> _inlineResults = [];
  OverlayEntry? _inlineOverlayEntry;
  List<BotListItem> _myBots = [];
  List<ChatBotCommand> _botCommands = [];
  OverlayEntry? _botAutocompleteOverlayEntry;
  StreamSubscription<void>? _signalSub;
  StreamSubscription<UserRealtimeEvent>? _presenceSub;
  VoidCallback? _apiReachabilityListener;
  VoidCallback? _apiConnectingListener;
  VoidCallback? _deviceOnlineListener;
  ValueListenable<bool>? _deviceOnlineListenable;
  ChatStreamService? _stream;
  ChatMessage? _replyTo;
  ChatPrivateReplyQuote? _privateReply;
  bool _appPaused = false;
  bool _sseConnected = false;
  bool _peerTyping = false;
  bool _pinned = false;
  bool _muted = false;
  bool _retryAllBulkBusy = false;
  bool _retryAllBulkCancelRequested = false;
  bool _clearAllAfterBulkStopRequested = false;
  int _retryAllBulkDone = 0;
  int _retryAllBulkTotal = 0;
  bool _recording = false;
  /// Session confirm for paid-DM fee (once per thread until cancelled).
  bool _paidDmFeeConfirmed = false;
  bool _sendingStarGift = false;
  bool _sendingPaidReaction = false;
  final Set<int> _giftActionMessageIds = {};
  bool _holdActive = false;
  bool _recordCancelled = false;
  bool _voiceLocked = false;
  /// Empty-composer mode: false = voice hold, true = video note (tap).
  bool _videoNoteComposerMode = false;
  bool _stickerPanelOpen = false;
  bool _hasText = false;
  List<ChatQuickReply> _quickReplies = const [];
  String? _composerLinkPreviewUrl;
  String? _composerLinkPreviewDismissedUrl;
  Timer? _composerLinkDebounce;
  List<ChatMessage> _serverSearchHits = const [];
  int _serverSearchSeq = 0;
  Duration _recordDuration = Duration.zero;
  int _messageLoadSeq = 0;
  bool _consumedPrefetchPage = false;
  Timer? _recordTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _markReadDebounce;
  Timer? _markDeliveredDebounce;
  Timer? _draftSaveDebounce;
  final List<double> _waveLevels = [];
  final _audioRecorder = AudioRecorder();
  late ChatConversation _conversation;
  Map<int, String> _senderNames = {};
  List<ChatUserBrief> _groupMembers = [];
  List<ChatForumTopic> _forumTopics = const [];
  int? _selectedTopicId;
  bool _forumTopicsLoading = false;
  bool _threadSearchOpen = false;
  bool _showOnlyFailedMessages = false;
  String _threadSearchQuery = '';
  _ThreadSearchFilter _threadSearchFilter = _ThreadSearchFilter.all;
  int? _threadSearchSenderId;
  DateTime? _threadSearchDate;
  int _searchMatchIndex = 0;
  bool _searchAutoloading = false;
  int _searchBackfillLoads = 0;
  int _searchBackfillSeq = 0;
  bool _jumpingToDate = false;
  final List<ChatMessage> _pinnedMessages = [];
  final Set<int> _revealedSpoilerIds = <int>{};
  int _pinnedBannerIndex = 0;
  ChatMessage? get _pinnedMessage {
    if (_pinnedMessages.isEmpty) return null;
    final idx = _pinnedBannerIndex % _pinnedMessages.length;
    return _pinnedMessages[idx];
  }
  bool _isMessagePinned(int messageId) =>
      _pinnedMessages.any((m) => m.id == messageId);
  void _setPinnedMessages(Iterable<ChatMessage> items) {
    _pinnedMessages
      ..clear()
      ..addAll(items);
    _pinnedBannerIndex = 0;
  }
  void _upsertPinnedMessage(ChatMessage msg) {
    _pinnedMessages.removeWhere((m) => m.id == msg.id);
    _pinnedMessages.insert(0, msg);
    _pinnedBannerIndex = 0;
  }
  void _removePinnedMessageId(int messageId) {
    _pinnedMessages.removeWhere((m) => m.id == messageId);
    if (_pinnedMessages.isEmpty) {
      _pinnedBannerIndex = 0;
    } else {
      _pinnedBannerIndex %= _pinnedMessages.length;
    }
  }
  void _replacePinnedMessage(ChatMessage msg) {
    final idx = _pinnedMessages.indexWhere((m) => m.id == msg.id);
    if (idx >= 0) _pinnedMessages[idx] = msg;
  }
  void _cyclePinnedBanner() {
    final current = _pinnedMessage;
    if (current == null) return;
    unawaited(_jumpToPinnedMessage(current));
    if (_pinnedMessages.length > 1) {
      setState(() {
        _pinnedBannerIndex =
            (_pinnedBannerIndex + 1) % _pinnedMessages.length;
      });
    }
  }

  Future<void> _jumpToPinnedMessage(ChatMessage msg) async {
    await _scrollToReplyMessage(msg.id);
    if (!mounted) return;
    _focusMessageTemporarily(msg.id);
  }

  Widget? _pinnedMediaLeading(ChatMessage msg) {
    final url = msg.mediaUrl?.trim();
    if (url == null || url.isEmpty) return null;
    if (msg.type != 'image' &&
        msg.type != 'sticker' &&
        msg.type != 'video' &&
        msg.type != 'video_note') {
      return null;
    }
    final resolved = ServerConfig.resolveMediaUrl(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 40,
        height: 40,
        child: msg.type == 'video' || msg.type == 'video_note'
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Icon(Icons.videocam_outlined, size: 20),
                  ),
                  const Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                ],
              )
            : CachedNetworkImage(
                imageUrl: resolved,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => ColoredBox(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  child: Icon(
                    msg.type == 'sticker'
                        ? Icons.emoji_emotions_outlined
                        : Icons.photo_outlined,
                    size: 20,
                  ),
                ),
              ),
      ),
    );
  }
  ChatMessage? _editingMessage;
  bool _showJumpToBottom = false;
  bool _jumpFabTargetsUnread = false;
  int _newMessagesBelow = 0;
  /// Session queue for cycling unread @mentions (survives mark-read badge clear).
  List<int> _unreadMentionQueue = const [];
  int _unreadMentionCursor = 0;
  /// Session queue for cycling unread reactions (survives mark-read badge clear).
  List<int> _unreadReactionQueue = const [];
  int _unreadReactionCursor = 0;
  /// Group admins: post as the group title (Telegram anonymous admin).
  bool _sendAnonymously = false;

  bool get _effectiveSendAnonymous =>
      _sendAnonymously &&
      canSendAnonymously(
        isGroup: _conversation.isGroup,
        amIGroupAdmin: _conversation.amIGroupAdmin,
      );
  int? _replySwipeMsgId;
  double _replySwipeDx = 0;
  String? _floatingDateLabel;
  bool _floatingDateVisible = false;
  Timer? _floatingDateHideTimer;
  bool _suppressMarkRead = false;
  /// Telegram-style unread divider shown above this message id.
  int? _unreadDividerBeforeId;
  final Set<int> _typingUserIds = <int>{};
  final Map<int, Timer> _typingUserTimers = <int, Timer>{};
  /// userId → `typing` | `recording`
  final Map<int, String> _typingActivityByUser = <int, String>{};
  /// Group: peer userId → last_read_message_id seen via SSE (for read_count).
  final Map<int, int> _peerGroupReadCursors = <int, int>{};
  bool _selectionMode = false;
  final _selectedMessageIds = <int>{};
  final _votingPollIds = <int>{};
  final _togglingChecklistIds = <int>{};
  final _transcribingIds = <int>{};
  final _closingPollIds = <int>{};
  final _callbackInFlightKeys = <String>{};
  final _composerPanelKey = GlobalKey();
  final Map<int, GlobalKey> _messageItemKeys = {};
  final _animatedMessageIds = <int>{};
  int _pollFailureCount = 0;
  int _scheduledPendingCount = 0;
  int? _pendingInitialJumpMessageId;
  int? _focusedMessageId;
  Timer? _focusedMessageTimer;
  Timer? _slowModeCountdownTimer;
  Timer? _autoDeleteTicker;
  Timer? _pendingMediaAutoRetryTimer;
  Timer? _manualReadyRetryTimer;
  Timer? _muteUnmuteTimer;
  DateTime? _slowModeLockUntil;
  DateTime? _floodLockUntil;
  DateTime? _pendingMediaAutoRetryUntil;
  DateTime? _manualReadyRetryUntil;
  int _manualReadyRetryDeferrals = 0;
  int _floodCooldownTotalSeconds = 0;
  int? _lastSlowModeTick;
  bool _slowModeCountdownHapticsEnabled = true;
  bool _autoRetryOnLimitsEnabled = true;
  bool _showFormatBar = false;
  ChatWallpaperStyle _wallpaperStyle = ChatWallpaperStyle.defaultStyle;
  ChatBubbleAccent _bubbleAccent = ChatBubbleAccent.defaultStyle;
  String? _wallpaperCustomPath;
  ImageProvider? _wallpaperImage;
  final Map<int, String> _autoTranslations = {};
  String? _pendingMediaAutoRetryClientMessageId;
  String? _pendingMediaAutoRetryReason;

  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
  static const _baseOverlayReactions = ['👍', '👌', '❤️', '👎', '👏'];
  static const _exclusiveOverlayReactions = ['🔥', '🥰', '🎉', '✨', '⚡️', '💯'];

  bool _hasFlexFeature(String slug) =>
      SubscriptionStatusCache.peek()?.hasFeature(slug) == true;

  Future<void> _loadQuickReplies() async {
    try {
      final items = await ChatService.listQuickReplies();
      if (!mounted) return;
      setState(() => _quickReplies = items);
    } catch (_) {}
  }

  Future<void> _insertQuickReply(ChatQuickReply reply) async {
    final next = reply.text;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _inputFocusNode.requestFocus();
  }

  Future<void> _createQuickReply() async {
    if (!_hasFlexFeature('quick_replies')) {
      await showCreatorUpsell(context);
      return;
    }
    final titleCtl = TextEditingController();
    final textCtl = TextEditingController(text: _controller.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Быстрый ответ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtl,
              decoration: const InputDecoration(labelText: 'Название'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: textCtl,
              decoration: const InputDecoration(labelText: 'Текст'),
              minLines: 2,
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ChatService.createQuickReply(
        title: titleCtl.text.trim(),
        text: textCtl.text.trim(),
      );
      if (!mounted) return;
      await _loadQuickReplies();
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      if (offerPackStoreIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _deleteQuickReply(ChatQuickReply reply) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить быстрый ответ?'),
        content: HighlightedText(
          text: reply.title.isEmpty ? reply.text : reply.title,
          style: Theme.of(ctx).textTheme.bodyMedium ??
              const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ChatService.deleteQuickReply(replyId: reply.id);
      if (!mounted) return;
      await _loadQuickReplies();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  List<String> get _overlayReactions {
    final unlocked =
        SubscriptionStatusCache.peek()?.hasFeature('exclusive_reactions') == true;
    if (unlocked) {
      return [..._baseOverlayReactions, ..._exclusiveOverlayReactions];
    }
    return _baseOverlayReactions;
  }
  static const _uiAnimDuration = Duration(milliseconds: 160);
  static const _composerIconSize = 20.0;
  static const _composerButtonSide = 40.0;
  static const _telegramAccent = AppColors.primary;
  static const _uploadAccent = AppColors.primary;
  static const _deleteForEveryoneMaxAge = Duration(hours: 48);

  bool get _canPinMessages =>
      !_conversation.isGroup ||
      _conversation.amICanPinMessages ||
      (_conversation.createdByUserId != null &&
          _conversation.createdByUserId == AuthService.instance.currentUser?.id);

  bool get _canManageGroupCalls =>
      !_conversation.isGroup ||
      _conversation.amICanManageVideoChats ||
      (_conversation.createdByUserId != null &&
          _conversation.createdByUserId == AuthService.instance.currentUser?.id);

  bool _canDeleteMessageForEveryone(ChatMessage msg) {
    if (msg.id <= 0) return false;
    if (_conversation.isGroup && _conversation.amICanDeleteMessages) {
      return true;
    }
    if (!msg.isMine) return false;
    return DateTime.now().difference(msg.createdAt.toLocal()) <=
        _deleteForEveryoneMaxAge;
  }

  ChatReplyKeyboard? _replyKeyboard;
  String? _activeEffectId;
  int? _activeEffectToken;
  final Set<int> _playedEffectMessageIds = {};

  static const _premiumMessageEffects = {'confetti', 'fireworks', 'celebration'};
  static const _messageEffects = <(String, String, IconData)>[
    ('confetti', 'Конфетти', Icons.celebration_outlined),
    ('fireworks', 'Фейерверк', Icons.auto_awesome),
    ('hearts', 'Сердца', Icons.favorite_outline),
    ('celebration', 'Праздник', Icons.party_mode_outlined),
    ('thumbs_up', 'Класс', Icons.thumb_up_alt_outlined),
  ];

  List<(String, String, IconData)> get _availableMessageEffects {
    final unlocked =
        SubscriptionStatusCache.peek()?.hasFeature('message_effects') == true;
    if (unlocked) return _messageEffects;
    return [
      for (final effect in _messageEffects)
        if (!_premiumMessageEffects.contains(effect.$1)) effect,
    ];
  }

  void _playMessageEffect(String? effectId, {int? messageId}) {
    final id = (effectId ?? '').trim();
    if (id.isEmpty) return;
    if (messageId != null) {
      if (_playedEffectMessageIds.contains(messageId)) return;
      _playedEffectMessageIds.add(messageId);
      if (_playedEffectMessageIds.length > 80) {
        _playedEffectMessageIds.remove(_playedEffectMessageIds.first);
      }
    }
    setState(() {
      _activeEffectId = id;
      _activeEffectToken = DateTime.now().millisecondsSinceEpoch;
    });
  }

  void _applyReplyKeyboard(ChatReplyKeyboard? kb) {
    if (kb == null) return;
    if (kb.remove || kb.isEmpty) {
      _replyKeyboard = null;
      return;
    }
    _replyKeyboard = kb;
  }

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _replyKeyboard = widget.conversation.replyKeyboard;
    if (_replyKeyboard != null &&
        (_replyKeyboard!.remove || _replyKeyboard!.isEmpty)) {
      _replyKeyboard = null;
    }
    _pendingInitialJumpMessageId = widget.initialJumpMessageId;
    _privateReply = widget.initialPrivateReply;
    _pinned = widget.conversation.pinned;
    _muted = widget.conversation.muted;
    ActiveChatSession.instance.setOpen(widget.conversationId);
    WidgetsBinding.instance.addObserver(this);
    _inputFocusNode.addListener(_onComposerFocusChanged);
    _scroll.addListener(_onScrollChanged);
    _controller.addListener(_onInputChanged);
    final warm = ChatCacheService.peekThread(widget.conversationId);
    if (warm != null && warm.isNotEmpty) {
      _messages.addAll(warm);
      _loading = false;
      _prefetchCustomEmojis(warm);
    }
    unawaited(_loadCachedMessages().then((_) async {
      await _restoreFailedTextSends();
      await _restoreReadyOutbox();
      await _restoreMediaOutbox();
    }));
    unawaited(_loadSlowModeUiPrefs());
    unawaited(_restoreDraft());
    unawaited(AuthService.getAccessTokenForApi());
    unawaited(_loadQuickReplies());
    unawaited(_loadMyBots());
    unawaited(_loadBotCommands());
    unawaited(_refreshScheduledPendingCount());
    unawaited(_syncMuteSchedule());
    if (_conversation.isForum) {
      unawaited(_loadForumTopics(selectGeneralIfNeeded: true));
    }
    if (_conversation.isSaved) {
      unawaited(_loadSavedTags());
    }
    if (widget.conversationId > 0) {
      _load(refresh: true);
    } else {
      _loading = false;
    }
    _startPolling();
    _syncAutoDeleteTicker();
    // Fallback poll; primary presence updates come via user.presence SSE.
    _presenceTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_appPaused) _refreshConversation();
    });
    _presenceSub = UserRealtimeService.instance.events.listen((event) {
      if (!mounted) return;
      if (event.event == 'chat.auto_delete' &&
          event.conversationId == widget.conversationId &&
          event.autoDeleteSeconds != null) {
        _applyAutoDeleteSeconds(event.autoDeleteSeconds!);
        return;
      }
      if (event.event == 'chat.history_cleared' &&
          event.conversationId == widget.conversationId) {
        _applyHistoryClearedLocally();
        return;
      }
      if (event.event == 'chat.deleted' &&
          event.conversationId == widget.conversationId) {
        unawaited(ChatCacheService.saveThread(widget.conversationId, const []));
        unawaited(ChatCacheService.clearDraft(widget.conversationId));
        try {
          ProviderScope.containerOf(context)
              .read(chatsHubRefreshProvider.notifier)
              .state++;
        } catch (_) {}
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        return;
      }
      if ((event.event == 'chat.mute' ||
              event.event == 'chat.pin' ||
              event.event == 'chat.archive') &&
          event.conversationId == widget.conversationId) {
        setState(() {
          _conversation = _conversation.copyWith(
            muted: event.muted ?? _conversation.muted,
            mutedUntil: event.mutedUntil,
            clearMutedUntil:
                event.event == 'chat.mute' &&
                (event.muted != true || event.mutedUntil == null),
            notifyMode: event.notifyMode ?? _conversation.notifyMode,
            pinned: event.pinned ?? _conversation.pinned,
            archived: event.archived ?? _conversation.archived,
          );
          if (event.event == 'chat.mute') {
            _muted = event.muted ?? _muted;
          }
        });
        return;
      }
      if (event.event == 'chat.draft' &&
          event.conversationId == widget.conversationId) {
        // Avoid fighting the local composer while the user is typing.
        if (_inputFocusNode.hasFocus) return;
        final cleared = event.draftCleared == true;
        final text = event.draftText ?? '';
        final replyId = event.draftReplyToMessageId;
        final empty = text.trim().isEmpty &&
            (replyId == null || replyId <= 0);
        if (cleared || empty) {
          if (_controller.text.isNotEmpty || _replyTo != null) {
            _controller.clear();
            setState(() {
              _replyTo = null;
              _pendingDraftReplyId = null;
            });
          }
          unawaited(ChatCacheService.clearDraft(widget.conversationId));
          return;
        }
        if (_controller.text != text) {
          _controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        }
        unawaited(
          ChatCacheService.saveDraft(
            widget.conversationId,
            text,
            replyToMessageId: replyId,
            updatedAt: DateTime.now(),
          ),
        );
        if (replyId != null && replyId > 0) {
          ChatMessage? target;
          for (final m in _messages) {
            if (m.id == replyId) {
              target = m;
              break;
            }
          }
          if (target != null) {
            if (_replyTo?.id != replyId) {
              setState(() => _replyTo = target);
            }
          } else {
            _pendingDraftReplyId = replyId;
          }
        } else if (_replyTo != null) {
          setState(() => _replyTo = null);
        }
        return;
      }
      if (event.event != 'user.presence') return;
      final peer = _conversation.peer;
      final uid = event.userId;
      final seen = event.lastSeenAt;
      if (peer == null || uid == null || seen == null || peer.id != uid) {
        return;
      }
      setState(() {
        _conversation = _conversation.copyWith(
          peer: peer.copyWith(lastSeenAt: seen),
        );
      });
    });
    _signalSub = ChatRealtimeSignals.instance.threadPoll.listen((_) {
      if (!_appPaused) _pollNew();
    });
    _apiReachabilityListener = () {
      if (!mounted) return;
      // Rebuild AppBar subtitle immediately (Telegram: «соединение…»).
      setState(() {});
      if (!ApiReachabilityService.instance.isApiReachable.value || _appPaused) {
        return;
      }
      _stream?.resumeFromBackground();
      unawaited(_pollNew());
      _onConnectionRestored();
    };
    ApiReachabilityService.instance.isApiReachable
        .addListener(_apiReachabilityListener!);
    _apiConnectingListener = () {
      if (mounted) setState(() {});
    };
    ApiReachabilityService.instance.isApiConnecting
        .addListener(_apiConnectingListener!);
    _deviceOnlineListener = () {
      if (mounted) setState(() {});
    };
    _deviceOnlineListenable = FeedSyncService.onlineListenable;
    _deviceOnlineListenable!.addListener(_deviceOnlineListener!);
    if (widget.conversationId > 0) {
      _stream = ChatStreamService(
      conversationId: widget.conversationId,
      onEvent: _onStreamEvent,
      onConnected: () {
        if (!mounted) return;
        setState(() {
          _sseConnected = true;
          _pollFailureCount = 0;
        });
        _restartPolling();
        unawaited(_pollNew());
        _onConnectionRestored();
        _scheduleMarkDelivered();
      },
      onDisconnected: () {
        if (!mounted) return;
        setState(() => _sseConnected = false);
        _restartPolling();
        unawaited(_pollNew());
      },
    )..connect();
    _refreshConversation();
    }
    _reconcileSlowModeCooldownWithConversation();
    if (kIsWeb) {
      registerWebPageVisibilityListener(
        _onWebTabVisible,
        onHidden: _onWebTabHidden,
      );
    }
  }

  @override
  void didUpdateWidget(covariant ChatThreadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.conversation.id != _conversation.id) {
      if (_conversation.id <= 0 && widget.conversation.id > 0) {
        _adoptResolvedConversation(widget.conversation);
      }
      return;
    }
    final next = widget.conversation;
    if (identical(next, _conversation)) return;
    final nextLooksStub = next.peer == null &&
        (next.title == null || next.title!.trim().isEmpty) &&
        next.memberCount == 0;
    final currentRicher = _conversation.peer != null ||
        (_conversation.title?.trim().isNotEmpty ?? false);
    if (nextLooksStub && currentRicher) return;
    setState(() {
      _conversation = next;
      _pinned = next.pinned;
      _muted = next.muted;
    });
    _reconcileSlowModeCooldownWithConversation();
  }

  void _adoptResolvedConversation(ChatConversation next) {
    _conversation = next;
    _pinned = next.pinned;
    _muted = next.muted;
    ActiveChatSession.instance.setOpen(next.id);
    unawaited(ChatThreadPrefetch.warm(next.id));
    _stream?.disconnect();
    _stream = ChatStreamService(
      conversationId: next.id,
      onEvent: _onStreamEvent,
      onConnected: () {
        if (!mounted) return;
        setState(() {
          _sseConnected = true;
          _pollFailureCount = 0;
        });
        _restartPolling();
        unawaited(_pollNew());
        _onConnectionRestored();
        _scheduleMarkDelivered();
      },
      onDisconnected: () {
        if (!mounted) return;
        setState(() => _sseConnected = false);
        _restartPolling();
        unawaited(_pollNew());
      },
    )..connect();
    unawaited(_loadCachedMessages().then((_) async {
      await _restoreFailedTextSends();
      await _restoreReadyOutbox();
      await _restoreMediaOutbox();
    }));
    _load(refresh: true);
    _refreshConversation();
    _kickTextOutbound();
    if (mounted) setState(() {});
  }

  void _onWebTabHidden() {
    if (!mounted) return;
    _appPaused = true;
    _stream?.pauseForBackground();
  }

  void _onWebTabVisible() {
    if (!mounted) return;
    _appPaused = false;
    HanEatHttpClient.recreateShared();
    unawaited(ApiReachabilityService.instance.warmUp(force: true));
    _stream?.resumeFromBackground();
    unawaited(_pollNew());
    _onConnectionRestored();
  }

  void _onConnectionRestored() {
    if (!mounted || _appPaused) return;
    // Re-queue failed text sends (like Telegram) instead of leaving them stuck.
    if (_failedTextSends.isNotEmpty) {
      final failed = _failedTextSends.values.toList(growable: false);
      _failedTextSends.clear();
      for (final pending in failed) {
        _clearFailedTextAutoRetry(pending.tempId);
        pending.attempts = 0;
        pending.lastRetryAfterSeconds = null;
        pending.lastLimitedAt = null;
        _textOutboundQueue.add(pending);
      }
      unawaited(_persistFailedTextSends());
      if (mounted) setState(() {});
    }
    if (_textOutboundQueue.isNotEmpty) {
      _kickTextOutbound();
    }
    if (_failedReadySends.isNotEmpty) {
      final failed = _failedReadySends.values.toList(growable: false);
      _failedReadySends.clear();
      for (final pending in failed) {
        pending.attempts = 0;
        _readyOutboundQueue.add(pending);
      }
      unawaited(_persistReadySends());
      if (mounted) setState(() {});
    }
    if (_readyOutboundQueue.isNotEmpty) {
      _kickReadyOutbound();
    }
    if (_mediaOutboundQueue.isNotEmpty) {
      unawaited(_drainMediaOutboundQueue());
    } else if (_pendingMediaRetry != null && _autoRetryOnLimitsEnabled) {
      unawaited(_retryPendingMedia());
    }
  }

  Future<void> _loadSlowModeUiPrefs() async {
    try {
      final hapticsEnabled =
          await ChatThreadUiPrefs.isSlowModeCountdownHapticsEnabled();
      final autoRetryEnabled =
          await ChatThreadUiPrefs.isAutoRetryOnLimitsEnabled();
      final customPath = await ChatThreadUiPrefs.getCustomWallpaperPath(
        widget.conversationId,
      );
      final cloudUrl = _conversation.wallpaperUrl?.trim();
      final cloudStyleId = _conversation.wallpaperStyle?.trim();
      // Cloud custom URL > local file cache > cloud style > local prefs.
      final ChatWallpaperStyle wallpaper;
      ImageProvider? customImage;
      String? resolvedCustomPath = customPath;

      if (cloudUrl != null && cloudUrl.isNotEmpty) {
        wallpaper = cloudStyleId != null && cloudStyleId.isNotEmpty
            ? ChatWallpaperStyle.fromId(cloudStyleId)
            : await ChatThreadUiPrefs.getWallpaperStyle(
                widget.conversationId,
              );
        final resolved = ServerConfig.resolveMediaUrl(cloudUrl);
        if (!kIsWeb &&
            customPath != null &&
            customPath.isNotEmpty &&
            await File(customPath).exists()) {
          customImage = FileImage(File(customPath));
        } else {
          customImage = CachedNetworkImageProvider(resolved);
          resolvedCustomPath = null;
        }
      } else if (customPath != null &&
          customPath.isNotEmpty &&
          !kIsWeb &&
          await File(customPath).exists()) {
        wallpaper = await ChatThreadUiPrefs.getWallpaperStyle(
          widget.conversationId,
        );
        customImage = FileImage(File(customPath));
      } else if (cloudStyleId != null && cloudStyleId.isNotEmpty) {
        wallpaper = ChatWallpaperStyle.fromId(cloudStyleId);
        resolvedCustomPath = null;
        unawaited(
          ChatThreadUiPrefs.setWallpaperStyle(
            widget.conversationId,
            wallpaper,
          ),
        );
      } else {
        wallpaper = await ChatThreadUiPrefs.getWallpaperStyle(
          widget.conversationId,
        );
        resolvedCustomPath = null;
      }
      final cloudAccent = _conversation.bubbleAccent?.trim();
      final bubbleAccent = ChatBubbleAccent.fromId(cloudAccent);
      if (!mounted) return;
      setState(() {
        _slowModeCountdownHapticsEnabled = hapticsEnabled;
        _autoRetryOnLimitsEnabled = autoRetryEnabled;
        _wallpaperStyle = wallpaper;
        _wallpaperCustomPath = resolvedCustomPath;
        _wallpaperImage = customImage;
        _bubbleAccent = bubbleAccent;
      });
      if (!autoRetryEnabled) {
        _clearAllAutoRetrySchedules();
      }
    } catch (_) {}
  }

  Future<void> _applyBubbleAccent(
    ChatBubbleAccent accent, {
    bool applyToAll = false,
  }) async {
    final previous = _bubbleAccent;
    setState(() {
      _bubbleAccent = accent;
      _conversation = accent == ChatBubbleAccent.defaultStyle
          ? _conversation.copyWith(clearBubbleAccent: true)
          : _conversation.copyWith(bubbleAccent: accent.id);
    });
    try {
      await ChatService.setBubbleAccent(
        conversationId: widget.conversationId,
        accent:
            accent == ChatBubbleAccent.defaultStyle ? null : accent.id,
        applyToAll: applyToAll,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _bubbleAccent = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _showBubbleAccentPicker() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Цвет пузырей',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final accent in ChatBubbleAccent.values)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: accent.swatchColor(isDark: isDark),
                  radius: 16,
                ),
                title: Text(accent.label),
                trailing: accent != ChatBubbleAccent.defaultStyle &&
                        !_hasFlexFeature('chat_wallpaper')
                    ? const Icon(Icons.lock_outline)
                    : _bubbleAccent == accent
                        ? const Icon(Icons.check)
                        : null,
                onTap: () => Navigator.pop(ctx, accent.id),
                onLongPress: () => Navigator.pop(ctx, 'all:${accent.id}'),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Долгое нажатие — применить ко всем чатам',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final pickedId = action.startsWith('all:') ? action.substring(4) : action;
    final picked = ChatBubbleAccent.fromId(pickedId);
    if (picked != ChatBubbleAccent.defaultStyle &&
        !_hasFlexFeature('chat_wallpaper')) {
      await showCreatorUpsell(context);
      return;
    }
    if (action.startsWith('all:')) {
      final id = action.substring(4);
      await _applyBubbleAccent(ChatBubbleAccent.fromId(id), applyToAll: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Цвет пузырей применён ко всем чатам')),
      );
      return;
    }
    await _applyBubbleAccent(ChatBubbleAccent.fromId(action));
  }

  Future<void> _applyWallpaperStyle(
    ChatWallpaperStyle style, {
    bool applyToAll = false,
  }) async {
    final previousStyle = _wallpaperStyle;
    final previousPath = _wallpaperCustomPath;
    final previousImage = _wallpaperImage;
    final previousConversation = _conversation;
    setState(() {
      _wallpaperStyle = style;
      _wallpaperCustomPath = null;
      _wallpaperImage = null;
      _conversation = _conversation.copyWith(
        wallpaperStyle: style.id,
        clearWallpaperUrl: true,
      );
    });
    try {
      if (applyToAll) {
        await ChatThreadUiPrefs.applyWallpaperToAll(style: style);
      } else {
        await ChatThreadUiPrefs.setWallpaperStyle(
          widget.conversationId,
          style,
        );
      }
      await ChatService.setWallpaperStyle(
        conversationId: widget.conversationId,
        style: style.id,
        setStyle: true,
        setUrl: false,
        applyToAll: applyToAll,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _wallpaperStyle = previousStyle;
        _wallpaperCustomPath = previousPath;
        _wallpaperImage = previousImage;
        _conversation = previousConversation;
      });
    }
  }

  Future<void> _pickCustomWallpaper({bool applyToAll = false}) async {
    final previousPath = _wallpaperCustomPath;
    final previousImage = _wallpaperImage;
    final previousConversation = _conversation;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked == null || !mounted) return;

      String? targetPath;
      ImageProvider? previewImage;
      if (!kIsWeb) {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return;
        final dir = await getApplicationDocumentsDirectory();
        final wallDir = Directory('${dir.path}/chat_wallpapers');
        if (!await wallDir.exists()) {
          await wallDir.create(recursive: true);
        }
        targetPath = applyToAll
            ? '${wallDir.path}/default.jpg'
            : '${wallDir.path}/c_${widget.conversationId}.jpg';
        final out = File(targetPath);
        await out.writeAsBytes(bytes, flush: true);
        previewImage = FileImage(out);
        setState(() {
          _wallpaperCustomPath = targetPath;
          _wallpaperImage = previewImage;
        });
      }

      final uploaded = await MediaUploadService.uploadMediaFile(
        file: picked,
        fileType: 'image',
      );
      final uploadedUrl = uploaded.url?.trim();
      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        throw StateError('upload_missing_url');
      }
      final url = ServerConfig.resolveMediaUrl(uploadedUrl);

      await ChatService.setWallpaperStyle(
        conversationId: widget.conversationId,
        wallpaperUrl: url,
        setStyle: false,
        setUrl: true,
        applyToAll: applyToAll,
      );

      if (!mounted) return;
      setState(() {
        _wallpaperCustomPath = targetPath;
        _wallpaperImage =
            previewImage ?? CachedNetworkImageProvider(url);
        _conversation = _conversation.copyWith(wallpaperUrl: url);
      });
      if (!kIsWeb && targetPath != null) {
        if (applyToAll) {
          await ChatThreadUiPrefs.applyWallpaperToAll(customPath: targetPath);
        } else {
          await ChatThreadUiPrefs.setCustomWallpaperPath(
            widget.conversationId,
            targetPath,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wallpaperCustomPath = previousPath;
        _wallpaperImage = previousImage;
        _conversation = previousConversation;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _toggleAutoTranslate() async {
    final enabled = !_conversation.autoTranslate;
    if (enabled && !_hasFlexFeature('auto_translate')) {
      await showCreatorUpsell(context);
      return;
    }
    final previous = _conversation;
    setState(() {
      _conversation = _conversation.copyWith(autoTranslate: enabled);
    });
    try {
      await ChatService.setAutoTranslate(
        conversationId: widget.conversationId,
        enabled: enabled,
      );
      if (enabled) unawaited(_runAutoTranslate());
      if (!enabled && mounted) {
        setState(() => _autoTranslations.clear());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _conversation = previous);
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _runAutoTranslate() async {
    if (!(_conversation.autoTranslate) || !_hasFlexFeature('auto_translate')) {
      return;
    }
    for (final msg in List<ChatMessage>.from(_messages)) {
      if (msg.isMine || msg.id <= 0 || msg.type != 'text') continue;
      if (_autoTranslations.containsKey(msg.id)) continue;
      final source = _translationSource(msg);
      if (source.isEmpty) continue;
      try {
        final translated = await ChatService.translateText(text: source);
        if (!mounted) return;
        if (translated.trim().isEmpty || translated.trim() == source) continue;
        setState(() => _autoTranslations[msg.id] = translated);
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _showWallpaperPicker() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Обои чата',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: const Text('Своё фото'),
                subtitle: const Text('Из галереи'),
                trailing: _hasFlexFeature('chat_wallpaper')
                    ? null
                    : const Icon(Icons.lock_outline),
                onTap: () => Navigator.pop(ctx, 'custom'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Своё фото для всех чатов'),
                trailing: _hasFlexFeature('chat_wallpaper')
                    ? null
                    : const Icon(Icons.lock_outline),
                onTap: () => Navigator.pop(ctx, 'custom_all'),
              ),
              const Divider(height: 1),
              for (final style in ChatWallpaperStyle.values)
                ListTile(
                  leading: SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ChatWallpaper(
                        isDark: isDark,
                        style: style,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  title: Text(style.label),
                  trailing: !_hasFlexFeature('chat_wallpaper') &&
                          style != ChatWallpaperStyle.pattern &&
                          style != ChatWallpaperStyle.solid
                      ? const Icon(Icons.lock_outline)
                      : _wallpaperImage == null && _wallpaperStyle == style
                          ? const Icon(Icons.check)
                          : null,
                  onTap: () => Navigator.pop(ctx, 'style:${style.id}'),
                  onLongPress: () =>
                      Navigator.pop(ctx, 'style_all:${style.id}'),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.select_all),
                title: const Text('Применить текущие ко всем'),
                subtitle: Text(
                  _wallpaperImage != null
                      ? 'Своё фото'
                      : _wallpaperStyle.label,
                ),
                onTap: () => Navigator.pop(ctx, 'apply_current_all'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Долгое нажатие на пресет — сделать обоями по умолчанию для всех чатов',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    final wantsCustom = action == 'custom' || action == 'custom_all';
    final styleId = action.startsWith('style:')
        ? action.substring(6)
        : action.startsWith('style_all:')
            ? action.substring(10)
            : null;
    final style = styleId == null ? null : ChatWallpaperStyle.fromId(styleId);
    final stylePremium = style != null &&
        style != ChatWallpaperStyle.pattern &&
        style != ChatWallpaperStyle.solid;
    if ((wantsCustom || stylePremium) && !_hasFlexFeature('chat_wallpaper')) {
      await showCreatorUpsell(context);
      return;
    }
    if (action == 'custom') {
      await _pickCustomWallpaper();
      return;
    }
    if (action == 'custom_all') {
      await _pickCustomWallpaper(applyToAll: true);
      return;
    }
    if (action == 'apply_current_all') {
      final cloudUrl = _conversation.wallpaperUrl?.trim();
      if (_wallpaperImage != null &&
          cloudUrl != null &&
          cloudUrl.isNotEmpty) {
        try {
          if (_wallpaperCustomPath != null) {
            await ChatThreadUiPrefs.applyWallpaperToAll(
              customPath: _wallpaperCustomPath,
            );
          }
          await ChatService.setWallpaperStyle(
            conversationId: widget.conversationId,
            wallpaperUrl: cloudUrl,
            setStyle: false,
            setUrl: true,
            applyToAll: true,
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userVisibleError(e))),
          );
          return;
        }
      } else if (_wallpaperCustomPath != null) {
        await ChatThreadUiPrefs.applyWallpaperToAll(
          customPath: _wallpaperCustomPath,
        );
      } else {
        await _applyWallpaperStyle(_wallpaperStyle, applyToAll: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Обои применены ко всем чатам')),
      );
      return;
    }
    if (action.startsWith('style_all:')) {
      final id = action.substring('style_all:'.length);
      await _applyWallpaperStyle(
        ChatWallpaperStyle.fromId(id),
        applyToAll: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Обои по умолчанию обновлены')),
      );
      return;
    }
    if (action.startsWith('style:')) {
      final id = action.substring('style:'.length);
      await _applyWallpaperStyle(ChatWallpaperStyle.fromId(id));
    }
  }

  Future<void> _showMessageReactors(ChatMessage msg, {String? emoji}) async {
    if (msg.id <= 0) return;
    await showChatMessageReactorsSheet(
      context,
      conversationId: widget.conversationId,
      messageId: msg.id,
      initialEmoji: emoji,
    );
  }

  Future<void> _toggleAutoRetryOnLimitsInThread(bool enabled) async {
    final previous = _autoRetryOnLimitsEnabled;
    if (previous == enabled) return;
    setState(() => _autoRetryOnLimitsEnabled = enabled);
    if (!enabled) {
      _clearAllAutoRetrySchedules();
    } else {
      _clearManualReadyRetrySchedule();
      _onConnectionRestored();
    }
    try {
      await ChatThreadUiPrefs.setAutoRetryOnLimitsEnabled(enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _autoRetryOnLimitsEnabled = previous);
      if (!previous) {
        _clearAllAutoRetrySchedules();
      }
    }
    // State is visible in the compact composer strip — no SnackBar.
  }

  void _clearAllAutoRetrySchedules() {
    _clearPendingMediaAutoRetry();
    final keys = _failedTextAutoRetryTimers.keys.toList(growable: false);
    for (final tempId in keys) {
      _clearFailedTextAutoRetry(tempId);
    }
  }

  bool get _slowModeEnabledForCurrentUser =>
      _conversation.isGroup &&
      !_conversation.amIGroupAdmin &&
      _conversation.slowModeSeconds > 0;

  int get _slowModeRemainingSeconds {
    if (!_slowModeEnabledForCurrentUser) return 0;
    final until = _slowModeLockUntil;
    if (until == null) return 0;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  int get _floodRemainingSeconds {
    final until = _floodLockUntil;
    if (until == null) return 0;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  int get _activeCooldownRemainingSeconds =>
      math.max(_slowModeRemainingSeconds, _floodRemainingSeconds);

  int get _pendingMediaAutoRetryRemainingSeconds {
    final until = _pendingMediaAutoRetryUntil;
    if (until == null) return 0;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  int get _manualReadyRetryRemainingSeconds {
    final until = _manualReadyRetryUntil;
    if (until == null) return 0;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  int _failedTextAutoRetryRemainingSeconds(int tempId) {
    final until = _failedTextAutoRetryUntil[tempId];
    if (until == null) return 0;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  int get _maxFailedTextAutoRetryRemainingSeconds {
    var maxSec = 0;
    for (final id in _failedTextAutoRetryUntil.keys) {
      maxSec = math.max(maxSec, _failedTextAutoRetryRemainingSeconds(id));
    }
    return maxSec;
  }

  int get _activeFailedTextAutoRetryCount {
    var count = 0;
    for (final id in _failedTextAutoRetryUntil.keys) {
      if (_failedTextAutoRetryRemainingSeconds(id) > 0) count++;
    }
    return count;
  }

  int get _activeFailedTextAutoRetrySlowCount {
    var count = 0;
    for (final entry in _failedTextAutoRetryReason.entries) {
      if (_failedTextAutoRetryRemainingSeconds(entry.key) > 0 &&
          entry.value == 'slow') {
        count++;
      }
    }
    return count;
  }

  int get _activeFailedTextAutoRetryFloodCount {
    var count = 0;
    for (final entry in _failedTextAutoRetryReason.entries) {
      if (_failedTextAutoRetryRemainingSeconds(entry.key) > 0 &&
          entry.value == 'flood') {
        count++;
      }
    }
    return count;
  }

  bool get _isAutoRetryActive =>
      _autoRetryOnLimitsEnabled &&
      (_pendingMediaAutoRetryRemainingSeconds > 0 ||
          _maxFailedTextAutoRetryRemainingSeconds > 0);

  int get _autoRetryRemainingSeconds => math.max(
        _pendingMediaAutoRetryRemainingSeconds,
        _maxFailedTextAutoRetryRemainingSeconds,
      );

  int get _autoRetryPendingCount =>
      (_pendingMediaAutoRetryRemainingSeconds > 0 ? 1 : 0) +
      _activeFailedTextAutoRetryCount;

  bool get _hasFailedPendingItems =>
      _pendingMediaRetry != null ||
      _failedTextSends.isNotEmpty ||
      _failedReadySends.isNotEmpty;

  int get _autoRetrySlowCount =>
      (_pendingMediaAutoRetryRemainingSeconds > 0 &&
              _pendingMediaAutoRetryReason == 'slow'
          ? 1
          : 0) +
      _activeFailedTextAutoRetrySlowCount;

  int get _autoRetryFloodCount =>
      (_pendingMediaAutoRetryRemainingSeconds > 0 &&
              _pendingMediaAutoRetryReason == 'flood'
          ? 1
          : 0) +
      _activeFailedTextAutoRetryFloodCount;

  IconData get _autoRetryReasonIcon =>
      _autoRetryFloodCount > _autoRetrySlowCount
          ? Icons.speed_outlined
          : Icons.timer_outlined;

  String get _autoRetryReasonLabel {
    if (_autoRetrySlowCount > 0 && _autoRetryFloodCount > 0) {
      return 'Slow mode и антифлуд';
    }
    if (_autoRetryFloodCount > 0) return 'Антифлуд';
    return 'Slow mode';
  }

  bool get _isAnyCooldownActive => _activeCooldownRemainingSeconds > 0;

  String _formatSlowModeCountdown(int seconds) {
    if (seconds <= 0) return '0с';
    if (seconds < 60) return '$secondsс';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (rest == 0) return '$minutesм';
    return '$minutesм $restс';
  }

  String _formatSlowModeCompact(int seconds) {
    if (seconds <= 0) return '0s';
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  void _syncSlowModeCountdownTimer() {
    final shouldRun = _isAnyCooldownActive ||
        _pendingMediaAutoRetryRemainingSeconds > 0 ||
        _maxFailedTextAutoRetryRemainingSeconds > 0 ||
        _manualReadyRetryRemainingSeconds > 0 ||
        (_nextManualRetryRemainingSeconds ?? 0) > 0;
    if (!shouldRun) {
      _slowModeCountdownTimer?.cancel();
      _slowModeCountdownTimer = null;
      _lastSlowModeTick = null;
      return;
    }
    if (_slowModeCountdownTimer != null) return;
    _lastSlowModeTick = _activeCooldownRemainingSeconds;
    _slowModeCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final manualRemaining = _nextManualRetryRemainingSeconds;
      if (shouldTriggerScheduledReadyRetryNow(
        hasSchedule: _manualReadyRetryUntil != null,
        nextRemainingSeconds: manualRemaining,
        sending: _sending,
        bulkRetryBusy: _retryAllBulkBusy,
      )) {
        _clearManualReadyRetrySchedule();
        unawaited(_retryReadyFailedPending());
        return;
      }
      final remaining = _activeCooldownRemainingSeconds;
      final previous = _lastSlowModeTick;
      if (previous != remaining) {
        if (_slowModeCountdownHapticsEnabled) {
          if (remaining > 0 && remaining <= 3) {
            unawaited(HapticFeedback.selectionClick());
          } else if (remaining == 0 && (previous ?? 1) > 0) {
            unawaited(HapticFeedback.lightImpact());
          }
        }
        _lastSlowModeTick = remaining;
      }
      if (!_isAnyCooldownActive &&
          _pendingMediaAutoRetryRemainingSeconds <= 0 &&
          _maxFailedTextAutoRetryRemainingSeconds <= 0 &&
          _manualReadyRetryRemainingSeconds <= 0 &&
          (_nextManualRetryRemainingSeconds ?? 0) <= 0) {
        _slowModeCountdownTimer?.cancel();
        _slowModeCountdownTimer = null;
        _lastSlowModeTick = null;
      }
      setState(() {});
    });
  }

  void _activateSlowModeCooldownFromNow() {
    if (!_slowModeEnabledForCurrentUser) return;
    _slowModeLockUntil =
        DateTime.now().add(Duration(seconds: _conversation.slowModeSeconds));
    _lastSlowModeTick = _activeCooldownRemainingSeconds;
    _syncSlowModeCountdownTimer();
  }

  void _activateSlowModeCooldownForSeconds(int seconds) {
    if (!_slowModeEnabledForCurrentUser) return;
    final safe = seconds <= 0 ? _conversation.slowModeSeconds : seconds;
    _slowModeLockUntil = DateTime.now().add(Duration(seconds: safe));
    _lastSlowModeTick = _activeCooldownRemainingSeconds;
    _syncSlowModeCountdownTimer();
  }

  void _activateFloodCooldownForSeconds(int seconds) {
    if (!_conversation.isGroup) return;
    final safe = seconds <= 0 ? 60 : seconds;
    _floodCooldownTotalSeconds = safe;
    _floodLockUntil = DateTime.now().add(Duration(seconds: safe));
    _lastSlowModeTick = _activeCooldownRemainingSeconds;
    _syncSlowModeCountdownTimer();
  }

  void _reconcileSlowModeCooldownWithConversation() {
    if (!_slowModeEnabledForCurrentUser) {
      _slowModeLockUntil = null;
    }
    _syncSlowModeCountdownTimer();
  }

  void _applyAutoDeleteSeconds(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    if (_conversation.autoDeleteSeconds == safe) {
      _syncAutoDeleteTicker();
      return;
    }
    setState(() {
      _conversation = _conversation.copyWith(autoDeleteSeconds: safe);
      _purgeExpiredAutoDeleteMessages(inSetState: true);
    });
    _syncAutoDeleteTicker();
  }

  void _purgeExpiredAutoDeleteMessages({bool inSetState = false}) {
    final ttl = _conversation.autoDeleteSeconds;
    if (ttl <= 0) return;
    final now = DateTime.now();
    final before = _messages.length;
    _messages.removeWhere(
      (m) => isMessageAutoDeleted(m.createdAt, ttl, now: now),
    );
    if (_messages.length == before) return;
    if (!inSetState && mounted) {
      setState(() {});
    }
  }

  void _syncAutoDeleteTicker() {
    final ttl = _conversation.autoDeleteSeconds;
    if (ttl <= 0) {
      _autoDeleteTicker?.cancel();
      _autoDeleteTicker = null;
      return;
    }
    if (_autoDeleteTicker != null) return;
    _autoDeleteTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _appPaused) return;
      if (_conversation.autoDeleteSeconds <= 0) {
        _autoDeleteTicker?.cancel();
        _autoDeleteTicker = null;
        return;
      }
      setState(() {
        _purgeExpiredAutoDeleteMessages(inSetState: true);
      });
    });
  }

  Future<void> _showPostingLimitsInfo({
    required bool floodCooldownActive,
    required int activeCooldownSeconds,
  }) async {
    if (!mounted) return;
    final slowModeOn = _conversation.slowModeSeconds > 0;
    final antiFloodOn = _conversation.antiFloodMaxMessagesPerMinute > 0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ограничения отправки'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (slowModeOn)
              Text(
                '• Slow mode: ${_formatSlowModeCountdown(_conversation.slowModeSeconds)} между сообщениями для обычных участников.',
              ),
            if (antiFloodOn) ...[
              if (slowModeOn) const SizedBox(height: 8),
              Text(
                '• Антифлуд: максимум ${_conversation.antiFloodMaxMessagesPerMinute} сообщений в минуту.',
              ),
            ],
            if (activeCooldownSeconds > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Сейчас активно: ${floodCooldownActive ? 'антифлуд' : 'slow mode'}. '
                'Отправка будет доступна через ${_formatSlowModeCountdown(activeCooldownSeconds)}.',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  bool _isRetryableSendError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('too many requests') ||
        s.contains('rate_limit') ||
        s.contains('429') ||
        s.contains('503') ||
        s.contains('504') ||
        s.contains('timeout') ||
        s.contains('network') ||
        s.contains('connection') ||
        s.contains('socket') ||
        s.contains('offline');
  }

  static const Duration _voiceUploadTimeout = Duration(seconds: 75);

  String _mediaStatusLabel(_PendingMediaSend pending) {
    return switch (pending.kind) {
      _PendingMediaKind.image => 'Загрузка фото…',
      _PendingMediaKind.video => 'Загрузка видео…',
      _PendingMediaKind.file => 'Загрузка файла…',
      _PendingMediaKind.voice => 'Загрузка голосового…',
    };
  }

  String _mediaUploadProgressLabel(
    _PendingMediaSend pending,
    double progress, {
    int? totalBytes,
  }) {
    final safeProgress = progress.clamp(0.0, 1.0).toDouble();
    if (totalBytes == null || totalBytes <= 0) {
      return _mediaStatusLabel(pending);
    }
    final sent = (totalBytes * safeProgress).round();
    final sentMb = sent / (1024 * 1024);
    final totalMb = totalBytes / (1024 * 1024);
    final noun = switch (pending.kind) {
      _PendingMediaKind.image => 'фото',
      _PendingMediaKind.video => 'видео',
      _PendingMediaKind.file => 'файла',
      _PendingMediaKind.voice => 'голосового',
    };
    return 'Загрузка $noun ${sentMb.toStringAsFixed(1)} / ${totalMb.toStringAsFixed(1)} МБ…';
  }

  int _newLocalTempId() =>
      -(DateTime.now().microsecondsSinceEpoch + math.Random().nextInt(999));

  bool _removeMediaFromQueue(String clientMessageId) {
    final index = _mediaOutboundQueue
        .indexWhere((p) => p.clientMessageId == clientMessageId);
    if (index < 0) return false;
    _mediaOutboundQueue.removeAt(index);
    return true;
  }

  void _enqueueMediaSend(_PendingMediaSend pending) {
    if (_mediaOutboundQueue
        .any((p) => p.clientMessageId == pending.clientMessageId)) {
      return;
    }
    final uid = AuthService.instance.currentUser?.id ?? 0;
    final optimistic = ChatMessage(
      id: pending.tempId,
      conversationId: widget.conversationId,
      senderId: uid,
      type: switch (pending.kind) {
        _PendingMediaKind.image => 'image',
        _PendingMediaKind.video => 'video',
        _PendingMediaKind.file => 'file',
        _PendingMediaKind.voice => 'voice',
      },
      content: switch (pending.kind) {
        _PendingMediaKind.file => pending.fileName ?? 'Файл',
        _PendingMediaKind.voice => '${pending.voiceDurationSec ?? 1}',
        _ => pending.caption,
      },
      createdAt: DateTime.now(),
      isMine: true,
      isRead: false,
      replyToMessageId: pending.replyToMessageId,
      mediaGroupId: pending.mediaGroupId,
      hasSpoiler: pending.hasSpoiler,
      isPaid: pending.isPaid,
      priceStars: pending.priceStars,
      purchased: true,
      clientMessageId: pending.clientMessageId,
    );
    setState(() {
      _pendingMediaByTempId[pending.tempId] = pending;
      _pendingMediaTempIdByClientId[pending.clientMessageId] = pending.tempId;
      _pendingMediaProgressByClientId[pending.clientMessageId] = 0.0;
      _messages.removeWhere((m) => m.id == pending.tempId);
      _messages.add(optimistic);
      _mediaOutboundQueue.add(pending);
    });
    unawaited(_persistMediaOutbox(pending, failed: false));
    _scrollToBottom();
    unawaited(_drainMediaOutboundQueue());
  }

  Future<void> _drainMediaOutboundQueue() async {
    if (_mediaDrainActive) return;
    _mediaDrainActive = true;
    try {
      while (_mediaOutboundQueue.isNotEmpty && mounted) {
        if (_conversation.isGroup && _isAnyCooldownActive) {
          final wait = _activeCooldownRemainingSeconds.clamp(1, 120);
          _setMediaComposerStatus(
            'Пауза ${_formatSlowModeCountdown(wait)}…',
          );
          await Future<void>.delayed(Duration(seconds: wait));
          if (!mounted) return;
          continue;
        }
        final pending = _mediaOutboundQueue.first;
        _setMediaComposerStatus(_mediaStatusLabel(pending));
        try {
          await _deliverMediaPending(pending);
          _removeMediaFromQueue(pending.clientMessageId);
          if (_pendingMediaRetry?.clientMessageId == pending.clientMessageId) {
            setState(() => _pendingMediaRetry = null);
          }
          if (_mediaOutboundQueue.isEmpty) {
            _clearMediaComposerProgress();
          } else if (mounted) {
            _setMediaComposerStatus(
              _mediaStatusLabel(_mediaOutboundQueue.first),
            );
          }
          _scrollToBottom();
        } catch (e) {
          if (e is _CancelledPendingMediaException) {
            _removeMediaFromQueue(pending.clientMessageId);
            if (_mediaOutboundQueue.isEmpty) {
              _clearMediaComposerProgress();
            }
            continue;
          }
          if (e is TimeoutException &&
              pending.kind == _PendingMediaKind.voice) {
            _removeMediaFromQueue(pending.clientMessageId);
            _clearMediaComposerProgress();
            pending.lastRetryAfterSeconds = null;
            pending.lastLimitedAt = null;
            _rememberFailedMedia(pending);
            if (mounted) {
              showErrorSnackBar(
                context,
                e,
                fallback:
                    'Загрузка голосового заняла слишком много времени. Проверьте сеть и нажмите «Повторить».',
              );
            }
            continue;
          }
          final err = e.toString().toLowerCase();
          if (err.contains('group_slow_mode')) {
            final retryAfter =
                e is ApiClientException ? e.retryAfterSeconds : null;
            pending.lastRetryAfterSeconds =
                (retryAfter ?? _conversation.slowModeSeconds).clamp(1, 3600);
            pending.lastLimitedAt = DateTime.now().toUtc();
            _removeMediaFromQueue(pending.clientMessageId);
            _clearMediaComposerProgress();
            _rememberFailedMedia(pending);
            if (mounted) {
              setState(() {
                _activateSlowModeCooldownForSeconds(retryAfter ?? 0);
              });
              _schedulePendingMediaAutoRetry(
                pending,
                retryAfterSeconds: retryAfter ?? _conversation.slowModeSeconds,
                reason: 'slow',
              );
              // Failed bubble + compact strip already explain retry state.
            }
            continue;
          }
          if (err.contains('group_flood_limited')) {
            final retryAfter =
                e is ApiClientException ? e.retryAfterSeconds : null;
            pending.lastRetryAfterSeconds = (retryAfter ?? 60).clamp(1, 3600);
            pending.lastLimitedAt = DateTime.now().toUtc();
            _removeMediaFromQueue(pending.clientMessageId);
            _clearMediaComposerProgress();
            _rememberFailedMedia(pending);
            if (mounted) {
              setState(() {
                _activateFloodCooldownForSeconds(retryAfter ?? 0);
              });
              _schedulePendingMediaAutoRetry(
                pending,
                retryAfterSeconds: retryAfter ?? 60,
                reason: 'flood',
              );
              // Failed bubble + compact strip already explain retry state.
            }
            continue;
          }
          pending.attempts++;
          final maxAttempts = pending.kind == _PendingMediaKind.voice ? 3 : 8;
          if (_isRetryableSendError(e) && pending.attempts < maxAttempts) {
            final waitSec = pending.kind == _PendingMediaKind.voice
                ? (pending.attempts * 2).clamp(2, 8)
                : (2 * pending.attempts).clamp(2, 45);
            if (mounted) {
              setState(() {
                _sendingStatus = 'Повтор через $waitSec с…';
              });
            }
            await Future<void>.delayed(Duration(seconds: waitSec));
            continue;
          }
          _removeMediaFromQueue(pending.clientMessageId);
          _clearMediaComposerProgress();
          pending.lastRetryAfterSeconds = null;
          pending.lastLimitedAt = null;
          _rememberFailedMedia(pending);
          if (mounted) {
            final fallback = switch (pending.kind) {
              _PendingMediaKind.image => 'Не удалось отправить фото',
              _PendingMediaKind.video => 'Не удалось отправить видео',
              _PendingMediaKind.file => 'Не удалось отправить файл',
              _PendingMediaKind.voice => 'Не удалось отправить голосовое',
            };
            if (isStarsRequiredError(e)) {
              await showStarsRequiredSnack(context, e, fallback: fallback);
            } else {
              showErrorSnackBar(context, e, fallback: fallback);
            }
          }
        }
      }
    } finally {
      _mediaDrainActive = false;
      if (mounted && _mediaOutboundQueue.isNotEmpty) {
        unawaited(_drainMediaOutboundQueue());
      }
    }
  }

  Future<void> _deliverMediaPending(_PendingMediaSend pending) async {
    _inFlightMediaClientIds.add(pending.clientMessageId);
    try {
      final reply = pending.replyToMessageId ?? _replyTo?.id;
      String? mediaUrl = pending.uploadedMediaUrl;
      if (mediaUrl == null) {
        final totalBytes = pending.totalBytes;
        final fileType = switch (pending.kind) {
          _PendingMediaKind.image => 'image',
          _PendingMediaKind.video => 'video',
          _PendingMediaKind.file => 'document',
          _PendingMediaKind.voice => 'audio',
        };
        final uploadFuture = MediaUploadService.uploadMediaFile(
          file: pending.file,
          fileType: fileType,
          clientUploadId: pending.clientMessageId,
          waitForProcessing: pending.kind != _PendingMediaKind.video,
          onProgress: (p) {
            if (!mounted) return;
            final clamped = p.clamp(0.0, 1.0).toDouble();
            setState(() {
              _pendingMediaProgressByClientId[pending.clientMessageId] =
                  clamped;
            });
            _setUploadProgress(
              clamped,
              status: _mediaUploadProgressLabel(
                pending,
                clamped,
                totalBytes: totalBytes,
              ),
            );
          },
        );
        final uploaded = pending.kind == _PendingMediaKind.voice
            ? await uploadFuture.timeout(_voiceUploadTimeout)
            : await uploadFuture;
        if (_cancelledPendingMediaClientIds.contains(pending.clientMessageId)) {
          throw _CancelledPendingMediaException();
        }
        final url = uploaded.url;
        if (url == null || url.isEmpty) throw Exception('Нет URL файла');
        mediaUrl = pending.kind == _PendingMediaKind.voice
            ? ServerConfig.resolveVoiceMediaUrl(url)
            : ServerConfig.resolveMediaUrl(url);
        pending.uploadedMediaUrl = mediaUrl;
      }
      if (_cancelledPendingMediaClientIds.contains(pending.clientMessageId)) {
        throw _CancelledPendingMediaException();
      }
      _setUploadProgress(1, status: 'Отправка…');
      final ChatMessage msg;
      switch (pending.kind) {
        case _PendingMediaKind.image:
          msg = await ChatService.sendImage(
            conversationId: widget.conversationId,
            mediaUrl: mediaUrl,
            caption: pending.caption,
            replyToMessageId: reply,
            clientMessageId: pending.clientMessageId,
            silent: pending.silent,
            mediaGroupId: pending.mediaGroupId,
            hasSpoiler: pending.hasSpoiler,
            isPaid: pending.isPaid,
            priceStars: pending.priceStars,
            topicId: pending.topicId,
            anonymous: pending.anonymous,
          );
          if (_chatIsGifMediaUrl(mediaUrl)) {
            unawaited(ChatRecentGifsStore.remember(mediaUrl));
          }
        case _PendingMediaKind.video:
          msg = await ChatService.sendVideo(
            conversationId: widget.conversationId,
            mediaUrl: mediaUrl,
            caption: pending.caption,
            replyToMessageId: reply,
            clientMessageId: pending.clientMessageId,
            silent: pending.silent,
            mediaGroupId: pending.mediaGroupId,
            hasSpoiler: pending.hasSpoiler,
            isPaid: pending.isPaid,
            priceStars: pending.priceStars,
            topicId: pending.topicId,
            anonymous: pending.anonymous,
          );
        case _PendingMediaKind.file:
          msg = await ChatService.sendFile(
            conversationId: widget.conversationId,
            mediaUrl: mediaUrl,
            fileName: pending.fileName ?? 'file',
            replyToMessageId: reply,
            clientMessageId: pending.clientMessageId,
            silent: pending.silent,
            isPaid: pending.isPaid,
            priceStars: pending.priceStars,
            topicId: pending.topicId,
            anonymous: pending.anonymous,
          );
        case _PendingMediaKind.voice:
          msg = await ChatService.sendVoice(
            conversationId: widget.conversationId,
            mediaUrl: mediaUrl,
            durationSec: pending.voiceDurationSec ?? 1,
            replyToMessageId: reply,
            clientMessageId: pending.clientMessageId,
            silent: pending.silent,
            topicId: pending.topicId,
            anonymous: pending.anonymous,
          );
      }
      if (_cancelledPendingMediaClientIds.contains(pending.clientMessageId)) {
        throw _CancelledPendingMediaException();
      }
      _rememberOutgoingForHub(msg, refreshHub: true);
      if (!mounted) return;
      setState(() {
        _integrateMessage(msg, removeTempId: pending.tempId);
        _replyTo = null;
      });
      unawaited(_removeMediaOutbox(pending.clientMessageId));
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
      if (pending.kind == _PendingMediaKind.file &&
          pending.fileName != null &&
          pending.uploadedMediaUrl != null) {
        unawaited(_rememberRecentFile(
          name: pending.fileName!,
          file: pending.file,
          mediaUrl: pending.uploadedMediaUrl!,
        ));
      }
    } finally {
      _inFlightMediaClientIds.remove(pending.clientMessageId);
    }
  }

  int? _lastServerMessageId() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final id = _messages[i].id;
      if (id > 0) return id;
    }
    return null;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval = _sseConnected
        ? const Duration(seconds: 8)
        : const Duration(seconds: 2);
    if (!_appPaused) {
      unawaited(_pollNew());
    }
    _pollTimer = Timer.periodic(interval, (_) {
      if (!_appPaused) _pollNew();
    });
  }

  Future<void> _loadCachedMessages() async {
    final cached = await ChatCacheService.loadThread(widget.conversationId);
    if (cached == null || cached.isEmpty || !mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(cached);
      _loading = false;
    });
    _tryRestorePendingDraftReply();
  }

  Future<void> _restoreFailedTextSends() async {
    final rows =
        await ChatCacheService.loadFailedTextSends(widget.conversationId);
    if (rows.isEmpty || !mounted) return;
    final uid = AuthService.instance.currentUser?.id ?? 0;
    final restoredFailed = <int, _PendingTextSend>{};
    final restoredQueued = <_PendingTextSend>[];
    final restoredMessages = <ChatMessage>[];
    final knownClientIds = {
      for (final pending in _textOutboundQueue) pending.clientMessageId,
      for (final pending in _failedTextSends.values) pending.clientMessageId,
    };
    for (final row in rows) {
      final text = row['text'] as String? ?? '';
      final clientMessageId = row['client_message_id'] as String? ?? '';
      final tempId = row['temp_id'] as int? ?? 0;
      if (text.trim().isEmpty || clientMessageId.isEmpty || tempId >= 0) {
        continue;
      }
      if (knownClientIds.contains(clientMessageId)) continue;
      final replyRaw = row['reply_to_message_id'];
      final topicRaw = row['topic_id'];
      final pending = _PendingTextSend(
        text: text,
        clientMessageId: clientMessageId,
        tempId: tempId,
        replyToMessageId: replyRaw is int ? replyRaw : null,
        silent: row['silent'] == true,
        disableWebpagePreview: row['disable_webpage_preview'] == true,
        effectId: row['effect_id'] as String?,
        topicId: topicRaw is int ? topicRaw : null,
        anonymous: row['anonymous'] == true,
      );
      pending.attempts = row['attempts'] as int? ?? 0;
      pending.lastRetryAfterSeconds =
          (row['last_retry_after_seconds'] as int?)?.clamp(1, 3600);
      pending.lastLimitedAt = DateTime.tryParse(
        row['last_limited_at'] as String? ?? '',
      );
      if (row['queued'] == true) {
        restoredQueued.add(pending);
      } else {
        restoredFailed[tempId] = pending;
      }
      knownClientIds.add(clientMessageId);
      if (!_messages.any((m) =>
          m.id == tempId ||
          ((m.clientMessageId ?? '').isNotEmpty &&
              m.clientMessageId == clientMessageId))) {
        restoredMessages.add(
          ChatMessage(
            id: tempId,
            conversationId: widget.conversationId,
            senderId: uid,
            type: 'text',
            content: text,
            replyToMessageId: pending.replyToMessageId,
            createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
            isMine: true,
            isRead: false,
            clientMessageId: clientMessageId,
            topicId: pending.topicId,
            isAnonymous: pending.anonymous,
          ),
        );
      }
    }
    if (restoredFailed.isEmpty && restoredQueued.isEmpty) return;
    setState(() {
      _failedTextSends.addAll(restoredFailed);
      _textOutboundQueue.addAll(restoredQueued);
      _messages.addAll(restoredMessages);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    _syncSlowModeCountdownTimer();
    if (restoredQueued.isNotEmpty) {
      _kickTextOutbound();
    }
  }

  Map<String, dynamic> _pendingTextToJson(
    _PendingTextSend pending, {
    required bool queued,
  }) {
    return {
      'text': pending.text,
      'client_message_id': pending.clientMessageId,
      'temp_id': pending.tempId,
      'reply_to_message_id': pending.replyToMessageId,
      'attempts': pending.attempts,
      'last_retry_after_seconds': pending.lastRetryAfterSeconds,
      'last_limited_at': pending.lastLimitedAt?.toUtc().toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'queued': queued,
      'silent': pending.silent,
      'disable_webpage_preview': pending.disableWebpagePreview,
      if (pending.effectId != null) 'effect_id': pending.effectId,
      if (pending.topicId != null) 'topic_id': pending.topicId,
      'anonymous': pending.anonymous,
    };
  }

  Future<void> _persistFailedTextSends() {
    final seen = <String>{};
    final items = <Map<String, dynamic>>[];
    for (final pending in _textOutboundQueue) {
      if (!seen.add(pending.clientMessageId)) continue;
      items.add(_pendingTextToJson(pending, queued: true));
    }
    for (final pending in _failedTextSends.values) {
      if (!seen.add(pending.clientMessageId)) continue;
      items.add(_pendingTextToJson(pending, queued: false));
    }
    return ChatCacheService.saveFailedTextSends(
      widget.conversationId,
      items,
    );
  }

  void _rememberOutgoingForHub(ChatMessage msg, {bool refreshHub = false}) {
    unawaited(
      ChatCacheService.patchConversationLastMessage(
        conversationId: widget.conversationId,
        lastMessage: msg,
      ),
    );
    if (!refreshHub) return;
    ChatRealtimeSignals.instance.notifyNewMessage();
    try {
      ProviderScope.containerOf(context)
          .read(chatsHubRefreshProvider.notifier)
          .state++;
    } catch (_) {}
  }

  Future<void> _persistReadySends() {
    final seen = <String>{};
    final items = <Map<String, dynamic>>[];
    for (final pending in _readyOutboundQueue) {
      if (!seen.add(pending.clientMessageId)) continue;
      items.add({...pending.toJson(), 'queued': true});
    }
    for (final pending in _failedReadySends.values) {
      if (!seen.add(pending.clientMessageId)) continue;
      items.add({...pending.toJson(), 'queued': false});
    }
    return ChatCacheService.saveReadyOutbox(widget.conversationId, items);
  }

  Future<void> _restoreReadyOutbox() async {
    final rows = await ChatCacheService.loadReadyOutbox(widget.conversationId);
    if (rows.isEmpty || !mounted) return;
    final uid = AuthService.instance.currentUser?.id ?? 0;
    final queued = <ChatReadyOutgoing>[];
    final failed = <int, ChatReadyOutgoing>{};
    final bubbles = <ChatMessage>[];
    final known = {
      for (final pending in _readyOutboundQueue) pending.clientMessageId,
      for (final pending in _failedReadySends.values) pending.clientMessageId,
    };
    for (final row in rows) {
      final pending = ChatReadyOutgoing.fromJson(row);
      if (pending.clientMessageId.isEmpty || pending.tempId >= 0) continue;
      if (known.contains(pending.clientMessageId)) continue;
      known.add(pending.clientMessageId);
      if (row['queued'] == true) {
        queued.add(pending);
      } else {
        failed[pending.tempId] = pending;
      }
      if (!_messages.any((m) =>
          m.id == pending.tempId ||
          ((m.clientMessageId ?? '').isNotEmpty &&
              m.clientMessageId == pending.clientMessageId))) {
        bubbles.add(
          ChatMessage(
            id: pending.tempId,
            conversationId: widget.conversationId,
            senderId: uid,
            type: pending.type,
            content: pending.content,
            mediaUrl: pending.mediaUrl,
            createdAt: DateTime.now(),
            isMine: true,
            replyToMessageId: pending.replyToMessageId,
            topicId: pending.topicId,
            isAnonymous: pending.anonymous,
            clientMessageId: pending.clientMessageId,
          ),
        );
      }
    }
    if (queued.isEmpty && failed.isEmpty) return;
    setState(() {
      _readyOutboundQueue.addAll(queued);
      _failedReadySends.addAll(failed);
      _messages.addAll(bubbles);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    if (queued.isNotEmpty) _kickReadyOutbound();
  }

  void _enqueueReadyOutgoing(ChatReadyOutgoing pending) {
    final uid = AuthService.instance.currentUser?.id ?? 0;
    final optimistic = ChatMessage(
      id: pending.tempId,
      conversationId: widget.conversationId,
      senderId: uid,
      type: pending.type,
      content: pending.content,
      mediaUrl: pending.mediaUrl,
      createdAt: DateTime.now(),
      isMine: true,
      replyToMessageId: pending.replyToMessageId,
      topicId: pending.topicId,
      isAnonymous: pending.anonymous,
      clientMessageId: pending.clientMessageId,
    );
    setState(() {
      _messages.add(optimistic);
      _replyTo = null;
      _readyOutboundQueue.add(pending);
    });
    unawaited(_persistReadySends());
    unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    _rememberOutgoingForHub(optimistic);
    _scrollToBottom();
    AppHaptics.selection();
    _kickReadyOutbound();
  }

  void _kickReadyOutbound() {
    for (final pending in List<ChatReadyOutgoing>.from(_readyOutboundQueue)) {
      if (_inFlightReadyClientIds.contains(pending.clientMessageId)) continue;
      unawaited(_flushReadyOutgoing(pending));
    }
  }

  Future<void> _retryFailedReady(int tempId) async {
    final pending = _failedReadySends.remove(tempId);
    if (pending == null) return;
    pending.attempts = 0;
    setState(() => _readyOutboundQueue.add(pending));
    unawaited(_persistReadySends());
    _kickReadyOutbound();
  }

  Future<void> _flushReadyOutgoing(ChatReadyOutgoing pending) async {
    if (_inFlightReadyClientIds.contains(pending.clientMessageId)) return;
    _inFlightReadyClientIds.add(pending.clientMessageId);
    try {
      while (true) {
        try {
          final msg = await sendChatReadyOutgoing(
            conversationId: widget.conversationId,
            pending: pending,
          );
          _readyOutboundQueue.removeWhere(
            (p) => p.clientMessageId == pending.clientMessageId,
          );
          _failedReadySends.remove(pending.tempId);
          unawaited(_persistReadySends());
          _rememberOutgoingForHub(msg, refreshHub: true);
          if (pending.type == 'live_location' && msg.id > 0) {
            final parsed = ChatLocationPayload.tryParse(msg.content);
            final expires = parsed?.expiresAt;
            if (expires != null) {
              LiveLocationSession.start(
                conversationId: widget.conversationId,
                messageId: msg.id,
                expiresAt: expires,
              );
            }
          }
          if (!mounted) return;
          setState(() {
            _integrateMessage(msg, removeTempId: pending.tempId);
          });
          _scrollToBottom();
          unawaited(
            ChatCacheService.saveThread(widget.conversationId, _messages),
          );
          return;
        } catch (e) {
          pending.attempts++;
          if (_isRetryableSendError(e) && pending.attempts < 3) {
            await Future<void>.delayed(
              Duration(milliseconds: pending.attempts == 1 ? 200 : 500),
            );
            continue;
          }
          _readyOutboundQueue.removeWhere(
            (p) => p.clientMessageId == pending.clientMessageId,
          );
          _failedReadySends[pending.tempId] = pending;
          unawaited(_persistReadySends());
          if (!mounted) return;
          setState(() {});
          if (offerFlexIfRequired(context, e)) return;
          if (offerPackStoreIfRequired(context, e)) return;
          showErrorSnackBar(context, e);
          return;
        }
      }
    } finally {
      _inFlightReadyClientIds.remove(pending.clientMessageId);
    }
  }

  void _restartPolling() {
    if (!mounted) return;
    _startPolling();
  }

  void _onInputChanged() {
    if (!mounted) return;
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    _scheduleDraftSave();
    _scheduleComposerLinkPreview();

    // === Live Inline Mode (@bot) ===
    _scheduleInlineSuggestions();

    // === Autocomplete @bots + @group members ===
    _scheduleBotAutocomplete();

    if (!has) {
      _hideInlineOverlay();
      _hideBotAutocompleteOverlay();
      return;
    }

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 800), () {
      ChatService.sendTyping(conversationId: widget.conversationId);
    });
  }

  void _scheduleComposerLinkPreview() {
    _composerLinkDebounce?.cancel();
    _composerLinkDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final url = extractFirstHttpUrl(_controller.text);
      if (url == null) {
        if (_composerLinkPreviewUrl != null ||
            _composerLinkPreviewDismissedUrl != null) {
          setState(() {
            _composerLinkPreviewUrl = null;
            _composerLinkPreviewDismissedUrl = null;
          });
        }
        return;
      }
      if (url == _composerLinkPreviewDismissedUrl) return;
      if (url == _composerLinkPreviewUrl) return;
      setState(() => _composerLinkPreviewUrl = url);
    });
  }

  void _scheduleInlineSuggestions() {
    _inlineDebounce?.cancel();

    final text = _controller.text.trim();
    if (!text.startsWith('@')) {
      _hideInlineOverlay();
      return;
    }

    // Извлекаем @botname и query
    final match = RegExp(r'^@([a-zA-Z0-9_]+)\s*(.*)$').firstMatch(text);
    if (match == null) {
      _hideInlineOverlay();
      return;
    }

    final botUsername = match.group(1)!;
    final query = match.group(2) ?? '';

    _inlineDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final results = await BotInlineService.getInlineResults(
        botUsername: botUsername,
        query: query,
        limit: 6,
      );
      if (!mounted) return;

      if (results.isNotEmpty) {
        _showInlineOverlay(results);
      } else {
        _hideInlineOverlay();
      }
    });
  }

  Future<void> _ensureGroupMembersForMentions() async {
    if (!_conversation.isGroup || _groupMembers.isNotEmpty) return;
    try {
      final members = await ChatService.listMembers(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _groupMembers = members;
        _senderNames = {for (final m in members) m.id: m.displayName};
      });
      _scheduleBotAutocomplete();
    } catch (_) {}
  }

  bool get _hasBotCommands => _botCommands.isNotEmpty;

  Future<void> _loadBotCommands() async {
    try {
      final cmds = await ChatService.listConversationBotCommands(
        conversationId: widget.conversationId,
      );
      if (!mounted) return;
      setState(() => _botCommands = cmds);
    } catch (_) {
      if (!mounted) return;
      if (_botCommands.isNotEmpty) setState(() => _botCommands = []);
    }
  }

  void _scheduleBotAutocomplete() {
    final text = _controller.text;

    // Slash-commands for chat bots: `/start`
    final slash = RegExp(r'(?:^|\s)/([a-zA-Z0-9_]*)$').firstMatch(text);
    if (slash != null && _botCommands.isNotEmpty) {
      final query = slash.group(1)!.toLowerCase();
      final filtered = _botCommands
          .where((c) {
            final cmd = c.command.toLowerCase();
            final desc = c.description.toLowerCase();
            if (query.isEmpty) return true;
            return cmd.startsWith(query) || desc.contains(query);
          })
          .take(10)
          .map(
            (c) => _MentionCandidate(
              username: c.command,
              title: '/${c.command}',
              subtitle: c.description.isEmpty ? null : c.description,
              avatarUrl: null,
              isBot: true,
              isSlashCommand: true,
            ),
          )
          .toList();
      if (filtered.isEmpty) {
        _hideBotAutocompleteOverlay();
        return;
      }
      _showBotAutocompleteOverlay(filtered);
      return;
    }

    // Ищем @query в конце строки (ASCII username или имя/кириллица).
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(text);
    if (match == null) {
      _hideBotAutocompleteOverlay();
      return;
    }

    if (_conversation.isGroup && _groupMembers.isEmpty) {
      unawaited(_ensureGroupMembersForMentions());
    }

    final query = match.group(1)!.toLowerCase();
    final myId = AuthService.instance.currentUser?.id;
    final candidates = <_MentionCandidate>[];

    // Group members: @username or @id{userId} when no username (by display name).
    if (_conversation.isGroup) {
      const specials = <(String, String, String)>[
        ('all', '@all', 'Все участники'),
        ('admin', '@admin', 'Администраторы'),
      ];
      for (final s in specials) {
        if (query.isEmpty ||
            s.$1.startsWith(query) ||
            s.$2.toLowerCase().contains(query)) {
          candidates.add(
            _MentionCandidate(
              username: s.$1,
              title: s.$2,
              subtitle: s.$3,
              avatarUrl: null,
              isBot: false,
            ),
          );
        }
      }
      for (final m in _groupMembers) {
        if (myId != null && m.id == myId) continue;
        final u = m.username?.trim();
        final handle = (u != null && u.isNotEmpty)
            ? (u.startsWith('@') ? u.substring(1) : u)
            : 'id${m.id}';
        if (handle.isEmpty) continue;
        final display = m.displayName;
        if (query.isNotEmpty &&
            !handle.toLowerCase().contains(query) &&
            !display.toLowerCase().contains(query) &&
            !(m.name?.toLowerCase().contains(query) ?? false)) {
          continue;
        }
        final hasUsername = u != null && u.isNotEmpty;
        candidates.add(
          _MentionCandidate(
            username: handle,
            title: hasUsername ? '@$handle' : display,
            subtitle: hasUsername ? display : 'Упоминание по имени',
            avatarUrl: m.avatarUrl,
            isBot: false,
          ),
        );
      }
    }

    for (final b in _myBots) {
      if (query.isNotEmpty && !b.username.toLowerCase().contains(query)) {
        continue;
      }
      candidates.add(
        _MentionCandidate(
          username: b.username,
          title: '@${b.username}',
          subtitle: b.name.isNotEmpty ? b.name : null,
          avatarUrl: b.avatarUrl,
          isBot: true,
        ),
      );
    }

    // Prefer people, then bots; cap list.
    candidates.sort((a, b) {
      if (a.isBot != b.isBot) return a.isBot ? 1 : -1;
      return a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });
    final filtered = candidates.take(8).toList();

    if (filtered.isEmpty) {
      _hideBotAutocompleteOverlay();
      return;
    }

    _showBotAutocompleteOverlay(filtered);
  }

  void _showBotAutocompleteOverlay(List<_MentionCandidate> items) {
    _botAutocompleteOverlayEntry?.remove();

    _botAutocompleteOverlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 16,
        right: 16,
        bottom: 90,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: item.avatarUrl != null
                        ? CachedNetworkImageProvider(item.avatarUrl!)
                        : null,
                    child: item.avatarUrl == null
                        ? Icon(
                            item.isBot
                                ? Icons.smart_toy_outlined
                                : Icons.person_outline,
                          )
                        : null,
                  ),
                  title: HighlightedText(
                    text: item.title,
                    style: Theme.of(context).textTheme.bodyLarge ??
                        const TextStyle(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: item.subtitle != null
                      ? HighlightedText(
                          text: item.subtitle!,
                          style: Theme.of(context).textTheme.bodySmall ??
                              const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () {
                    if (item.isSlashCommand) {
                      _insertBotCommand(item.username);
                    } else {
                      _insertBotMention(item.username);
                    }
                    _hideBotAutocompleteOverlay();
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true)
        .insert(_botAutocompleteOverlayEntry!);
  }

  void _hideBotAutocompleteOverlay() {
    _botAutocompleteOverlayEntry?.remove();
    _botAutocompleteOverlayEntry = null;
  }

  /// Вставляет @username / @idN в поле ввода, заменяя текущий @query
  void _insertBotMention(String username) {
    final text = _controller.text;
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(text);
    if (match == null) return;

    final start = match.start + (text[match.start] == ' ' ? 1 : 0);
    final newText = '${text.substring(0, start)}@$username ';

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  void _insertBotCommand(String command) {
    final clean = command.startsWith('/') ? command.substring(1) : command;
    final text = _controller.text;
    final match = RegExp(r'(?:^|\s)/([a-zA-Z0-9_]*)$').firstMatch(text);
    if (match == null) {
      final newText = '/$clean';
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      return;
    }
    final start = match.start + (text[match.start] == ' ' ? 1 : 0);
    final newText = '${text.substring(0, start)}/$clean';
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  void _insertComposerToken(String token) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start.clamp(0, text.length) : text.length;
    final end = sel.isValid ? sel.end.clamp(0, text.length) : text.length;
    final insertion = start > 0 && text[start - 1] != ' ' && text[start - 1] != '\n'
        ? ' $token '
        : '$token ';
    final newText = text.replaceRange(start, end, insertion);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    _inputFocusNode.requestFocus();
  }

  void _wrapComposerMarkup(String left, String right) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    final hasSelection = sel.isValid && !sel.isCollapsed && end > start;
    final selected = hasSelection ? text.substring(start, end) : '';
    final inner = selected.isEmpty ? '' : selected;
    final insertion = '$left$inner$right';
    final newText = text.replaceRange(start, end, insertion);
    final cursorStart = start + left.length;
    final cursorEnd = cursorStart + inner.length;
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: cursorStart,
        extentOffset: cursorEnd,
      ),
    );
    _inputFocusNode.requestFocus();
  }

  void _openBotCommandsMenu() {
    if (_botCommands.isEmpty) {
      unawaited(_loadBotCommands());
    }
    if (_controller.text.trim().isEmpty) {
      _controller.value = const TextEditingValue(
        text: '/',
        selection: TextSelection.collapsed(offset: 1),
      );
    } else if (!RegExp(r'(?:^|\s)/[a-zA-Z0-9_]*$').hasMatch(_controller.text)) {
      final t = _controller.text;
      final needsSpace = t.isNotEmpty && !t.endsWith(' ') && !t.endsWith('\n');
      final newText = '$t${needsSpace ? ' ' : ''}/';
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
    _inputFocusNode.requestFocus();
    _scheduleBotAutocomplete();
  }

  void _showInlineOverlay(List<InlineResult> results) {
    _inlineResults = results;
    _inlineOverlayEntry?.remove();

    _inlineOverlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 16,
        right: 16,
        bottom: 90, // над полем ввода
        child: InlineSuggestions(
          results: _inlineResults,
          onSelect: _insertInlineResult,
          maxHeight: 200,
        ),
      ),
    );

    Overlay.of(context).insert(_inlineOverlayEntry!);
  }

  void _hideInlineOverlay() {
    _inlineOverlayEntry?.remove();
    _inlineOverlayEntry = null;
    _inlineResults = [];
  }

  void _insertInlineResult(InlineResult result) {
    _hideInlineOverlay();
    if (result.type == 'miniapp') {
      unawaited(_openMiniAppFromInline(result));
      return;
    }
    // Как в Telegram: выбор inline-результата сразу отправляет payload.
    final payload = result.payload.trim();
    if (payload.isEmpty) return;
    _controller.text = payload;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    unawaited(_sendText());
  }

  Future<void> _openMiniAppFromInline(InlineResult result) async {
    final miniAppId = result.miniAppId;
    if (miniAppId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mini app недоступен для запуска')),
      );
      return;
    }
    try {
      final launch = await MiniAppsService.getLaunchContext(
        miniAppId,
        conversationId: widget.conversationId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MiniAppWebViewScreen(
            title: result.title,
            subtitle: result.description,
            url: launch.url,
            initData: launch.initData,
            initDataUnsafe: launch.initDataUnsafe,
            miniAppId: miniAppId,
            conversationId: widget.conversationId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть mini app: $e')),
      );
    }
  }

  void _onStreamEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type']?.toString();
    if (type == 'message.new') {
      final raw = event['message'];
      if (raw is! Map<String, dynamic>) return;
      try {
        final msg = ChatService.messageFromStreamPayload(raw);
        setState(() {
          _integrateMessage(msg);
          if (!msg.isMine) {
            _clearTypingState();
            if (msg.replyKeyboard != null) {
              _applyReplyKeyboard(msg.replyKeyboard);
            }
          }
        });
        if ((msg.effectId ?? '').isNotEmpty) {
          _playMessageEffect(msg.effectId, messageId: msg.id);
        }
        // Delivered as soon as the client receives the message (Telegram).
        if (!msg.isMine) {
          _scheduleMarkDelivered();
        }
        // Same as poll path: only auto-scroll/mark-read when near bottom.
        if (_isNearBottom()) {
          _scrollToBottom();
          _scheduleMarkRead();
        } else if (!msg.isMine) {
          setState(() {
            _newMessagesBelow += 1;
            _showJumpToBottom = true;
          });
        }
      } catch (e) {
        debugPrint('Chat SSE message parse failed: $e');
      }
      return;
    }
    if (type == 'message.deleted') {
      final id = event['message_id'];
      final messageId = id is int ? id : int.tryParse('$id');
      if (messageId == null) return;
      setState(() {
        _messages.removeWhere((m) => m.id == messageId);
        _removePinnedMessageId(messageId);
      });
      return;
    }
    if (type == 'conversation.auto_delete') {
      final raw = event['auto_delete_seconds'];
      final seconds = raw is int ? raw : int.tryParse('$raw');
      if (seconds == null) return;
      _applyAutoDeleteSeconds(seconds);
      return;
    }
    if (type == 'conversation.history_cleared') {
      final alsoForPeer = event['also_for_peer'] == true;
      final rawUid = event['user_id'];
      final uid = rawUid is int ? rawUid : int.tryParse('$rawUid');
      final myId = AuthService.instance.currentUser?.id;
      if (alsoForPeer || (uid != null && uid == myId)) {
        _applyHistoryClearedLocally();
      }
      return;
    }
    if (type == 'typing') {
      final rawUid = event['user_id'];
      final uid = rawUid is int ? rawUid : int.tryParse('$rawUid');
      final activity = event['activity'] == 'recording' ? 'recording' : 'typing';
      _onPeerTyping(uid, activity: activity);
      return;
    }
    if (type == 'message.delivered') {
      final delivererId = event['user_id'];
      final myId = AuthService.instance.currentUser?.id;
      if (delivererId == myId) return;
      final raw = event['last_delivered_message_id'];
      final deliveredId = raw is int ? raw : int.tryParse('$raw');
      if (deliveredId != null) _applyDeliveredReceipt(deliveredId);
      return;
    }
    if (type == 'message.read') {
      final rawReader = event['user_id'];
      final readerId =
          rawReader is int ? rawReader : int.tryParse('$rawReader');
      final myId = AuthService.instance.currentUser?.id;
      if (readerId != null && readerId == myId) return;
      final raw = event['last_read_message_id'];
      final readId = raw is int ? raw : int.tryParse('$raw');
      if (readId != null) {
        _applyReadReceipt(readId, readerId: readerId);
      }
      return;
    }
    if (type == 'message.edited') {
      final raw = event['message'];
      if (raw is! Map<String, dynamic>) return;
      try {
        _replaceMessage(ChatService.messageFromStreamPayload(raw));
      } catch (e) {
        debugPrint('Chat SSE edit parse failed: $e');
      }
      return;
    }
    if (type == 'message.reaction') {
      final id = event['message_id'];
      final messageId = id is int ? id : int.tryParse('$id');
      if (messageId == null) return;
      _applyReactions(
          messageId, ChatService.parseReactions(event['reactions']));
      return;
    }
    if (type == 'message.pinned' || type == 'message.unpinned') {
      final listRaw = event['pinned_messages'];
      if (listRaw is List) {
        final parsed = <ChatMessage>[];
        for (final raw in listRaw) {
          if (raw is! Map<String, dynamic>) continue;
          try {
            parsed.add(ChatService.messageFromStreamPayload(raw));
          } catch (_) {}
        }
        setState(() => _setPinnedMessages(parsed));
        return;
      }
      if (type == 'message.pinned') {
        final raw = event['message'];
        if (raw is Map<String, dynamic>) {
          try {
            final msg = ChatService.messageFromStreamPayload(raw);
            setState(() => _upsertPinnedMessage(msg));
          } catch (_) {}
        }
      } else {
        final id = event['message_id'];
        final messageId = id is int ? id : int.tryParse('$id');
        setState(() {
          if (messageId != null) {
            _removePinnedMessageId(messageId);
          } else {
            _setPinnedMessages(const []);
          }
        });
      }
      return;
    }
  }

  void _replaceMessage(ChatMessage updated) {
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == updated.id);
      if (idx >= 0) {
        _messages[idx] = applyIncomingChatMessagePreservingLocalPoll(
          _messages[idx],
          updated,
        );
      }
      if (_isMessagePinned(updated.id)) {
        _replacePinnedMessage(
          applyIncomingChatMessagePreservingLocalPoll(
            _pinnedMessages.firstWhere((m) => m.id == updated.id),
            updated,
          ),
        );
      }
    });
  }

  void _applyReactions(int messageId, List<ChatReactionSummary> reactions) {
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        _messages[idx] = _messages[idx].copyWith(reactions: reactions);
      }
      if (_isMessagePinned(messageId)) {
        final cur = _pinnedMessages.firstWhere((m) => m.id == messageId);
        _replacePinnedMessage(cur.copyWith(reactions: reactions));
      }
    });
  }

  String? _normalizedMediaUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    return ServerConfig.resolveMediaUrl(url.trim());
  }

  bool _isDuplicateMessage(ChatMessage a, ChatMessage b) {
    if (a.id > 0 && b.id > 0 && a.id == b.id) return true;
    final ca = (a.clientMessageId ?? '').trim();
    final cb = (b.clientMessageId ?? '').trim();
    if (ca.isNotEmpty && cb.isNotEmpty) return ca == cb;
    if (!a.isMine || !b.isMine) return false;
    if (a.conversationId != b.conversationId) return false;
    if (a.type != b.type) return false;
    if (a.createdAt.difference(b.createdAt).inSeconds.abs() > 20) return false;

    switch (a.type) {
      case 'voice':
        final urlA = _normalizedMediaUrl(a.mediaUrl);
        final urlB = _normalizedMediaUrl(b.mediaUrl);
        if (urlA != null && urlB != null && urlA == urlB) return true;
        return a.content.trim() == b.content.trim();
      case 'image':
        final imageA = _normalizedMediaUrl(a.mediaUrl);
        final imageB = _normalizedMediaUrl(b.mediaUrl);
        return imageA != null && imageA == imageB;
      case 'video':
        final videoA = _normalizedMediaUrl(a.mediaUrl);
        final videoB = _normalizedMediaUrl(b.mediaUrl);
        if (videoA != null && videoA == videoB) return true;
        return a.content.trim() == b.content.trim();
      case 'file':
        final fileA = _normalizedMediaUrl(a.mediaUrl);
        final fileB = _normalizedMediaUrl(b.mediaUrl);
        return fileA != null &&
            fileA == fileB &&
            a.content.trim() == b.content.trim();
      default:
        return a.content.trim() == b.content.trim() &&
            _normalizedMediaUrl(a.mediaUrl) == _normalizedMediaUrl(b.mediaUrl);
    }
  }

  bool _messageBelongsToSelectedTopic(ChatMessage msg) {
    if (!_conversation.isForum) return true;
    final selectedId = _selectedTopicId;
    if (selectedId == null) return true;
    ChatForumTopic? selected;
    for (final t in _forumTopics) {
      if (t.id == selectedId) {
        selected = t;
        break;
      }
    }
    if (selected == null) return true;
    if (selected.isGeneral) {
      return msg.topicId == null || msg.topicId == selected.id;
    }
    return msg.topicId == selected.id;
  }

  int? get _activeTopicIdForSend =>
      _conversation.isForum ? _selectedTopicId : null;

  bool get _canManageForumTopics =>
      _conversation.amICanChangeInfo ||
      (_conversation.createdByUserId != null &&
          _conversation.createdByUserId ==
              AuthService.instance.currentUser?.id);

  ChatForumTopic? get _selectedForumTopic {
    final id = _selectedTopicId;
    if (id == null) return null;
    for (final t in _forumTopics) {
      if (t.id == id) return t;
    }
    return null;
  }

  bool get _selectedTopicIsClosed => _selectedForumTopic?.closed == true;

  Future<void> _loadForumTopics({bool selectGeneralIfNeeded = false}) async {
    if (!_conversation.isForum) {
      if (_forumTopics.isNotEmpty || _selectedTopicId != null) {
        setState(() {
          _forumTopics = const [];
          _selectedTopicId = null;
        });
      }
      return;
    }
    setState(() => _forumTopicsLoading = true);
    try {
      final topics = await ChatService.listForumTopics(
        conversationId: widget.conversationId,
        includeClosed: _canManageForumTopics,
      );
      if (!mounted) return;
      var selected = _selectedTopicId;
      if (selectGeneralIfNeeded ||
          selected == null ||
          !topics.any((t) => t.id == selected)) {
        int? generalId;
        for (final t in topics) {
          if (t.isGeneral) {
            generalId = t.id;
            break;
          }
        }
        selected = generalId ?? (topics.isNotEmpty ? topics.first.id : null);
      }
      final changedTopic = selected != _selectedTopicId;
      setState(() {
        _forumTopics = topics;
        _selectedTopicId = selected;
        _forumTopicsLoading = false;
      });
      if (changedTopic) {
        unawaited(_load(refresh: true));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _forumTopicsLoading = false);
    }
  }

  Future<void> _selectForumTopic(int topicId) async {
    if (_selectedTopicId == topicId) return;
    setState(() => _selectedTopicId = topicId);
    await _load(refresh: true);
  }

  Future<void> _createForumTopicDialog() async {
    if (!_canManageForumTopics) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет права создавать темы')),
      );
      return;
    }
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая тема'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 128,
          decoration: const InputDecoration(
            labelText: 'Название',
            hintText: 'Например: Новости',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || !mounted) return;
    final temp = ChatForumTopic(
      id: -DateTime.now().millisecondsSinceEpoch,
      conversationId: widget.conversationId,
      title: title,
      createdAt: DateTime.now(),
    );
    setState(() => _forumTopics = [..._forumTopics, temp]);
    try {
      final topic = await ChatService.createForumTopic(
        conversationId: widget.conversationId,
        title: title,
      );
      if (!mounted) return;
      setState(() {
        _forumTopics = [
          for (final t in _forumTopics)
            if (t.id == temp.id) topic else t,
        ];
        _selectedTopicId = topic.id;
      });
      unawaited(_load(refresh: true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _forumTopics = [
          for (final t in _forumTopics)
            if (t.id != temp.id) t,
        ];
      });
      if (offerFlexIfRequired(context, e)) return;
      if (offerPackStoreIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _renameForumTopicDialog(ChatForumTopic topic) async {
    final controller = TextEditingController(text: topic.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать тему'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 128,
          decoration: const InputDecoration(labelText: 'Название'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || !mounted) return;
    if (title == topic.title) return;
    setState(() {
      _forumTopics = [
        for (final t in _forumTopics)
          if (t.id == topic.id) t.copyWith(title: title) else t,
      ];
    });
    try {
      final updated = await ChatService.updateForumTopic(
        conversationId: widget.conversationId,
        topicId: topic.id,
        title: title,
      );
      if (!mounted) return;
      setState(() {
        _forumTopics = [
          for (final t in _forumTopics)
            if (t.id == updated.id) updated else t,
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _forumTopics = [
          for (final t in _forumTopics)
            if (t.id == topic.id) topic else t,
        ];
      });
      if (offerFlexIfRequired(context, e)) return;
      if (offerPackStoreIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _setForumTopicClosed(ChatForumTopic topic, bool closed) async {
    setState(() {
      _forumTopics = [
        for (final t in _forumTopics)
          if (t.id == topic.id) t.copyWith(closed: closed) else t,
      ];
    });
    try {
      final updated = await ChatService.updateForumTopic(
        conversationId: widget.conversationId,
        topicId: topic.id,
        closed: closed,
      );
      if (!mounted) return;
      setState(() {
        _forumTopics = [
          for (final t in _forumTopics)
            if (t.id == updated.id) updated else t,
        ];
      });
      if (closed && _selectedTopicId == topic.id) {
        ChatForumTopic? general;
        for (final t in _forumTopics) {
          if (t.isGeneral) {
            general = t;
            break;
          }
        }
        if (general != null) {
          await _selectForumTopic(general.id);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(closed ? 'Тема закрыта' : 'Тема снова открыта'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _forumTopics = [
          for (final t in _forumTopics)
            if (t.id == topic.id) topic else t,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _showForumTopicActions(ChatForumTopic topic) async {
    if (!_canManageForumTopics) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: HighlightedText(
                text: topic.displayLabel,
                style: Theme.of(ctx).textTheme.bodyLarge ??
                    const TextStyle(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                topic.isGeneral
                    ? 'Главная тема группы'
                    : (topic.closed ? 'Закрыта для новых сообщений' : 'Открыта'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Переименовать'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            if (!topic.isGeneral && !topic.closed)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Закрыть тему'),
                subtitle: const Text('Нельзя писать, история останется'),
                onTap: () => Navigator.pop(ctx, 'close'),
              ),
            if (!topic.isGeneral && topic.closed)
              ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: const Text('Открыть тему'),
                onTap: () => Navigator.pop(ctx, 'reopen'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'rename') {
      await _renameForumTopicDialog(topic);
    } else if (action == 'close') {
      await _setForumTopicClosed(topic, true);
    } else if (action == 'reopen') {
      await _setForumTopicClosed(topic, false);
    }
  }

  Widget _buildSavedTagsBar(ColorScheme scheme) {
    final locked = !_hasFlexFeature('saved_tags');
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF18222D)
          : scheme.surface,
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: const Text('Все'),
                selected: _activeSavedTagId == null,
                onSelected: (_) => unawaited(_selectSavedTagFilter(null)),
              ),
            ),
            for (final tag in _savedTags)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: HighlightedText(
                    text: tag.label,
                    style: Theme.of(context).textTheme.labelLarge ??
                        const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: _activeSavedTagId == tag.id,
                  onSelected: locked
                      ? (_) => unawaited(showCreatorUpsell(context))
                      : (_) => unawaited(_selectSavedTagFilter(tag.id)),
                ),
              ),
            ActionChip(
              avatar: Icon(
                locked ? Icons.lock_outline : Icons.add,
                size: 16,
              ),
              label: const Text('Тег'),
              onPressed: () => unawaited(_createSavedTagFromBar()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForumTopicsStrip(ColorScheme scheme) {
    if (!_conversation.isForum) return const SizedBox.shrink();
    final canManage = _canManageForumTopics;
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF18222D)
          : scheme.surface,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          children: [
            if (_forumTopicsLoading && _forumTopics.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            for (final topic in _forumTopics)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onLongPress: canManage
                      ? () => unawaited(_showForumTopicActions(topic))
                      : null,
                  child: Opacity(
                    opacity: topic.closed ? 0.65 : 1,
                    child: ChoiceChip(
                      avatar: topic.closed
                          ? Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            )
                          : null,
                      label: HighlightedText(
                        text: topic.closed
                            ? '${topic.displayLabel} · закрыта'
                            : topic.displayLabel,
                        style: Theme.of(context).textTheme.labelLarge ??
                            const TextStyle(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: _selectedTopicId == topic.id,
                      onSelected: (_) =>
                          unawaited(_selectForumTopic(topic.id)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
            if (canManage)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Тема'),
                  onPressed: () => unawaited(_createForumTopicDialog()),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Вставляет или обновляет сообщение, убирая оптимистичные и повторные копии.
  /// Возвращает true, если сообщение добавлено впервые.
  bool _integrateMessage(ChatMessage msg, {int? removeTempId}) {
    if (!_messageBelongsToSelectedTopic(msg)) {
      if (removeTempId != null) {
        _messages.removeWhere((m) => m.id == removeTempId);
      }
      return false;
    }
    if (removeTempId != null) {
      final removedFailedText = _failedTextSends.remove(removeTempId) != null;
      final removedFailedReady = _failedReadySends.remove(removeTempId) != null;
      _removePendingMediaByTempId(removeTempId);
      if (removedFailedText) {
        unawaited(_persistFailedTextSends());
      }
      if (removedFailedReady) {
        unawaited(_persistReadySends());
      }
    }
    final result = integrateIncomingChatMessage(
      messages: _messages,
      incoming: msg,
      removeTempId: removeTempId,
      isDuplicate: _isDuplicateMessage,
      merge: (prev, incoming) {
        var next = incoming;
        // WS fanout redacts paid media_url for everyone; don't wipe own media.
        if (prev.isMine &&
            prev.isPaid &&
            (next.mediaUrl == null || next.mediaUrl!.isEmpty) &&
            prev.mediaUrl != null &&
            prev.mediaUrl!.isNotEmpty) {
          next = next.copyWith(
            mediaUrl: prev.mediaUrl,
            purchased: true,
            isPaid: prev.isPaid,
            priceStars: prev.priceStars,
          );
        }
        if ((next.clientMessageId == null || next.clientMessageId!.isEmpty) &&
            (prev.clientMessageId ?? '').isNotEmpty) {
          next = next.copyWith(clientMessageId: prev.clientMessageId);
        }
        return applyIncomingChatMessagePreservingLocalPoll(prev, next);
      },
    );
    _messages
      ..clear()
      ..addAll(result.messages);
    _prefetchCustomEmojis([msg]);
    return result.added;
  }

  void _prefetchCustomEmojis([Iterable<ChatMessage>? msgs]) {
    final ids = <int>{};
    for (final m in msgs ?? _messages) {
      ids.addAll(parseCustomEmojiIds(m.content));
      for (final r in m.reactions) {
        final id = parseCustomEmojiTokenId(r.emoji);
        if (id != null) ids.add(id);
      }
    }
    final statusId = parseCustomEmojiTokenId(_conversation.peer?.emojiStatus);
    if (statusId != null) ids.add(statusId);
    if (ids.isEmpty) return;
    unawaited(CustomEmojiRegistry.instance.resolveMissing(ids));
  }

  String _pinnedPreview(ChatMessage msg) {
    if (msg.type == 'call') {
      return CallMessageLabels.preview(msg.content, mine: msg.isMine);
    }
    if (msg.type == 'voice') return '🎤 Голосовое';
    if (msg.type == 'image') return '📷 Фото';
    if (msg.type == 'video') return '🎬 Видео';
    if (msg.type == 'video_note') return '⭕ Видеосообщение';
    if (msg.type == 'sticker') return '🧩 Стикер';
    if (msg.type == 'poll') {
      final poll = msg.poll;
      if (poll != null) return chatPollPreviewText(poll);
      return '📊 Опрос';
    }
    if (msg.type == 'checklist') {
      return msg.checklist?.preview ?? '☑ Чеклист';
    }
    if (msg.type == 'file') {
      final name = msg.content.trim();
      return name.isEmpty
          ? '📎 Файл'
          : '📎 ${previewTextWithCustomEmoji(name)}';
    }
    if (msg.type == 'location' ||
        ChatLocationPayload.tryParse(msg.content) != null) {
      final loc = ChatLocationPayload.tryParse(msg.content);
      return loc?.previewText ?? '📍 Геопозиция';
    }
    if (msg.type == 'story_reply' ||
        ChatStoryReplyPayload.tryParse(msg.content) != null) {
      final reply = ChatStoryReplyPayload.tryParse(msg.content);
      return reply?.previewText ?? '🖼 Ответ на сторис';
    }
    final contact = ChatContactPayload.tryParse(msg.content);
    if (contact != null) {
      return '👤 ${previewTextWithCustomEmoji(contact.displayName)}';
    }
    final text = msg.content.trim();
    if (text.isEmpty) return 'Сообщение';
    return previewTextWithCustomEmoji(text);
  }

  void _scrollToMessage(int messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0 || !_scroll.hasClients || _messages.isEmpty) return;
    final ctx = _messageItemKeys[messageId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.42,
      );
      return;
    }
    final fraction = idx / math.max(1, _messages.length - 1);
    _scroll.animateTo(
      _scroll.position.maxScrollExtent * fraction,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _scrollToReplyMessage(int messageId) async {
    if (_messages.any((m) => m.id == messageId)) {
      _scrollToMessage(messageId);
      return;
    }
    var attempts = 0;
    while (_hasMore && attempts < 8) {
      attempts++;
      await _load(refresh: false);
      if (_messages.any((m) => m.id == messageId)) {
        if (!mounted) return;
        _scrollToMessage(messageId);
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Исходное сообщение не найдено')),
    );
  }

  void _beginSending({String status = 'Отправка…'}) {
    setState(() {
      _sending = true;
      _sendingStatus = status;
      _uploadProgress = null;
    });
  }

  void _endSending() {
    setState(() {
      _sending = false;
      _sendingStatus = 'Отправка…';
      _uploadProgress = null;
    });
  }

  void _setMediaComposerStatus(String status, {double? progress}) {
    if (!mounted) return;
    setState(() {
      _sendingStatus = status;
      if (progress != null) {
        _uploadProgress = progress.clamp(0.0, 1.0);
      }
    });
  }

  void _clearMediaComposerProgress() {
    if (!mounted) return;
    setState(() {
      _uploadProgress = null;
      _sendingStatus = 'Отправка…';
    });
  }

  void _setUploadProgress(double value, {String? status}) {
    if (!mounted) return;
    setState(() {
      _uploadProgress = value.clamp(0.0, 1.0);
      if (status != null) _sendingStatus = status;
    });
  }

  Future<void> _retryFailedText(int tempId) async {
    _clearFailedTextAutoRetry(tempId);
    final pending = _failedTextSends[tempId];
    if (pending == null) return;
    _failedTextSends.remove(tempId);
    unawaited(_persistFailedTextSends());
    pending.attempts = 0;
    pending.lastRetryAfterSeconds = null;
    pending.lastLimitedAt = null;
    setState(() => _textOutboundQueue.add(pending));
    _kickTextOutbound();
  }

  void _discardFailedText(int tempId) {
    _clearFailedTextAutoRetry(tempId);
    setState(() {
      _failedTextSends.remove(tempId);
      _messages.removeWhere((m) => m.id == tempId);
    });
    if (!_hasFailedPendingItems) {
      _clearManualReadyRetrySchedule();
    }
    unawaited(_persistFailedTextSends());
    unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
  }

  void _clearFailedTextAutoRetry(int tempId) {
    _failedTextAutoRetryTimers[tempId]?.cancel();
    _failedTextAutoRetryTimers.remove(tempId);
    _failedTextAutoRetryUntil.remove(tempId);
    _failedTextAutoRetryReason.remove(tempId);
    _syncSlowModeCountdownTimer();
  }

  void _cancelFailedTextAutoRetry(int tempId) {
    _clearFailedTextAutoRetry(tempId);
  }

  void _scheduleFailedTextAutoRetry(
    _PendingTextSend pending, {
    required int retryAfterSeconds,
    required String reason,
  }) {
    if (!_autoRetryOnLimitsEnabled) return;
    final waitSec = retryAfterSeconds.clamp(1, 120).toInt();
    _clearFailedTextAutoRetry(pending.tempId);
    _failedTextAutoRetryUntil[pending.tempId] =
        DateTime.now().add(Duration(seconds: waitSec));
    _failedTextAutoRetryReason[pending.tempId] = reason;
    _syncSlowModeCountdownTimer();
    _failedTextAutoRetryTimers[pending.tempId] =
        Timer(Duration(seconds: waitSec), () {
      if (!mounted) return;
      if (!_failedTextSends.containsKey(pending.tempId)) return;
      unawaited(_retryFailedText(pending.tempId));
    });
  }

  int? _remainingRetryDelay({
    required int? retryAfterSeconds,
    required DateTime? limitedAt,
  }) {
    return remainingRetryDelay(
      retryAfterSeconds: retryAfterSeconds,
      limitedAt: limitedAt,
    );
  }

  int? _remainingRetryDelayForText(_PendingTextSend pending) {
    return _remainingRetryDelay(
      retryAfterSeconds: pending.lastRetryAfterSeconds,
      limitedAt: pending.lastLimitedAt,
    );
  }

  int? _remainingRetryDelayForMedia(_PendingMediaSend pending) {
    return _remainingRetryDelay(
      retryAfterSeconds: pending.lastRetryAfterSeconds,
      limitedAt: pending.lastLimitedAt,
    );
  }

  int? get _nextManualRetryRemainingSeconds {
    return nextManualRetryRemainingSeconds([
      for (final pending in _failedTextSends.values)
        _remainingRetryDelayForText(pending),
      if (_pendingMediaRetry != null)
        _remainingRetryDelayForMedia(_pendingMediaRetry!),
    ]);
  }

  void _discardPendingMedia() {
    final pending = _pendingMediaRetry;
    _clearPendingMediaAutoRetry();
    setState(() {
      _pendingMediaRetry = null;
      if (pending != null) {
        _removePendingMediaByTempId(pending.tempId, removeMessage: true);
      }
    });
    if (pending != null) {
      unawaited(_removeMediaOutbox(pending.clientMessageId));
    }
    if (!_hasFailedPendingItems) {
      _clearManualReadyRetrySchedule();
    }
  }

  List<_ManualRetryTask> _buildManualRetryTasks() {
    final pendingMedia = _pendingMediaRetry;
    final failedTextItems = _failedTextSends.values.toList(growable: false);
    return sortManualRetryItems<_ManualRetryTask>(
      <_ManualRetryTask>[
        if (pendingMedia != null)
          _ManualRetryTask(
            remainingSeconds: _remainingRetryDelayForMedia(pendingMedia),
            isMedia: true,
            action: _retryPendingMedia,
          ),
        for (final pending in failedTextItems)
          _ManualRetryTask(
            remainingSeconds: _remainingRetryDelayForText(pending),
            isMedia: false,
            action: () => _retryFailedText(pending.tempId),
          ),
        for (final pending in _failedReadySends.values)
          _ManualRetryTask(
            remainingSeconds: null,
            isMedia: false,
            action: () => _retryFailedReady(pending.tempId),
          ),
      ],
      (item) => item.remainingSeconds,
      (item) => item.isMedia,
    );
  }

  Future<void> _runManualRetryTasks(
    List<_ManualRetryTask> retryTasks, {
    String? completionSuffix,
  }) async {
    if (retryTasks.isEmpty || _sending || _retryAllBulkBusy) return;
    _clearManualReadyRetrySchedule();
    final cooldownBeforeRetry = _activeCooldownRemainingSeconds;
    if (mounted) {
      setState(() {
        _retryAllBulkBusy = true;
        _retryAllBulkCancelRequested = false;
        _clearAllAfterBulkStopRequested = false;
        _retryAllBulkDone = 0;
        _retryAllBulkTotal = retryTasks.length;
      });
    }
    const interItemDelay = Duration(milliseconds: 160);
    var retriedMedia = 0;
    var retriedText = 0;
    var cancelled = false;
    try {
      for (var i = 0; i < retryTasks.length; i++) {
        if (_retryAllBulkCancelRequested) {
          cancelled = true;
          break;
        }
        final task = retryTasks[i];
        await task.action();
        if (task.isMedia) {
          retriedMedia++;
        } else {
          retriedText++;
        }
        if (mounted) {
          setState(() {
            _retryAllBulkDone = i + 1;
          });
        }
        if (_retryAllBulkCancelRequested) {
          cancelled = true;
          break;
        }
        if (i < retryTasks.length - 1) {
          await Future<void>.delayed(interItemDelay);
        }
      }
      if (!mounted) return;
      final total = retriedMedia + retriedText;
      if (total <= 0) return;
      final details = <String>[
        if (retriedText > 0) 'текст: $retriedText',
        if (retriedMedia > 0) 'медиа: $retriedMedia',
      ].join(', ');
      final waitSuffix = cooldownBeforeRetry > 0
          ? '. Отправка начнётся через ${_formatSlowModeCountdown(cooldownBeforeRetry)}'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (total == 1
                    ? 'Повтор запущен ($details)$waitSuffix'
                    : 'Повтор запущен для $total элементов ($details)$waitSuffix') +
                (completionSuffix ?? '') +
                (cancelled ? '. Остановлено пользователем' : ''),
          ),
        ),
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final runClearAfterStop = _clearAllAfterBulkStopRequested;
      if (mounted) {
        setState(() {
          _retryAllBulkBusy = false;
          _retryAllBulkCancelRequested = false;
          _clearAllAfterBulkStopRequested = false;
          _retryAllBulkDone = 0;
          _retryAllBulkTotal = 0;
        });
        if (runClearAfterStop) {
          unawaited(_clearAllFailedPending());
        }
      }
    }
  }

  void _cancelRetryAllBulk() {
    if (!_retryAllBulkBusy || _retryAllBulkCancelRequested) return;
    setState(() {
      _retryAllBulkCancelRequested = true;
    });
    _logRetryAction('bulk_cancel_requested');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Останавливаем пакетный повтор...')),
    );
  }

  void _logRetryAction(
    String action, {
    Map<String, dynamic>? metadata,
  }) {
    unawaited(
      ProductAnalytics.logEvent(
        eventType: 'chat_retry_action',
        entityType: 'conversation',
        entityId: widget.conversationId,
        metadata: {
          'action': action,
          'auto_retry_enabled': _autoRetryOnLimitsEnabled,
          if (metadata != null) ...metadata,
        },
      ),
    );
  }

  void _requestClearAfterBulkStop() {
    if (!_retryAllBulkBusy) {
      unawaited(_clearAllFailedPending());
      return;
    }
    setState(() {
      _clearAllAfterBulkStopRequested = true;
    });
    _logRetryAction('clear_after_bulk_stop_requested');
    _cancelRetryAllBulk();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Останавливаем повтор. Очистка откроется сразу после остановки.',
        ),
      ),
    );
  }

  Future<void> _retryAllFailedPending() async {
    _logRetryAction('retry_all_manual');
    await _runManualRetryTasks(_buildManualRetryTasks());
  }

  void _clearManualReadyRetrySchedule({bool resetDeferrals = true}) {
    final hadSchedule =
        _manualReadyRetryTimer != null || _manualReadyRetryUntil != null;
    _manualReadyRetryTimer?.cancel();
    _manualReadyRetryTimer = null;
    _manualReadyRetryUntil = null;
    if (resetDeferrals) _manualReadyRetryDeferrals = 0;
    _syncSlowModeCountdownTimer();
    if (hadSchedule && mounted) setState(() {});
  }

  void _cancelManualReadyRetrySchedule() {
    _clearManualReadyRetrySchedule();
    if (!mounted) return;
    _logRetryAction('manual_ready_autostart_cancel');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Автозапуск готовых отменен')),
    );
  }

  void _scheduleManualReadyRetry(
    int waitSec, {
    bool announce = true,
  }) {
    if (_autoRetryOnLimitsEnabled || !_hasFailedPendingItems) return;
    final safeWait = waitSec.clamp(1, 1200);
    final isReschedule =
        _manualReadyRetryUntil != null || _manualReadyRetryTimer != null;
    final nextDeferrals = nextManualReadyRetryDeferrals(
      isReschedule: isReschedule,
      currentDeferrals: _manualReadyRetryDeferrals,
    );
    _clearManualReadyRetrySchedule(resetDeferrals: false);
    _manualReadyRetryDeferrals = nextDeferrals;
    _manualReadyRetryUntil = DateTime.now().add(Duration(seconds: safeWait));
    _logRetryAction(
      'manual_ready_autostart_schedule',
      metadata: {
        'wait_seconds': safeWait,
        'is_reschedule': isReschedule,
        'deferrals': nextDeferrals,
      },
    );
    _syncSlowModeCountdownTimer();
    if (mounted) setState(() {});
    _armManualReadyRetryTimer(safeWait);
    if (!announce || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Автозапуск готовых через ${_formatSlowModeCountdown(safeWait)}',
        ),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: _cancelManualReadyRetrySchedule,
        ),
      ),
    );
  }

  void _armManualReadyRetryTimer(int waitSec) {
    _manualReadyRetryTimer?.cancel();
    _manualReadyRetryTimer = Timer(Duration(seconds: waitSec), () {
      if (!mounted) return;
      if (_sending || _retryAllBulkBusy) {
        if (shouldStopManualReadyRetry(deferrals: _manualReadyRetryDeferrals)) {
          _clearManualReadyRetrySchedule();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Автозапуск готовых остановлен: чат долго занят отправкой',
              ),
            ),
          );
          return;
        }
        _scheduleManualReadyRetry(2, announce: false);
        return;
      }
      _clearManualReadyRetrySchedule();
      unawaited(_retryReadyFailedPending());
    });
  }

  void _reconcileManualReadyRetrySchedule() {
    final until = _manualReadyRetryUntil;
    if (until == null) return;
    final remainingMs = until.difference(DateTime.now()).inMilliseconds;
    if (remainingMs <= 0) {
      _clearManualReadyRetrySchedule();
      unawaited(_retryReadyFailedPending());
      return;
    }
    final remainingSec = (remainingMs / 1000).ceil().clamp(1, 1200);
    _armManualReadyRetryTimer(remainingSec);
    _syncSlowModeCountdownTimer();
    if (mounted) setState(() {});
  }

  Future<void> _retryReadyFailedPending() async {
    if (_sending || _retryAllBulkBusy) return;
    final tasks = _buildManualRetryTasks();
    if (tasks.isEmpty) return;
    final readyTasks = readyManualRetryItems<_ManualRetryTask>(
        tasks, (t) => t.remainingSeconds);
    final skipped = tasks.length - readyTasks.length;
    if (readyTasks.isEmpty) {
      if (!mounted) return;
      final remaining = _nextManualRetryRemainingSeconds;
      final suffix = remaining != null
          ? 'Ближайшая готовность через ${_formatSlowModeCountdown(remaining)}.'
          : 'Пока нет элементов для повтора.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(suffix),
          action: (remaining != null && remaining > 0)
              ? SnackBarAction(
                  label: 'Автозапуск',
                  onPressed: () => _scheduleManualReadyRetry(remaining),
                )
              : null,
        ),
      );
      return;
    }
    _logRetryAction(
      'retry_ready_manual',
      metadata: {
        'ready_count': readyTasks.length,
        'skipped_count': skipped,
      },
    );
    _clearManualReadyRetrySchedule();
    final completionSuffix =
        skipped > 0 ? '. Отложено: $skipped, пока действует лимит' : null;
    await _runManualRetryTasks(
      readyTasks,
      completionSuffix: completionSuffix,
    );
  }

  Future<void> _retryAllFailedPendingWithGuard() async {
    if (_sending || _retryAllBulkBusy) return;
    final remaining = _nextManualRetryRemainingSeconds;
    if (remaining != null && remaining > 8) {
      _logRetryAction(
        'retry_all_guard_shown',
        metadata: {'remaining_seconds': remaining},
      );
      final proceedNow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Повторить сейчас?'),
          content: Text(
            'До ближайшей готовности примерно ${_formatSlowModeCountdown(remaining)}.'
            '\nМожно подождать, чтобы снизить шанс повторного лимита.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Подождать'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Все равно повторить'),
            ),
          ],
        ),
      );
      if (proceedNow != true || !mounted) {
        _logRetryAction('retry_all_guard_cancelled');
        return;
      }
      _logRetryAction('retry_all_guard_confirmed');
    }
    await _retryAllFailedPending();
  }

  String _failedItemsClearSummary(int textCount, int mediaCount) {
    final parts = <String>[
      if (textCount > 0) 'текст: $textCount',
      if (mediaCount > 0) 'медиа: $mediaCount',
    ];
    return parts.join(', ');
  }

  Future<void> _showClearedFailedItemsSnackbar({
    required int textCount,
    required int mediaCount,
  }) async {
    if (!mounted) return;
    final total = textCount + mediaCount;
    if (total <= 0) return;
    final details = _failedItemsClearSummary(textCount, mediaCount);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          total == 1
              ? 'Неотправленный элемент удален ($details)'
              : 'Неотправленные элементы очищены: $total ($details)',
        ),
      ),
    );
  }

  Future<void> _clearAllFailedPending() async {
    if (_sending) return;
    if (_retryAllBulkBusy) {
      _requestClearAfterBulkStop();
      return;
    }
    final mediaCount = _pendingMediaRetry != null ? 1 : 0;
    final failedTextIds = _failedTextSends.keys.toList(growable: false);
    final failedReadyIds = _failedReadySends.keys.toList(growable: false);
    if (mediaCount == 0 && failedTextIds.isEmpty && failedReadyIds.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить неотправленные?'),
        content: const Text(
          'Все неотправленные сообщения и медиа будут удалены из очереди.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _logRetryAction(
      'clear_all_pending_confirmed',
      metadata: {
        'text_count': failedTextIds.length,
        'media_count': mediaCount,
      },
    );
    _clearManualReadyRetrySchedule();
    _clearPendingMediaAutoRetry();
    for (final tempId in failedTextIds) {
      _clearFailedTextAutoRetry(tempId);
    }
    setState(() {
      final failedMediaTempId = _pendingMediaRetry?.tempId;
      _pendingMediaRetry = null;
      _failedTextSends.removeWhere((_, __) => true);
      _failedReadySends.removeWhere((_, __) => true);
      _messages.removeWhere(
        (m) =>
            failedTextIds.contains(m.id) ||
            failedReadyIds.contains(m.id) ||
            (failedMediaTempId != null && m.id == failedMediaTempId),
      );
      if (failedMediaTempId != null) {
        _removePendingMediaByTempId(failedMediaTempId);
      }
    });
    unawaited(_persistFailedTextSends());
    unawaited(_persistReadySends());
    unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    await _showClearedFailedItemsSnackbar(
      textCount: failedTextIds.length,
      mediaCount: mediaCount,
    );
  }

  void _rememberFailedMedia(_PendingMediaSend pending) {
    _clearPendingMediaAutoRetry();
    setState(() => _pendingMediaRetry = pending);
    unawaited(_persistMediaOutbox(pending, failed: true));
  }

  void _clearPendingMediaAutoRetry() {
    _pendingMediaAutoRetryTimer?.cancel();
    _pendingMediaAutoRetryTimer = null;
    _pendingMediaAutoRetryClientMessageId = null;
    _pendingMediaAutoRetryUntil = null;
    _pendingMediaAutoRetryReason = null;
    _syncSlowModeCountdownTimer();
  }

  void _cancelPendingMediaAutoRetry() {
    _clearPendingMediaAutoRetry();
  }

  void _schedulePendingMediaAutoRetry(
    _PendingMediaSend pending, {
    required int retryAfterSeconds,
    required String reason,
  }) {
    if (!_autoRetryOnLimitsEnabled) return;
    final waitSec = retryAfterSeconds.clamp(1, 120).toInt();
    _clearPendingMediaAutoRetry();
    _pendingMediaAutoRetryUntil =
        DateTime.now().add(Duration(seconds: waitSec));
    _pendingMediaAutoRetryReason = reason;
    if (mounted) setState(() {});
    _syncSlowModeCountdownTimer();
    _pendingMediaAutoRetryClientMessageId = pending.clientMessageId;
    _pendingMediaAutoRetryTimer = Timer(Duration(seconds: waitSec), () {
      if (!mounted) return;
      final expectedId = _pendingMediaAutoRetryClientMessageId;
      if (expectedId == null) return;
      if (_pendingMediaRetry?.clientMessageId != expectedId) return;
      unawaited(_retryPendingMedia());
    });
  }

  Future<void> _retryPendingMedia() async {
    final pending = _pendingMediaRetry;
    if (pending == null) return;
    _clearPendingMediaAutoRetry();
    setState(() => _pendingMediaRetry = null);
    pending.attempts = 0;
    pending.lastRetryAfterSeconds = null;
    pending.lastLimitedAt = null;
    _enqueueMediaSend(pending);
  }

  void _cancelPendingMediaUploadByTempId(int tempId) {
    final pending = _pendingMediaByTempId[tempId];
    if (pending == null) return;
    _cancelledPendingMediaClientIds.add(pending.clientMessageId);
    _clearPendingMediaAutoRetry();
    setState(() {
      _mediaOutboundQueue
          .removeWhere((p) => p.clientMessageId == pending.clientMessageId);
      if (_pendingMediaRetry?.clientMessageId == pending.clientMessageId) {
        _pendingMediaRetry = null;
      }
      _removePendingMediaByTempId(tempId, removeMessage: true);
    });
    if (_mediaOutboundQueue.isEmpty) {
      _clearMediaComposerProgress();
    }
  }

  void _removePendingMediaByTempId(int tempId, {bool removeMessage = false}) {
    final pending = _pendingMediaByTempId.remove(tempId);
    if (pending == null) return;
    _pendingMediaTempIdByClientId.remove(pending.clientMessageId);
    _pendingMediaProgressByClientId.remove(pending.clientMessageId);
    _cancelledPendingMediaClientIds.remove(pending.clientMessageId);
    if (removeMessage) {
      _messages.removeWhere((m) => m.id == tempId);
      unawaited(_removeMediaOutbox(pending.clientMessageId));
    }
  }

  Future<Uint8List?> _bytesForMediaOutbox(_PendingMediaSend pending) async {
    final cached = pending.payloadBytes ?? pending.previewBytes;
    if (cached != null &&
        cached.isNotEmpty &&
        cached.length <= ChatMediaOutboxService.maxBytesPerItem) {
      return cached;
    }
    try {
      final bytes = await pending.file.readAsBytes();
      if (bytes.isEmpty ||
          bytes.length > ChatMediaOutboxService.maxBytesPerItem) {
        return null;
      }
      pending.payloadBytes = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistMediaOutbox(
    _PendingMediaSend pending, {
    required bool failed,
  }) async {
    final bytes = await _bytesForMediaOutbox(pending);
    if (bytes == null) return;
    await ChatMediaOutboxService.upsert(
      conversationId: widget.conversationId,
      clientMessageId: pending.clientMessageId,
      tempId: pending.tempId,
      kind: pending.kind.name,
      bytes: bytes,
      fileName: pending.fileName,
      replyToMessageId: pending.replyToMessageId,
      voiceDurationSec: pending.voiceDurationSec,
      uploadedMediaUrl: pending.uploadedMediaUrl,
      attempts: pending.attempts,
      lastRetryAfterSeconds: pending.lastRetryAfterSeconds,
      lastLimitedAtIso: pending.lastLimitedAt?.toUtc().toIso8601String(),
      failed: failed,
    );
  }

  Future<void> _removeMediaOutbox(String clientMessageId) {
    return ChatMediaOutboxService.remove(
      conversationId: widget.conversationId,
      clientMessageId: clientMessageId,
    );
  }

  Future<void> _restoreMediaOutbox() async {
    final rows =
        await ChatMediaOutboxService.loadConversation(widget.conversationId);
    if (rows.isEmpty || !mounted) return;
    final uid = AuthService.instance.currentUser?.id ?? 0;
    final restoredMessages = <ChatMessage>[];
    _PendingMediaSend? firstFailed;
    for (final row in rows) {
      final clientMessageId = row['client_message_id'] as String? ?? '';
      final tempId = row['temp_id'] as int? ?? 0;
      final kindName = row['kind'] as String? ?? '';
      final bytes = row['bytes'];
      if (clientMessageId.isEmpty ||
          tempId >= 0 ||
          bytes is! Uint8List ||
          bytes.isEmpty) {
        continue;
      }
      if (_pendingMediaByTempId.containsKey(tempId) ||
          _pendingMediaTempIdByClientId.containsKey(clientMessageId)) {
        continue;
      }
      final kind = _PendingMediaKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => _PendingMediaKind.file,
      );
      final fileName = row['file_name'] as String?;
      final mime = switch (kind) {
        _PendingMediaKind.image => 'image/jpeg',
        _PendingMediaKind.video => 'video/mp4',
        _PendingMediaKind.voice => 'audio/m4a',
        _PendingMediaKind.file => 'application/octet-stream',
      };
      final file = XFile.fromData(
        bytes,
        name: fileName ?? 'media',
        mimeType: mime,
      );
      final pending = _PendingMediaSend(
        tempId: tempId,
        kind: kind,
        file: file,
        clientMessageId: clientMessageId,
        fileName: fileName,
        replyToMessageId: row['reply_to_message_id'] as int?,
        voiceDurationSec: row['voice_duration_sec'] as int?,
        totalBytes: bytes.length,
        previewBytes: kind == _PendingMediaKind.image ? bytes : null,
        topicId: row['topic_id'] as int? ?? _activeTopicIdForSend,
      );
      pending.payloadBytes = bytes;
      pending.uploadedMediaUrl = row['uploaded_media_url'] as String?;
      pending.attempts = row['attempts'] as int? ?? 0;
      pending.lastRetryAfterSeconds =
          (row['last_retry_after_seconds'] as int?)?.clamp(1, 3600);
      pending.lastLimitedAt = DateTime.tryParse(
        row['last_limited_at'] as String? ?? '',
      );
      final failed = row['failed'] as bool? ?? true;
      _pendingMediaByTempId[tempId] = pending;
      _pendingMediaTempIdByClientId[clientMessageId] = tempId;
      if (!_messages.any((m) => m.id == tempId)) {
        restoredMessages.add(
          ChatMessage(
            id: tempId,
            conversationId: widget.conversationId,
            senderId: uid,
            type: switch (kind) {
              _PendingMediaKind.image => 'image',
              _PendingMediaKind.video => 'video',
              _PendingMediaKind.file => 'file',
              _PendingMediaKind.voice => 'voice',
            },
            content: switch (kind) {
              _PendingMediaKind.file => fileName ?? 'Файл',
              _PendingMediaKind.voice => '${pending.voiceDurationSec ?? 1}',
              _ => '',
            },
            replyToMessageId: pending.replyToMessageId,
            createdAt:
                DateTime.tryParse(row['created_at'] as String? ?? '') ??
                    DateTime.now(),
            isMine: true,
            isDelivered: false,
            isRead: false,
          ),
        );
      }
      if (failed) {
        firstFailed ??= pending;
      } else {
        _mediaOutboundQueue.add(pending);
      }
    }
    if (restoredMessages.isEmpty &&
        firstFailed == null &&
        _mediaOutboundQueue.isEmpty) {
      return;
    }
    setState(() {
      _messages.addAll(restoredMessages);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (firstFailed != null) {
        _pendingMediaRetry = firstFailed;
      }
    });
    if (_mediaOutboundQueue.isNotEmpty) {
      unawaited(_drainMediaOutboundQueue());
    }
  }

  Widget _pendingMediaRetryBanner(ColorScheme scheme) {
    final pending = _pendingMediaRetry;
    if (pending == null) return const SizedBox.shrink();
    final autoRetrying =
        _pendingMediaAutoRetryClientMessageId == pending.clientMessageId &&
            _pendingMediaAutoRetryRemainingSeconds > 0;
    final label = switch (pending.kind) {
      _PendingMediaKind.image => 'фото',
      _PendingMediaKind.video => 'видео',
      _PendingMediaKind.file => 'файл',
      _PendingMediaKind.voice => 'голосовое',
    };
    return _compactComposerStrip(
      icon: Icons.error_outline_rounded,
      label: autoRetrying
          ? 'Медиа ($label) · повтор через ${_formatSlowModeCountdown(_pendingMediaAutoRetryRemainingSeconds)}'
          : 'Не отправлено · $label',
      actionLabel: autoRetrying ? 'Стоп' : 'Повторить',
      onAction: _sending
          ? null
          : (autoRetrying
              ? _cancelPendingMediaAutoRetry
              : () => unawaited(_retryPendingMedia())),
      secondaryActionLabel: 'Удалить',
      onSecondaryAction: _sending ? null : _discardPendingMedia,
    );
  }

  Future<void> _restoreDraft() async {
    // Prefer seed from reply-privately / deep open.
    final seed = widget.initialDraftText?.trim();
    if (seed != null && seed.isNotEmpty && _controller.text.trim().isEmpty) {
      _controller.text = seed;
      _controller.selection = TextSelection.collapsed(offset: seed.length);
      unawaited(_persistDraftLocalAndCloud());
      return;
    }

    ChatDraft? local = await ChatCacheService.loadDraft(widget.conversationId);
    ChatDraft? cloud;
    try {
      final map = await ChatService.listCloudDraftsByConversation();
      cloud = map[widget.conversationId];
    } catch (_) {}

    ChatDraft? draft = local;
    if (cloud != null && !cloud.isEmpty) {
      final localAt = local?.updatedAt;
      final cloudAt = cloud.updatedAt;
      if (local == null ||
          local.isEmpty ||
          (cloudAt != null &&
              (localAt == null || cloudAt.isAfter(localAt)))) {
        draft = cloud;
        await ChatCacheService.saveDraft(
          widget.conversationId,
          cloud.text,
          replyToMessageId: cloud.replyToMessageId,
          updatedAt: cloud.updatedAt,
        );
      } else {
        // Local draft is newer — push it to cloud.
        unawaited(
          ChatService.upsertCloudDraft(
            conversationId: widget.conversationId,
            text: local.text,
            replyToMessageId: local.replyToMessageId,
          ),
        );
      }
    }

    if (!mounted || draft == null || draft.isEmpty) return;
    if (_controller.text.trim().isEmpty && draft.text.isNotEmpty) {
      _controller.text = draft.text;
      _controller.selection =
          TextSelection.collapsed(offset: draft.text.length);
    }
    final replyId = draft.replyToMessageId;
    if (replyId != null && replyId > 0 && _replyTo == null) {
      ChatMessage? target;
      for (final m in _messages) {
        if (m.id == replyId) {
          target = m;
          break;
        }
      }
      if (target != null) {
        setState(() => _replyTo = target);
      } else {
        // Keep reply id until history loads; retry after messages arrive.
        _pendingDraftReplyId = replyId;
      }
    }
  }

  int? _pendingDraftReplyId;

  void _tryRestorePendingDraftReply() {
    final replyId = _pendingDraftReplyId;
    if (replyId == null || replyId <= 0 || _replyTo != null) return;
    for (final m in _messages) {
      if (m.id == replyId) {
        _pendingDraftReplyId = null;
        setState(() => _replyTo = m);
        return;
      }
    }
  }

  void _scheduleDraftSave() {
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persistDraftLocalAndCloud());
    });
  }

  Future<void> _persistDraftLocalAndCloud() async {
    final text = _controller.text;
    final replyId = _replyTo?.id;
    await ChatCacheService.saveDraft(
      widget.conversationId,
      text,
      replyToMessageId: replyId,
    );
    try {
      final trimmed = text.trim();
      if (trimmed.isEmpty && (replyId == null || replyId <= 0)) {
        await ChatService.deleteCloudDraft(
          conversationId: widget.conversationId,
        );
      } else {
        final cloud = await ChatService.upsertCloudDraft(
          conversationId: widget.conversationId,
          text: trimmed,
          replyToMessageId: replyId,
        );
        if (cloud != null) {
          await ChatCacheService.saveDraft(
            widget.conversationId,
            cloud.text,
            replyToMessageId: cloud.replyToMessageId,
            updatedAt: cloud.updatedAt,
          );
        }
      }
    } catch (_) {
      // Local draft remains; cloud sync is best-effort.
    }
  }

  void _onComposerFocusChanged() {
    if (!_inputFocusNode.hasFocus) {
      _hideBotAutocompleteOverlay();
    } else {
      _scrollToBottomAfterKeyboard();
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      if (keyboard > 0 && (_inputFocusNode.hasFocus || _isNearBottom())) {
        _scrollToBottomAfterKeyboard();
      }
    });
  }

  void _onScrollChanged() {
    if (!_scroll.hasClients || _selectionMode) return;
    final nearBottom = _isNearBottom();
    if (nearBottom) {
      if (_showJumpToBottom ||
          _jumpFabTargetsUnread ||
          _unreadMentionQueue.isNotEmpty ||
          _unreadReactionQueue.isNotEmpty) {
        setState(() {
          _showJumpToBottom = false;
          _jumpFabTargetsUnread = false;
          _newMessagesBelow = 0;
          _clearUnreadMentionQueue();
          _clearUnreadReactionQueue();
        });
      }
      // Telegram: mark read when the user actually reaches the bottom.
      _scheduleMarkRead();
    } else {
      final targetsUnread = _shouldJumpToFirstUnread() ||
          _hasMentionJumpTargets ||
          _hasReactionJumpTargets;
      if (!_showJumpToBottom || _jumpFabTargetsUnread != targetsUnread) {
        setState(() {
          _showJumpToBottom = true;
          _jumpFabTargetsUnread = targetsUnread;
        });
      }
    }
    // Auto-load older history near the top (Telegram infinite scroll).
    if (_hasMore &&
        !_loadingMore &&
        !_loading &&
        _scroll.position.pixels < 140) {
      unawaited(_load(refresh: false));
    }
    _updateFloatingDateFromScroll();
  }

  void _updateFloatingDateFromScroll() {
    final messages = _visibleMessages;
    if (messages.isEmpty || !_scroll.hasClients) return;
    final threshold =
        MediaQuery.paddingOf(context).top + kToolbarHeight + 72;
    String? label;
    for (final msg in messages) {
      final ctx = _messageItemKeys[msg.id]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y <= threshold) {
        label = _chatDateSeparatorLabel(msg.createdAt);
      } else if (label != null) {
        break;
      }
    }
    label ??= _chatDateSeparatorLabel(messages.first.createdAt);
    final changed =
        label != _floatingDateLabel || !_floatingDateVisible;
    if (changed) {
      setState(() {
        _floatingDateLabel = label;
        _floatingDateVisible = true;
      });
    } else {
      _floatingDateVisible = true;
    }
    _floatingDateHideTimer?.cancel();
    _floatingDateHideTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() => _floatingDateVisible = false);
    });
  }

  void _clearTypingState() {
    for (final t in _typingUserTimers.values) {
      t.cancel();
    }
    _typingUserTimers.clear();
    _typingUserIds.clear();
    _typingActivityByUser.clear();
    _peerTyping = false;
  }

  void _onPeerTyping(int? userId, {String activity = 'typing'}) {
    final myId = AuthService.instance.currentUser?.id;
    if (userId != null && userId == myId) return;
    final key = userId ?? 0;
    final kind = activity == 'recording' ? 'recording' : 'typing';
    setState(() {
      _typingUserIds.add(key);
      _typingActivityByUser[key] = kind;
      _peerTyping = true;
    });
    _typingUserTimers[key]?.cancel();
    _typingUserTimers[key] = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _typingUserIds.remove(key);
        _typingActivityByUser.remove(key);
        _peerTyping = _typingUserIds.isNotEmpty;
      });
      _typingUserTimers.remove(key);
    });
  }

  void _startRecordingPresence() {
    _recordingPresenceTimer?.cancel();
    unawaited(
      ChatService.sendTyping(
        conversationId: widget.conversationId,
        activity: 'recording',
      ),
    );
    _recordingPresenceTimer =
        Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(
        ChatService.sendTyping(
          conversationId: widget.conversationId,
          activity: 'recording',
        ),
      );
    });
  }

  void _stopRecordingPresence() {
    _recordingPresenceTimer?.cancel();
    _recordingPresenceTimer = null;
  }

  String? _displayNameForUserId(int id) {
    final mapped = _senderNames[id]?.trim();
    if (mapped != null && mapped.isNotEmpty) return mapped;
    for (final m in _groupMembers) {
      if (m.id == id) {
        final name = m.displayName.trim();
        if (name.isNotEmpty) return name;
      }
    }
    for (final m in _conversation.membersPreview) {
      if (m.id == id) {
        final name = m.displayName.trim();
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  bool get _anyPeerRecording =>
      _typingActivityByUser.values.any((a) => a == 'recording');

  String _typingSubtitleLabel({required bool isGroup}) {
    if (!_peerTyping) return '';
    final recording = _anyPeerRecording;
    if (!isGroup) {
      return recording ? 'записывает голосовое' : 'печатает';
    }
    final names = <String>[];
    for (final id in _typingUserIds) {
      if (id == 0) continue;
      final name = _displayNameForUserId(id);
      if (name == null || name.isEmpty) continue;
      names.add(name.split(' ').first);
    }
    if (recording) {
      if (names.isEmpty) return 'записывает голосовое';
      if (names.length == 1) return '${names.first} записывает голосовое';
      return '${names.length} записывают голосовое';
    }
    if (names.isEmpty) return 'печатает';
    if (names.length == 1) return '${names.first} печатает';
    if (names.length == 2) {
      return '${names[0]} и ${names[1]} печатают';
    }
    return '${names.length} печатают';
  }

  Widget _unreadMessagesSeparator() {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.primary.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Непрочитанные сообщения',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(height: 1, color: line)),
        ],
      ),
    );
  }

  (IconData icon, Color color) _outgoingStatusVisual({
    required bool isPending,
    required bool isFailed,
    required bool isDelivered,
    required bool isRead,
    required Color fg,
    required ColorScheme scheme,
    bool onMedia = false,
  }) {
    if (isFailed) {
      return (
        Icons.error_outline,
        onMedia ? Colors.white : scheme.error,
      );
    }
    if (isPending) {
      return (
        Icons.access_time,
        onMedia
            ? Colors.white.withValues(alpha: 0.85)
            : fg.withValues(alpha: 0.55),
      );
    }
    if (isRead) {
      return (
        Icons.done_all,
        onMedia ? Colors.white.withValues(alpha: 0.95) : scheme.primary,
      );
    }
    if (isDelivered) {
      // Telegram gray double-check = delivered, not yet read.
      return (
        Icons.done_all,
        onMedia
            ? Colors.white.withValues(alpha: 0.78)
            : fg.withValues(alpha: 0.55),
      );
    }
    return (
      Icons.done,
      onMedia
          ? Colors.white.withValues(alpha: 0.7)
          : fg.withValues(alpha: 0.45),
    );
  }

  bool _isNearBottom([double threshold = 120]) {
    if (!_scroll.hasClients) return true;
    return _scroll.position.maxScrollExtent - _scroll.offset <= threshold;
  }

  int? _firstUnreadMessageId() {
    final unread = _conversation.unreadCount;
    if (unread <= 0 || _messages.isEmpty) return null;
    var remaining = unread;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (!_messages[i].isMine) {
        remaining--;
        if (remaining <= 0) return _messages[i].id;
      }
    }
    return _messages.first.id;
  }

  bool _messageMentionsMe(ChatMessage msg) {
    final me = AuthService.instance.currentUser;
    if (me == null) return false;
    return messageContentMentionsUser(
      content: msg.content,
      isMine: msg.isMine,
      userId: me.id,
      username: me.username,
      amIGroupAdmin: _conversation.amIGroupAdmin,
    );
  }

  int get _remainingMentionJumps =>
      remainingMentionJumps(_unreadMentionQueue, _unreadMentionCursor);

  bool get _hasMentionJumpTargets => _remainingMentionJumps > 0;

  int get _remainingReactionJumps =>
      remainingReactionJumps(_unreadReactionQueue, _unreadReactionCursor);

  bool get _hasReactionJumpTargets => _remainingReactionJumps > 0;

  List<int> _collectUnreadMentionIds({int? fromMessageId}) {
    final me = AuthService.instance.currentUser;
    if (me == null || _messages.isEmpty) return const [];
    final startId =
        fromMessageId ?? _unreadDividerBeforeId ?? _firstUnreadMessageId();
    return collectMentionMessageIds(
      messages: [
        for (final m in _messages)
          (id: m.id, content: m.content, isMine: m.isMine),
      ],
      fromMessageId: startId,
      userId: me.id,
      username: me.username,
      amIGroupAdmin: _conversation.amIGroupAdmin,
    );
  }

  void _seedUnreadMentionQueue({int? fromMessageId}) {
    final ids = _collectUnreadMentionIds(fromMessageId: fromMessageId);
    _unreadMentionQueue = ids;
    _unreadMentionCursor = 0;
  }

  void _clearUnreadMentionQueue() {
    _unreadMentionQueue = const [];
    _unreadMentionCursor = 0;
  }

  int? _firstUnreadMentionMessageId() {
    if (_hasMentionJumpTargets) {
      return _unreadMentionQueue[_unreadMentionCursor];
    }
    final ids = _collectUnreadMentionIds();
    return ids.isEmpty ? null : ids.first;
  }

  List<int> _collectUnreadReactionIds({int? fromMessageId}) {
    if (_messages.isEmpty) return const [];
    return collectReactionMessageIds(
      messages: [
        for (final m in _messages)
          (
            id: m.id,
            isMine: m.isMine,
            hasReactions: m.reactions.isNotEmpty,
          ),
      ],
      fromMessageId: fromMessageId,
    );
  }

  void _seedUnreadReactionQueue({int? fromMessageId}) {
    final ids = _collectUnreadReactionIds(fromMessageId: fromMessageId);
    _unreadReactionQueue = ids;
    _unreadReactionCursor = 0;
  }

  void _clearUnreadReactionQueue() {
    _unreadReactionQueue = const [];
    _unreadReactionCursor = 0;
  }

  int? _firstUnreadReactionMessageId() {
    if (_hasReactionJumpTargets) {
      return _unreadReactionQueue[_unreadReactionCursor];
    }
    if (_conversation.unreadReactionsCount <= 0 || _messages.isEmpty) {
      return null;
    }
    final ids = _collectUnreadReactionIds();
    return ids.isEmpty ? null : ids.first;
  }

  void _scrollAfterInitialLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_pendingInitialJumpMessageId != null) {
        unawaited(_jumpToInitialMessageIfNeeded());
        return;
      }
      final firstUnread = _firstUnreadMessageId();
      if (firstUnread != null) {
        _seedUnreadMentionQueue(fromMessageId: firstUnread);
        if (_conversation.unreadReactionsCount > 0) {
          _seedUnreadReactionQueue();
        }
        final mentionId = _firstUnreadMentionMessageId();
        final reactionId =
            mentionId == null ? _firstUnreadReactionMessageId() : null;
        // First mention/reaction is shown on open; next FAB tap advances further.
        if (mentionId != null && _unreadMentionQueue.isNotEmpty) {
          _unreadMentionCursor = 1;
        } else if (reactionId != null && _unreadReactionQueue.isNotEmpty) {
          _unreadReactionCursor = 1;
        }
        setState(() => _unreadDividerBeforeId = firstUnread);
        _scrollToMessage(mentionId ?? reactionId ?? firstUnread);
        final idx = _messages.indexWhere((m) => m.id == firstUnread);
        final below = idx >= 0 ? _messages.length - idx - 1 : 0;
        if (below > 0 ||
            _hasMentionJumpTargets ||
            _hasReactionJumpTargets) {
          setState(() {
            _newMessagesBelow = below;
            _showJumpToBottom = true;
            _jumpFabTargetsUnread = true;
          });
        }
      } else {
        if (_conversation.unreadReactionsCount > 0) {
          _seedUnreadReactionQueue();
        }
        final reactionId = _firstUnreadReactionMessageId();
        if (reactionId != null) {
          // First reaction is shown on open; next FAB tap advances further.
          if (_unreadReactionQueue.isNotEmpty) {
            _unreadReactionCursor = 1;
          }
          _scrollToMessage(reactionId);
          _focusMessageTemporarily(reactionId);
          setState(() {
            _showJumpToBottom = true;
            _jumpFabTargetsUnread = _hasReactionJumpTargets;
          });
        } else {
          _scrollToBottom();
          _scheduleMarkRead();
        }
      }
    });
  }

  void _focusMessageTemporarily(int messageId) {
    _focusedMessageTimer?.cancel();
    if (!mounted) return;
    setState(() => _focusedMessageId = messageId);
    _focusedMessageTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _focusedMessageId != messageId) return;
      setState(() => _focusedMessageId = null);
    });
  }

  Future<void> _jumpToInitialMessageIfNeeded() async {
    final targetId = _pendingInitialJumpMessageId;
    if (targetId == null || !mounted) return;

    if (_messages.any((m) => m.id == targetId)) {
      _pendingInitialJumpMessageId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToMessage(targetId);
        _focusMessageTemporarily(targetId);
      });
      return;
    }

    var attempts = 0;
    while (mounted && _hasMore && attempts < 8) {
      attempts++;
      await _load(refresh: false);
      if (_messages.any((m) => m.id == targetId)) {
        _pendingInitialJumpMessageId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToMessage(targetId);
          _focusMessageTemporarily(targetId);
        });
        return;
      }
    }

    _pendingInitialJumpMessageId = null;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сообщение не найдено в истории чата')),
    );
  }

  void _jumpToBottomAndMarkRead() {
    _scrollToBottom();
    setState(() {
      _showJumpToBottom = false;
      _jumpFabTargetsUnread = false;
      _newMessagesBelow = 0;
      _suppressMarkRead = false;
      _unreadDividerBeforeId = null;
      _clearUnreadMentionQueue();
      _clearUnreadReactionQueue();
    });
    _scheduleMarkRead();
  }

  /// True when the unread divider sits below the viewport (user scrolled up).
  bool _shouldJumpToFirstUnread() {
    final id = _unreadDividerBeforeId;
    if (id == null) return false;
    final ctx = _messageItemKeys[id]?.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        final y = box.localToGlobal(Offset.zero).dy;
        final screenH = MediaQuery.sizeOf(context).height;
        return y > screenH - 120;
      }
    }
    if (!_scroll.hasClients || _messages.length <= 1) return false;
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx < 0) return false;
    final fraction = idx / (_messages.length - 1);
    final unreadApprox = _scroll.position.maxScrollExtent * fraction;
    return _scroll.offset + 160 < unreadApprox;
  }

  void _onJumpFabTap() {
    // Telegram: @ FAB cycles through unread mentions even after mark-read.
    if (_unreadMentionQueue.isEmpty &&
        (_conversation.unreadMentionsCount > 0 ||
            _unreadDividerBeforeId != null)) {
      _seedUnreadMentionQueue();
    }
    if (_hasMentionJumpTargets) {
      final id = _unreadMentionQueue[_unreadMentionCursor];
      setState(() {
        _unreadMentionCursor += 1;
        _showJumpToBottom = true;
        _jumpFabTargetsUnread = true;
      });
      _scrollToMessage(id);
      _focusMessageTemporarily(id);
      return;
    }
    // Telegram: ❤ FAB cycles through unread reactions even after mark-read.
    if (_unreadReactionQueue.isEmpty &&
        _conversation.unreadReactionsCount > 0) {
      _seedUnreadReactionQueue();
    }
    if (_hasReactionJumpTargets) {
      final id = _unreadReactionQueue[_unreadReactionCursor];
      setState(() {
        _unreadReactionCursor += 1;
        _showJumpToBottom = true;
        _jumpFabTargetsUnread =
            _hasReactionJumpTargets || _unreadDividerBeforeId != null;
      });
      _scrollToMessage(id);
      _focusMessageTemporarily(id);
      return;
    }
    if (_jumpFabTargetsUnread && _unreadDividerBeforeId != null) {
      final id = _unreadDividerBeforeId!;
      _scrollToMessage(id);
      _focusMessageTemporarily(id);
      return;
    }
    _jumpToBottomAndMarkRead();
  }

  bool _isSameChatDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  DateTime _dateOnly(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  int? _messageIdForJumpDate(DateTime targetDay) {
    if (_messages.isEmpty) return null;
    for (final msg in _messages) {
      if (_isSameChatDay(msg.createdAt, targetDay)) return msg.id;
    }
    for (final msg in _messages) {
      final day = _dateOnly(msg.createdAt);
      if (day.isAfter(targetDay)) return msg.id;
    }
    return _messages.last.id;
  }

  Future<void> _pickAndJumpToDate() async {
    if (_jumpingToDate) return;
    if (_messages.isEmpty && !_loading) {
      await _load(refresh: true);
      if (!mounted || _messages.isEmpty) return;
    }
    if (!mounted || _messages.isEmpty) return;
    final now = DateTime.now();
    final oldest = _dateOnly(_messages.first.createdAt);
    final firstDate = oldest.isBefore(now)
        ? oldest
        : now.subtract(const Duration(days: 3650));
    final lastDate = _dateOnly(now);
    final initialCandidate = _dateOnly(_messages.last.createdAt);
    final initialDate = initialCandidate.isAfter(lastDate)
        ? lastDate
        : initialCandidate.isBefore(firstDate)
            ? firstDate
            : initialCandidate;
    final picked = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: initialDate,
      helpText: 'Перейти к дате',
    );
    if (picked == null || !mounted) return;
    await _jumpToDate(picked);
  }

  Future<void> _jumpToDate(DateTime picked) async {
    if (_jumpingToDate) return;
    final targetDay = _dateOnly(picked);
    setState(() => _jumpingToDate = true);
    try {
      var attempts = 0;
      while (mounted &&
          _messages.isNotEmpty &&
          _hasMore &&
          attempts < 12 &&
          _dateOnly(_messages.first.createdAt).isAfter(targetDay)) {
        if (_loading || _loadingMore) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          continue;
        }
        attempts++;
        await _load(refresh: false);
      }
      if (!mounted || _messages.isEmpty) return;
      final messageId = _messageIdForJumpDate(targetDay);
      if (messageId == null) return;
      _scrollToMessage(messageId);
    } finally {
      if (mounted) setState(() => _jumpingToDate = false);
    }
  }

  String _chatDateSeparatorLabel(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    if (_isSameChatDay(local, now)) return 'Сегодня';
    if (_isSameChatDay(local, now.subtract(const Duration(days: 1)))) {
      return 'Вчера';
    }
    try {
      return DateFormat('d MMMM yyyy', 'ru').format(local);
    } catch (_) {
      return DateFormat('d MMMM yyyy').format(local);
    }
  }

  Widget _chatDateSeparator(DateTime date) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => unawaited(_pickAndJumpToDate()),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.28)
                  : Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _chatDateSeparatorLabel(date),
              style: TextStyle(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.92)
                    : scheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _startEdit(ChatMessage msg) {
    setState(() {
      _editingMessage = msg;
      _replyTo = null;
      _controller.text = msg.content;
      _controller.selection =
          TextSelection.collapsed(offset: msg.content.length);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _controller.clear();
    });
  }

  Future<void> _toggleReaction(ChatMessage msg, String emoji) async {
    if (msg.id <= 0) return;
    final previous = msg.reactions;
    final optimistic = optimisticToggleReactions(
      current: previous,
      emoji: emoji,
    );
    _applyReactions(msg.id, optimistic);
    final existing = previous.where((r) => r.reactedByMe);
    final myEmoji = existing.isEmpty ? null : existing.first.emoji;
    try {
      final reactions = myEmoji == emoji
          ? await ChatService.removeReaction(
              conversationId: widget.conversationId,
              messageId: msg.id,
            )
          : await ChatService.setReaction(
              conversationId: widget.conversationId,
              messageId: msg.id,
              emoji: emoji,
            );
      if (!mounted) return;
      _applyReactions(msg.id, reactions);
    } catch (e) {
      if (!mounted) return;
      _applyReactions(msg.id, previous);
      if (offerFlexIfRequired(context, e)) return;
      if (offerPackStoreIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _sendPaidReaction(ChatMessage msg) async {
    if (msg.isMine || msg.id <= 0 || _sendingPaidReaction) return;
    final amount = await pickPaidReactionStars(context);
    if (amount == null || !mounted) return;
    final ok = await confirmStarsSpend(
      context,
      title: 'Платная реакция',
      body: 'Отправить $amount ★ за реакцию на это сообщение?',
      amountStars: amount,
      confirmLabel: 'Отправить',
    );
    if (!ok || !mounted) return;
    final previous = msg.reactions;
    _applyReactions(
      msg.id,
      optimisticToggleReactions(current: previous, emoji: '⭐'),
    );
    setState(() => _sendingPaidReaction = true);
    final idem = 'flutter:react:${msg.id}:${const Uuid().v4()}';
    try {
      final reactions = await ChatService.setReaction(
        conversationId: widget.conversationId,
        messageId: msg.id,
        emoji: '⭐',
        stars: amount,
        idempotencyKey: idem,
      );
      if (!mounted) return;
      _applyReactions(msg.id, reactions);
    } catch (e) {
      if (!mounted) return;
      _applyReactions(msg.id, previous);
      await showStarsRequiredSnack(context, e);
    } finally {
      if (mounted) setState(() => _sendingPaidReaction = false);
    }
  }

  Future<void> _togglePinMessage(ChatMessage msg) async {
    final isPinned = _isMessagePinned(msg.id);
    var notifyMembers = false;
    if (!isPinned && _conversation.isGroup) {
      var notify = true; // Telegram default: notify members when pinning.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Закрепить сообщение?'),
            content: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: notify,
              onChanged: (v) => setLocal(() => notify = v ?? false),
              title: const Text('Уведомить участников'),
              subtitle: const Text(
                'Участники получат уведомление о закреплении',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Закрепить'),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
      notifyMembers = notify;
    }
    setState(() {
      if (isPinned) {
        _removePinnedMessageId(msg.id);
      } else {
        _upsertPinnedMessage(msg);
      }
    });
    try {
      await ChatService.pinMessage(
        conversationId: widget.conversationId,
        messageId: msg.id,
        pinned: !isPinned,
        notify: notifyMembers,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isPinned) {
          _upsertPinnedMessage(msg);
        } else {
          _removePinnedMessageId(msg.id);
        }
      });
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _unpinAllMessages() async {
    if (_pinnedMessages.isEmpty) return;
    final previous = List<ChatMessage>.from(_pinnedMessages);
    setState(() => _setPinnedMessages(const []));
    try {
      await ChatService.clearPinnedMessages(
        conversationId: widget.conversationId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _setPinnedMessages(previous));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _showPinnedMessagesSheet() async {
    if (_pinnedMessages.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final items = List<ChatMessage>.from(_pinnedMessages);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Закреплённые (${items.length})',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    if (items.length > 1)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          unawaited(_unpinAllMessages());
                        },
                        child: const Text('Открепить все'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final msg = items[i];
                      return ListTile(
                        leading: _pinnedMediaLeading(msg) ??
                            Icon(
                              msg.type == 'voice'
                                  ? Icons.mic_rounded
                                  : msg.type == 'file'
                                      ? Icons.insert_drive_file_outlined
                                      : Icons.push_pin_outlined,
                            ),
                        title: Text(
                          _pinnedPreview(msg),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'Открепить',
                          icon: const Icon(Icons.push_pin_outlined),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _togglePinMessage(msg);
                          },
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(_jumpToPinnedMessage(msg));
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _freeChatReactions = [
    '👍',
    '👌',
    '❤️',
    '👎',
    '👏',
    '😂',
    '😮',
    '😢',
    '🙏',
  ];
  static const _extraReactionGrid = [
    '😊',
    '😍',
    '🤣',
    '😎',
    '🤔',
    '😴',
    '😇',
    '🤗',
    '🫡',
    '😭',
    '😡',
    '🤮',
    '💀',
    '👀',
    '🙈',
    '💪',
    '🤝',
    '✌️',
    '👋',
    '💋',
    '💔',
    '🌹',
    '🎂',
    '🎁',
    '🏆',
    '⚽️',
    '🎵',
    '📱',
    '✅',
    '❌',
    '⭐',
    '🌟',
    '🌈',
    '☀️',
    '🌙',
    '🍀',
    '🐶',
    '🐱',
    '🍕',
    '☕',
  ];

  List<String> get _reactionPickerEmojis {
    final seen = <String>{};
    final out = <String>[];
    for (final emoji in [
      ..._quickReactions,
      ..._freeChatReactions,
      ..._exclusiveOverlayReactions,
      ..._extraReactionGrid,
    ]) {
      if (seen.add(emoji)) out.add(emoji);
    }
    return out;
  }

  bool _canUseReactionEmoji(String emoji) {
    final customId = parseCustomEmojiTokenId(emoji);
    if (customId != null) {
      if (!_hasFlexFeature('custom_emoji_reactions')) return false;
      return _customReactionEmojis.any((e) => e.id == customId);
    }
    if (_freeChatReactions.contains(emoji)) return true;
    if (_exclusiveOverlayReactions.contains(emoji)) {
      return _hasFlexFeature('exclusive_reactions') ||
          _hasFlexFeature('any_emoji_reactions');
    }
    return _hasFlexFeature('any_emoji_reactions');
  }

  Future<void> _pickReactionEmoji(ChatMessage msg, String emoji) async {
    final customId = parseCustomEmojiTokenId(emoji);
    if (customId != null) {
      if (!_hasFlexFeature('custom_emoji_reactions')) {
        await showCreatorUpsell(context);
        return;
      }
      await _ensureCustomReactionEmojis();
      if (!_customReactionEmojis.any((e) => e.id == customId)) {
        offerPackStoreIfRequired(context, 'pack_purchase_required');
        return;
      }
    } else if (!_canUseReactionEmoji(emoji)) {
      await showCreatorUpsell(context);
      return;
    }
    await _toggleReaction(msg, emoji);
  }

  List<CustomEmojiItem> _customReactionEmojis = const [];

  Future<void> _ensureCustomReactionEmojis() async {
    if (_customReactionEmojis.isNotEmpty) return;
    try {
      final packs = await EmojiPackService.listMyPacks();
      _customReactionEmojis = [
        for (final pack in packs)
          if (pack.canUse) ...pack.items,
      ];
    } catch (_) {}
  }

  Future<void> _showReactionPicker(ChatMessage msg) async {
    await _ensureCustomReactionEmojis();
    if (!mounted) return;
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Реакция',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._reactionPickerEmojis,
                      for (final item in _customReactionEmojis)
                        customEmojiReaction(item.id),
                    ].map((emoji) {
                      final locked = !_canUseReactionEmoji(emoji);
                      return Material(
                        color: msg.reactions.any(
                          (r) => r.reactedByMe && r.emoji == emoji,
                        )
                            ? Theme.of(ctx).colorScheme.primaryContainer
                            : Theme.of(ctx)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_pickReactionEmoji(msg, emoji));
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Opacity(
                                  opacity: locked ? 0.45 : 1,
                                  child: ReactionEmojiView(
                                    token: emoji,
                                    size: 26,
                                  ),
                                ),
                                if (locked)
                                  const Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Icon(Icons.lock, size: 12),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: _hasFlexFeature('any_emoji_reactions')
                      ? 'Вставьте любой эмодзи'
                      : 'Любой эмодзи — с уровня 37',
                  suffixIcon: IconButton(
                    tooltip: 'Поставить',
                    icon: const Icon(Icons.send_rounded),
                    onPressed: () {
                      final emoji = controller.text.trim();
                      if (emoji.isEmpty) return;
                      Navigator.pop(ctx);
                      unawaited(_pickReactionEmoji(msg, emoji));
                    },
                  ),
                ),
                onSubmitted: (value) {
                  final emoji = value.trim();
                  if (emoji.isEmpty) return;
                  Navigator.pop(ctx);
                  unawaited(_pickReactionEmoji(msg, emoji));
                },
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  void _showThreadActionsSheet() {
    final isGroup = _conversation.isGroup;
    final isSaved = _conversation.isSaved;
    final peer = _conversation.peer;
    final mediaCount = _messages.where((m) => m.mediaUrl != null).length;
    final manualReadyRetryRemaining = _manualReadyRetryRemainingSeconds;
    final nextReadyRemaining = _nextManualRetryRemainingSeconds;
    final hasManualRetryControls =
        !_autoRetryOnLimitsEnabled && _hasFailedPendingItems;
    final readyManualRetryCount = hasManualRetryControls
        ? readyManualRetryItems<_ManualRetryTask>(
            _buildManualRetryTasks(),
            (t) => t.remainingSeconds,
          ).length
        : 0;

    showTelegramActionSheet<void>(
      context: context,
      title: 'Действия',
      actions: [
        TelegramActionSheetAction(
          icon: _threadSearchOpen ? Icons.search_off : Icons.search,
          title: _threadSearchOpen ? 'Закрыть поиск' : 'Поиск в чате',
          onTap: _toggleThreadSearch,
        ),
        TelegramActionSheetAction(
          icon: _showOnlyFailedMessages
              ? Icons.filter_alt_off_outlined
              : Icons.filter_alt_outlined,
          title: _showOnlyFailedMessages
              ? 'Показывать все сообщения'
              : 'Только неотправленные',
          onTap: () => _setShowOnlyFailedMessages(!_showOnlyFailedMessages),
        ),
        TelegramActionSheetAction(
          icon: Icons.calendar_today_outlined,
          title: _jumpingToDate ? 'Переход к дате…' : 'Перейти к дате',
          onTap: () => unawaited(_pickAndJumpToDate()),
        ),
        TelegramActionSheetAction(
          icon: Icons.wallpaper_outlined,
          title: 'Обои чата',
          onTap: () => unawaited(_showWallpaperPicker()),
        ),
        TelegramActionSheetAction(
          icon: _conversation.autoTranslate
              ? Icons.translate
              : Icons.translate_outlined,
          title: _conversation.autoTranslate
              ? 'Автоперевод включён'
              : 'Автоперевод чата',
          onTap: () => unawaited(_toggleAutoTranslate()),
        ),
        TelegramActionSheetAction(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Цвет пузырей',
          onTap: () => unawaited(_showBubbleAccentPicker()),
        ),
        if (!isSaved)
          TelegramActionSheetAction(
            icon: Icons.ios_share_outlined,
            title: 'Экспорт чата',
            onTap: () => unawaited(_exportChat()),
          ),
        if (!isGroup)
          TelegramActionSheetAction(
            icon: Icons.auto_delete_outlined,
            title: _conversation.autoDeleteSeconds <= 0
                ? 'Автоудаление'
                : 'Автоудаление: ${_autoDeleteLabel(_conversation.autoDeleteSeconds)}',
            onTap: () => unawaited(_configureAutoDelete()),
          ),
        TelegramActionSheetAction(
          icon: _autoRetryOnLimitsEnabled
              ? Icons.autorenew_rounded
              : Icons.autorenew_outlined,
          title: _autoRetryOnLimitsEnabled
              ? 'Автоповтор при лимитах: вкл'
              : 'Автоповтор при лимитах: выкл',
          onTap: () => unawaited(
              _toggleAutoRetryOnLimitsInThread(!_autoRetryOnLimitsEnabled)),
        ),
        if (hasManualRetryControls)
          TelegramActionSheetAction(
            icon: Icons.playlist_add_check_circle_outlined,
            title: readyManualRetryCount > 0
                ? 'Повторить готовые ($readyManualRetryCount)'
                : 'Повторить готовые',
            onTap: () {
              if (_sending || _retryAllBulkBusy) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Сейчас идет отправка. Повторите действие чуть позже.',
                    ),
                  ),
                );
                return;
              }
              unawaited(_retryReadyFailedPending());
            },
          ),
        if (hasManualRetryControls)
          TelegramActionSheetAction(
            icon: Icons.refresh_rounded,
            title: 'Повторить все',
            onTap: () {
              if (_sending || _retryAllBulkBusy) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Сейчас идет отправка. Повторите действие чуть позже.',
                    ),
                  ),
                );
                return;
              }
              unawaited(_retryAllFailedPendingWithGuard());
            },
          ),
        if (_retryAllBulkBusy)
          TelegramActionSheetAction(
            icon: Icons.stop_circle_outlined,
            title: _clearAllAfterBulkStopRequested
                ? 'Остановить и очистить...'
                : _retryAllBulkCancelRequested
                    ? 'Останавливаем пакетный повтор...'
                    : 'Остановить пакетный повтор',
            onTap: _cancelRetryAllBulk,
          ),
        if (hasManualRetryControls)
          TelegramActionSheetAction(
            icon: Icons.delete_sweep_outlined,
            title: 'Очистить неотправленные',
            destructive: true,
            onTap: () {
              if (_retryAllBulkBusy) {
                _requestClearAfterBulkStop();
                return;
              }
              unawaited(_clearAllFailedPending());
            },
          ),
        if (!_autoRetryOnLimitsEnabled && _hasFailedPendingItems)
          if (manualReadyRetryRemaining > 0)
            TelegramActionSheetAction(
              icon: Icons.alarm_off_outlined,
              title:
                  'Отменить автозапуск (${_formatSlowModeCountdown(manualReadyRetryRemaining)})',
              onTap: _cancelManualReadyRetrySchedule,
            )
          else if (nextReadyRemaining != null && nextReadyRemaining > 0)
            TelegramActionSheetAction(
              icon: Icons.alarm_add_outlined,
              title:
                  'Автозапуск готовых через ${_formatSlowModeCountdown(nextReadyRemaining)}',
              onTap: () => _scheduleManualReadyRetry(nextReadyRemaining),
            ),
        if (mediaCount > 0)
          TelegramActionSheetAction(
            icon: Icons.photo_library_outlined,
            title: 'Медиа ($mediaCount)',
            onTap: _openMediaGallery,
          ),
        if (!isGroup && peer != null) ...[
          TelegramActionSheetAction(
            icon: Icons.stars_rounded,
            title: 'Отправить звёзды',
            onTap: _tipPeerWithStars,
          ),
          TelegramActionSheetAction(
            icon: Icons.card_giftcard_rounded,
            title: 'Отправить подарок',
            onTap: _sendStarGift,
          ),
        ],
        if ((!isGroup && peer != null) ||
            (isGroup && _canManageGroupCalls)) ...[
          TelegramActionSheetAction(
            icon: Icons.videocam_outlined,
            title: isGroup ? 'Групповой видеозвонок' : 'Видеозвонок',
            onTap: () => unawaited(_startVideoCall()),
          ),
          TelegramActionSheetAction(
            icon: Icons.call_outlined,
            title: isGroup ? 'Групповой звонок' : 'Аудиозвонок',
            onTap: () => unawaited(_startVoiceCall()),
          ),
        ],
        if (!isSaved) ...[
          TelegramActionSheetAction(
            icon: _pinned ? Icons.push_pin : Icons.push_pin_outlined,
            title: _pinned ? 'Открепить' : 'Закрепить',
            onTap: _togglePin,
          ),
          TelegramActionSheetAction(
            icon: _muted
                ? Icons.notifications_off_outlined
                : Icons.notifications_outlined,
            title: _muted ? 'Включить уведомления' : 'Без звука',
            onTap: _toggleMute,
          ),
          if (isGroup)
            TelegramActionSheetAction(
              icon: Icons.info_outline,
              title: 'О группе',
              onTap: _openGroupInfo,
            ),
          if (!isGroup && !isSaved && peer != null) ...[
            TelegramActionSheetAction(
              icon: Icons.flag_outlined,
              title: 'Пожаловаться',
              onTap: () => unawaited(reportUserWithDialog(context, peer.id)),
            ),
            TelegramActionSheetAction(
              icon: _conversation.peerBlockedByMe
                  ? Icons.lock_open_outlined
                  : Icons.block_outlined,
              title: _conversation.peerBlockedByMe
                  ? 'Разблокировать'
                  : 'Заблокировать',
              destructive: !_conversation.peerBlockedByMe,
              onTap: _conversation.peerBlockedByMe ? _unblockPeer : _blockPeer,
            ),
          ],
          if (isGroup)
            TelegramActionSheetAction(
              icon: Icons.logout,
              title: 'Выйти из группы',
              destructive: true,
              onTap: _leaveGroup,
            ),
          TelegramActionSheetAction(
            icon: Icons.mark_chat_unread_outlined,
            title: 'Пометить непрочитанным',
            onTap: _markUnread,
          ),
          TelegramActionSheetAction(
            icon: Icons.archive_outlined,
            title: 'В архив',
            onTap: _archiveChat,
          ),
          if (!isSaved)
            TelegramActionSheetAction(
              icon: Icons.history_outlined,
              title: 'Очистить историю',
              destructive: true,
              onTap: _clearChatHistory,
            ),
          if (!isGroup)
            TelegramActionSheetAction(
              icon: Icons.delete_outline,
              title: 'Удалить чат',
              destructive: true,
              onTap: _deleteChat,
            ),
        ],
      ],
    );
  }

  void _applyDeliveredReceipt(int deliveredUpToId) {
    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        if (m.isMine && m.id <= deliveredUpToId && !m.isDelivered) {
          _messages[i] = m.copyWith(isDelivered: true);
        }
      }
    });
  }

  void _applyReadReceipt(int readUpToId, {int? readerId}) {
    if (_conversation.isGroup) {
      final prev =
          (readerId != null) ? (_peerGroupReadCursors[readerId] ?? 0) : 0;
      if (readerId != null) {
        final known = _peerGroupReadCursors[readerId] ?? 0;
        if (readUpToId <= known) return;
        _peerGroupReadCursors[readerId] = readUpToId;
      }
      final others = math.max(0, _conversation.memberCount - 1);
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final m = _messages[i];
          if (!m.isMine || m.id <= 0) continue;
          if (m.id <= prev || m.id > readUpToId) {
            if (m.id <= readUpToId && !m.isDelivered) {
              _messages[i] = m.copyWith(isDelivered: true);
            }
            continue;
          }
          final nextCount = m.readCount + 1;
          final allRead = others > 0 && nextCount >= others;
          _messages[i] = m.copyWith(
            readCount: nextCount,
            isDelivered: true,
            isRead: allRead || m.isRead,
          );
        }
      });
      return;
    }
    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        if (m.isMine && m.id <= readUpToId && (!m.isRead || !m.isDelivered)) {
          _messages[i] = m.copyWith(isRead: true, isDelivered: true);
        }
      }
    });
  }

  @override
  void dispose() {
    ChatVoicePlaybackCoordinator.instance.stopAll();
    ActiveChatSession.instance.clearIfOpen(widget.conversationId);
    _scroll.removeListener(_onScrollChanged);
    WidgetsBinding.instance.removeObserver(this);
    _floatingDateHideTimer?.cancel();
    _pollTimer?.cancel();
    _presenceTimer?.cancel();
    _autoDeleteTicker?.cancel();
    _typingDebounce?.cancel();
    _stopRecordingPresence();
    for (final t in _typingUserTimers.values) {
      t.cancel();
    }
    _typingUserTimers.clear();
    _typingUserIds.clear();
    _inlineDebounce?.cancel();
    _composerLinkDebounce?.cancel();
    _hideInlineOverlay();
    _markReadDebounce?.cancel();
    _markDeliveredDebounce?.cancel();
    _draftSaveDebounce?.cancel();
    _signalSub?.cancel();
    _presenceSub?.cancel();
    if (_apiReachabilityListener != null) {
      ApiReachabilityService.instance.isApiReachable
          .removeListener(_apiReachabilityListener!);
    }
    if (_apiConnectingListener != null) {
      ApiReachabilityService.instance.isApiConnecting
          .removeListener(_apiConnectingListener!);
    }
    if (_deviceOnlineListener != null && _deviceOnlineListenable != null) {
      _deviceOnlineListenable!.removeListener(_deviceOnlineListener!);
    }
    _holdActive = false;
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    unawaited(_stopRecorderSilently());
    _audioRecorder.dispose();
    _stream?.disconnect();
    _focusedMessageTimer?.cancel();
    _slowModeCountdownTimer?.cancel();
    _pendingMediaAutoRetryTimer?.cancel();
    _manualReadyRetryTimer?.cancel();
    _muteUnmuteTimer?.cancel();
    for (final t in _failedTextAutoRetryTimers.values) {
      t.cancel();
    }
    _failedTextAutoRetryTimers.clear();
    unawaited(_persistFailedTextSends());
    unawaited(_persistReadySends());
    unawaited(
      ChatCacheService.saveDraft(
        widget.conversationId,
        _controller.text,
        replyToMessageId: _replyTo?.id,
      ),
    );
    _controller.removeListener(_onInputChanged);
    _inputFocusNode.removeListener(_onComposerFocusChanged);
    _inputFocusNode.dispose();
    _controller.dispose();
    _threadSearchController.dispose();
    _threadSearchFocusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _openUserProfile(int userId) {
    if (userId <= 0) return;
    context.push(ProfileRoute.withUserId(userId));
  }

  void _openMentionProfile(String handle) {
    final username = handle.startsWith('@')
        ? handle.substring(1).toLowerCase()
        : handle.toLowerCase();
    if (username.isEmpty) return;
    final idMatch = RegExp(r'^id(\d+)$').firstMatch(username);
    if (idMatch != null) {
      final uid = int.tryParse(idMatch.group(1)!);
      if (uid != null && uid > 0) {
        _openUserProfile(uid);
        return;
      }
    }
    for (final member in _groupMembers) {
      final u = member.username?.trim().toLowerCase();
      if (u != null && u == username) {
        _openUserProfile(member.id);
        return;
      }
    }
    final peer = _conversation.peer;
    final peerUser = peer?.username?.trim().toLowerCase();
    if (peer != null && peerUser == username) {
      _openUserProfile(peer.id);
    }
  }

  Map<String, String> get _mentionLabels {
    final out = <String, String>{};
    for (final m in _groupMembers) {
      out['id${m.id}'] = m.displayName;
      final u = m.username?.trim();
      if (u != null && u.isNotEmpty) {
        final handle = u.startsWith('@') ? u.substring(1) : u;
        if (handle.isNotEmpty) out[handle] = m.displayName;
      }
    }
    final peer = _conversation.peer;
    if (peer != null) {
      out['id${peer.id}'] = peer.displayName;
      final u = peer.username?.trim();
      if (u != null && u.isNotEmpty) {
        final handle = u.startsWith('@') ? u.substring(1) : u;
        if (handle.isNotEmpty) out[handle] = peer.displayName;
      }
    }
    return out;
  }

  void _playNextVoiceAfter(ChatMessage finished) {
    if (finished.id <= 0) return;
    final idx = _messages.indexWhere((m) => m.id == finished.id);
    if (idx < 0) return;
    for (var i = idx + 1; i < _messages.length; i++) {
      final next = _messages[i];
      if (next.type == 'voice' &&
          next.id > 0 &&
          (next.mediaUrl?.trim().isNotEmpty ?? false)) {
        ChatVoicePlaybackCoordinator.instance.requestPlay(next.id);
        return;
      }
    }
  }

  Future<void> _messageContactUser(
    int userId, {
    ChatMessage? quoteFrom,
  }) async {
    if (userId <= 0) return;
    final peer = _conversation.peer;
    if (!_conversation.isGroup && peer?.id == userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы уже в этом чате')),
      );
      return;
    }
    try {
      final conv = await ChatOpenDirect.openNow(
        userId,
        peer: ChatUserBrief(
          id: userId,
          name: _senderNames[userId],
        ),
      );
      if (!mounted) return;
      if (conv.id == widget.conversationId ||
          (conv.peer?.id == userId &&
              !_conversation.isGroup &&
              _conversation.peer?.id == userId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы уже в этом чате')),
        );
        return;
      }
      ChatPrivateReplyQuote? privateReply;
      if (quoteFrom != null && quoteFrom.id > 0) {
        final who = (quoteFrom.senderName?.trim().isNotEmpty == true)
            ? quoteFrom.senderName!.trim()
            : (_senderNames[quoteFrom.senderId] ?? 'Участник');
        final body = _messagePreview(quoteFrom).trim();
        privateReply = ChatPrivateReplyQuote(
          sourceConversationId: widget.conversationId,
          sourceMessageId: quoteFrom.id,
          author: who,
          preview: body.isEmpty ? 'Сообщение' : body,
          sourceChatTitle: _conversation.displayTitle,
        );
      }
      await context.push(
        ChatThreadRoute.pathFor(conv),
        extra: ChatThreadOpenArgs(
          conversation: conv,
          initialPrivateReply: privateReply,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось открыть чат'),
          ),
        ),
      );
    }
  }

  void _openPeerProfile() {
    final peer = _conversation.peer;
    if (peer != null) _openUserProfile(peer.id);
  }

  Future<void> _onForwardAttributionTap(ChatMessage msg) async {
    final srcConvId = msg.forwardedFromConversationId;
    final srcMsgId = msg.forwardedFromMessageId;
    final canOpenOriginal = srcConvId != null &&
        srcConvId > 0 &&
        srcMsgId != null &&
        srcMsgId > 0;
    final canOpenProfile =
        msg.forwardFromUserId != null && msg.forwardFromUserId! > 0;
    if (!canOpenOriginal && !canOpenProfile) return;

    if (canOpenOriginal && !canOpenProfile) {
      await _openForwardedOriginal(
        conversationId: srcConvId,
        messageId: srcMsgId,
      );
      return;
    }
    if (!canOpenOriginal && canOpenProfile) {
      _openUserProfile(msg.forwardFromUserId!);
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canOpenOriginal)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('К оригиналу'),
                onTap: () => Navigator.pop(ctx, 'original'),
              ),
            if (canOpenProfile)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: HighlightedText(
                  text: msg.forwardFromName?.trim().isNotEmpty == true
                      ? msg.forwardFromName!.trim()
                      : 'Профиль',
                  style: Theme.of(context).textTheme.bodyLarge ??
                      const TextStyle(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(ctx, 'profile'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'original' && canOpenOriginal) {
      await _openForwardedOriginal(
        conversationId: srcConvId,
        messageId: srcMsgId,
      );
    } else if (action == 'profile' && canOpenProfile) {
      _openUserProfile(msg.forwardFromUserId!);
    }
  }

  Future<void> _openForwardedOriginal({
    required int conversationId,
    required int messageId,
  }) async {
    if (conversationId == widget.conversationId) {
      await _scrollToReplyMessage(messageId);
      if (mounted) _focusMessageTemporarily(messageId);
      return;
    }
    try {
      final conv = await ChatService.getConversation(conversationId);
      if (!mounted) return;
      unawaited(ChatThreadPrefetch.warm(conv.id));
      await context.push(
        ChatThreadRoute.pathFor(conv),
        extra: ChatThreadOpenArgs(
          conversation: conv,
          jumpToMessageId: messageId,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e).contains('403') ||
                    userVisibleError(e).toLowerCase().contains('access')
                ? 'Нет доступа к исходному чату'
                : userVisibleError(e),
          ),
        ),
      );
    }
  }

  Future<void> _openDirectChatInfo() async {
    final peer = _conversation.peer;
    if (peer == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AppUserAvatar(
                imageUrl: peer.avatarUrl,
                displayName: peer.displayName,
                radius: 22,
              ),
              title: HighlightedText(
                text: peer.displayName,
                style: Theme.of(context).textTheme.bodyLarge ??
                    const TextStyle(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                peer.isOnline
                    ? 'в сети'
                    : formatLastSeen(peer.lastSeenAt),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Медиа, файлы и ссылки'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_openMediaGallery());
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Профиль'),
              onTap: () {
                Navigator.pop(ctx);
                _openPeerProfile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Ссылка на профиль'),
              subtitle: Text(ShareLinkService.profileLink(peer.id)),
              onTap: () async {
                final text = ShareLinkService.profileShareText(
                  userId: peer.id,
                  displayName: peer.displayName,
                  username: peer.username,
                );
                await Clipboard.setData(ClipboardData(text: text));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ссылка скопирована')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Общие группы'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_showCommonGroups(peer));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showCommonGroups(ChatUserBrief peer) async {
    try {
      final groups = await ChatService.listCommonGroups(peerUserId: peer.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          if (groups.isEmpty) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Нет общих групп',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return SafeArea(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: groups.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final g = groups[index];
                return ListTile(
                  leading: const Icon(Icons.group_outlined),
                  title: HighlightedText(
                    text: g.displayTitle,
                    style: Theme.of(context).textTheme.bodyLarge ??
                        const TextStyle(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${g.memberCount} участн.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(ChatThreadPrefetch.warm(g.id));
                    context.push(ChatThreadRoute.pathForId(g.id));
                  },
                );
              },
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _clearChatHistory() async {
    if (_conversation.isSaved) return;
    final isDirect = !_conversation.isGroup && !_conversation.isSaved;
    final peerName = _conversation.peer?.displayName.trim();
    var alsoForPeer = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Очистить историю?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isDirect
                    ? (alsoForPeer
                        ? 'Переписка будет удалена у вас и у собеседника.'
                        : 'Сообщения исчезнут только у вас. Собеседник продолжит видеть переписку.')
                    : 'Сообщения исчезнут только у вас. Участники продолжат видеть переписку.',
              ),
              if (isDirect) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: alsoForPeer,
                  onChanged: (v) => setLocal(() => alsoForPeer = v ?? false),
                  title: Text(
                    (peerName != null && peerName.isNotEmpty)
                        ? 'Также удалить у ${previewTextWithCustomEmoji(peerName)}'
                        : 'Также удалить у собеседника',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Очистить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final previousMessages = List<ChatMessage>.from(_messages);
    final previousPins = List<ChatMessage>.from(_pinnedMessages);
    final previousHasMore = _hasMore;
    _applyHistoryClearedLocally();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isDirect && alsoForPeer
              ? 'История очищена у обоих'
              : 'История очищена',
        ),
      ),
    );
    try {
      await ChatService.clearHistory(
        conversationId: widget.conversationId,
        alsoForPeer: isDirect && alsoForPeer,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(previousMessages);
        _setPinnedMessages(previousPins);
        _hasMore = previousHasMore;
      });
      unawaited(
        ChatCacheService.saveThread(widget.conversationId, previousMessages),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  void _applyHistoryClearedLocally() {
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _setPinnedMessages(const []);
      _selectedMessageIds.clear();
      _selectionMode = false;
      _hasMore = false;
    });
    unawaited(ChatCacheService.saveThread(widget.conversationId, const []));
    unawaited(ChatCacheService.clearDraft(widget.conversationId));
    unawaited(
      ChatService.deleteCloudDraft(conversationId: widget.conversationId),
    );
    try {
      ProviderScope.containerOf(context)
          .read(chatsHubRefreshProvider.notifier)
          .state++;
    } catch (_) {}
  }

  ChatUserBrief? _userBriefForSender(ChatMessage msg) {
    if (!_conversation.isGroup) return _conversation.peer;
    for (final member in _groupMembers) {
      if (member.id == msg.senderId) return member;
    }
    for (final member in _conversation.membersPreview) {
      if (member.id == msg.senderId) return member;
    }
    final name = msg.senderName ?? _senderNames[msg.senderId];
    if (name != null) {
      return ChatUserBrief(id: msg.senderId, name: name);
    }
    return ChatUserBrief(id: msg.senderId, name: '?');
  }

  bool _canRevealAnonymousSender(ChatMessage msg) {
    if (!msg.isAnonymous) return true;
    if (msg.isMine) return true;
    return _conversation.amIGroupAdmin;
  }

  Widget _incomingMessageAvatar(ChatMessage msg) {
    final user = _userBriefForSender(msg);
    final reveal = _canRevealAnonymousSender(msg);
    final displayName = msg.isAnonymous
        ? (msg.senderName ?? _conversation.title ?? 'Группа')
        : (user?.displayName ?? '?');
    return AppUserAvatar(
      radius: 15,
      imageUrl: msg.isAnonymous && !reveal ? _conversation.avatarUrl : user?.avatarUrl,
      displayName: displayName,
      onTap: () {
        if (msg.isAnonymous && !reveal) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Анонимный админ')),
          );
          return;
        }
        _openUserProfile(msg.senderId);
      },
    );
  }

  Future<void> _refreshConversation() async {
    if (widget.conversationId <= 0) return;
    try {
      final conv = await ChatService.getConversation(widget.conversationId);
      Map<int, String> names = _senderNames;
      List<ChatUserBrief> members = _groupMembers;
      if (conv.isGroup) {
        final loaded = await ChatService.listMembers(widget.conversationId);
        members = loaded;
        names = {for (final m in loaded) m.id: m.displayName};
      }
      if (!mounted) return;
      final forumChanged = conv.isForum != _conversation.isForum;
      setState(() {
        _conversation = conv;
        _pinned = conv.pinned;
        _muted = conv.muted;
        if (conv.replyKeyboard != null) {
          _applyReplyKeyboard(conv.replyKeyboard);
        }
        _senderNames = names;
        _groupMembers = members;
        _bubbleAccent = ChatBubbleAccent.fromId(conv.bubbleAccent);
        _purgeExpiredAutoDeleteMessages(inSetState: true);
      });
      _reconcileSlowModeCooldownWithConversation();
      _syncAutoDeleteTicker();
      unawaited(_syncMuteSchedule());
      unawaited(_hydrateWallpaperFromConversation());
      unawaited(_loadBotCommands());
      if (forumChanged || conv.isForum) {
        unawaited(
          _loadForumTopics(selectGeneralIfNeeded: forumChanged && conv.isForum),
        );
      }
    } catch (_) {}
  }

  Future<void> _hydrateWallpaperFromConversation() async {
    final cloudUrl = _conversation.wallpaperUrl?.trim();
    if (cloudUrl != null && cloudUrl.isNotEmpty) {
      final resolved = ServerConfig.resolveMediaUrl(cloudUrl);
      final local = await ChatThreadUiPrefs.getCustomWallpaperPath(
        widget.conversationId,
      );
      ImageProvider image;
      String? path;
      if (!kIsWeb &&
          local != null &&
          local.isNotEmpty &&
          await File(local).exists()) {
        image = FileImage(File(local));
        path = local;
      } else {
        image = CachedNetworkImageProvider(resolved);
      }
      if (!mounted) return;
      if (_wallpaperImage == image && _wallpaperCustomPath == path) return;
      setState(() {
        _wallpaperCustomPath = path;
        _wallpaperImage = image;
      });
      return;
    }

    final cloudId = _conversation.wallpaperStyle?.trim();
    if (cloudId == null || cloudId.isEmpty) return;
    // Cloud style without custom URL wins over stale local custom cache.
    final style = ChatWallpaperStyle.fromId(cloudId);
    if (!mounted) return;
    if (style == _wallpaperStyle &&
        _wallpaperImage == null &&
        _wallpaperCustomPath == null) {
      return;
    }
    setState(() {
      _wallpaperStyle = style;
      _wallpaperCustomPath = null;
      _wallpaperImage = null;
    });
    unawaited(
      ChatThreadUiPrefs.setWallpaperStyle(widget.conversationId, style),
    );
  }

  Future<void> _forwardMessage(ChatMessage msg) async {
    if (_conversation.protectContent) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В этом чате запрещена пересылка сообщений'),
        ),
      );
      return;
    }
    try {
      final chats = await ChatOpenDirect.listForPicker();
      if (!mounted) return;
      final targets =
          chats.where((c) => c.id != widget.conversationId).toList();
      if (targets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет других чатов для пересылки')),
        );
        return;
      }
      final picked = await showChatTargetPickerResult(
        context,
        title: 'Переслать в...',
        chats: targets,
        enableAsCopy: true,
        allowMultiSelect: true,
      );
      if (picked == null || !mounted) return;
      final dests = picked.targets;
      for (final chat in dests) {
        unawaited(() async {
          try {
            await _sendForwardTo(chat, msg, asCopy: picked.asCopy);
            unawaited(ChatThreadPrefetch.warm(chat.id));
          } catch (e) {
            if (!mounted) return;
            if (offerFlexIfRequired(context, e)) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(userVisibleError(e))),
            );
          }
        }());
      }
      final verb = picked.asCopy ? 'Скопировано' : 'Переслано';
      final label = dests.length == 1
          ? '«${previewTextWithCustomEmoji(dests.first.displayTitle)}»'
          : '${dests.length} чатов';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$verb в $label')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _sendForwardTo(
    ChatConversation target,
    ChatMessage msg, {
    bool asCopy = false,
  }) async {
    if (msg.id <= 0) {
      throw Exception('Нельзя переслать неотправленное сообщение');
    }
    await ChatService.forwardMessage(
      targetConversationId: target.id,
      sourceConversationId: widget.conversationId,
      messageId: msg.id,
      asCopy: asCopy,
    );
  }

  Future<void> _saveMessageToFavorites(ChatMessage msg) async {
    if (msg.id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала дождитесь отправки')),
      );
      return;
    }
    if (_conversation.isSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение уже в избранном')),
      );
      return;
    }
    try {
      final saved = ChatCacheService.peekSavedChat() ??
          await ChatService.ensureSavedChat();
      if (!mounted) return;
      if (saved.id == widget.conversationId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сообщение уже в избранном')),
        );
        return;
      }
      unawaited(() async {
        try {
          await ChatService.forwardMessage(
            targetConversationId: saved.id,
            sourceConversationId: widget.conversationId,
            messageId: msg.id,
          );
          unawaited(ChatThreadPrefetch.warm(saved.id));
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userVisibleError(e))),
          );
        }
      }());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавлено в избранное')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _deleteChat() async {
    if (_conversation.isGroup) {
      await _leaveGroup();
      return;
    }
    final isDirect = !_conversation.isGroup && !_conversation.isSaved;
    final peerName = _conversation.peer?.displayName.trim();
    var alsoForPeer = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Удалить чат?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                alsoForPeer
                    ? 'Чат будет удалён у вас и у собеседника.'
                    : 'Чат исчезнет из списка. При новом сообщении диалог можно начать снова.',
              ),
              if (isDirect) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: alsoForPeer,
                  onChanged: (v) => setLocal(() => alsoForPeer = v ?? false),
                  title: Text(
                    (peerName != null && peerName.isNotEmpty)
                        ? 'Также удалить у ${previewTextWithCustomEmoji(peerName)}'
                        : 'Также удалить у собеседника',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    _leaveThreadLocally(dropCache: true);
    unawaited(() async {
      try {
        await ChatService.deleteConversation(
          conversationId: widget.conversationId,
          alsoForPeer: isDirect && alsoForPeer,
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }());
  }

  Future<void> _openFileUrl(String url) async {
    final resolved = ServerConfig.resolveMediaUrl(url);
    final uri = Uri.tryParse(resolved);
    if (uri == null) return;
    var ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    if (!ok) {
      ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть файл')),
      );
    }
  }

  void _leaveThreadLocally({required bool dropCache}) {
    if (dropCache) {
      unawaited(ChatCacheService.dropConversation(widget.conversationId));
      unawaited(ChatCacheService.clearDraft(widget.conversationId));
      unawaited(ChatCacheService.saveThread(widget.conversationId, const []));
      unawaited(
        ChatService.deleteCloudDraft(conversationId: widget.conversationId),
      );
    } else {
      unawaited(
        ChatCacheService.upsertConversation(
          ChatInboxOptimistic.applyArchive(_conversation, archived: true),
        ),
      );
    }
    _bumpChatsHub();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _archiveChat() async {
    final messenger = ScaffoldMessenger.of(context);
    _leaveThreadLocally(dropCache: false);
    unawaited(() async {
      try {
        await ChatService.setArchived(
          conversationId: widget.conversationId,
          archived: true,
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }());
  }

  void _showMembers() {
    unawaited(_openMembersSheet());
  }

  Future<void> _openMembersSheet() async {
    if (_groupMembers.isEmpty) {
      try {
        final members = await ChatService.listMembers(widget.conversationId);
        if (!mounted) return;
        setState(() {
          _groupMembers = members;
          _senderNames = {for (final m in members) m.id: m.displayName};
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
        return;
      }
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.45,
          minChildSize: 0.25,
          maxChildSize: 0.85,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Участники (${_conversation.memberCount})',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              ..._groupMembers.map(
                (member) => ListTile(
                  leading: AppUserAvatar(
                    radius: 20,
                    imageUrl: member.avatarUrl,
                    displayName: member.displayName,
                    onTap: () {
                      Navigator.pop(ctx);
                      _openUserProfile(member.id);
                    },
                  ),
                  title: HighlightedText(
                    text: member.displayName,
                    style: Theme.of(context).textTheme.bodyLarge ??
                        const TextStyle(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(formatLastSeen(member.lastSeenAt)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openUserProfile(member.id);
                  },
                ),
              ),
              if (_groupMembers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Нет данных об участниках')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMediaGallery() async {
    final messageId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ChatMediaGalleryScreen(
          conversationId: widget.conversationId,
          seedMessages: _messages,
          protectContent: _conversation.protectContent,
        ),
      ),
    );
    if (messageId == null || messageId <= 0 || !mounted) return;
    await _scrollToReplyMessage(messageId);
    if (mounted) _focusMessageTemporarily(messageId);
  }

  void _toggleThreadSearch() {
    setState(() {
      _threadSearchOpen = !_threadSearchOpen;
      if (!_threadSearchOpen) {
        _searchBackfillSeq++;
        _serverSearchSeq++;
        _searchAutoloading = false;
        _searchBackfillLoads = 0;
        _threadSearchQuery = '';
        _threadSearchFilter = _ThreadSearchFilter.all;
        _threadSearchSenderId = null;
        _threadSearchDate = null;
        _searchMatchIndex = 0;
        _serverSearchHits = const [];
        _threadSearchController.clear();
      }
    });
  }

  void _setShowOnlyFailedMessages(bool enabled) {
    if (_showOnlyFailedMessages == enabled) return;
    setState(() {
      _showOnlyFailedMessages = enabled;
    });
    if (enabled && _failedTextSends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Неотправленные медиа отображаются прямо в чате',
          ),
        ),
      );
    }
  }

  bool _messageMatchesFilter(ChatMessage msg) {
    if (_threadSearchSenderId != null &&
        msg.senderId != _threadSearchSenderId) {
      return false;
    }
    if (!messageMatchesSearchDate(msg.createdAt, _threadSearchDate)) {
      return false;
    }
    switch (_threadSearchFilter) {
      case _ThreadSearchFilter.all:
        return true;
      case _ThreadSearchFilter.text:
        return msg.content.trim().isNotEmpty &&
            msg.type != 'image' &&
            msg.type != 'video' &&
            msg.type != 'file' &&
            msg.type != 'voice';
      case _ThreadSearchFilter.media:
        return msg.type == 'image' ||
            msg.type == 'video' ||
            msg.type == 'video_note' ||
            msg.type == 'voice' ||
            msg.type == 'sticker';
      case _ThreadSearchFilter.files:
        return msg.type == 'file';
      case _ThreadSearchFilter.links:
        return extractFirstHttpUrl(msg.content) != null;
      case _ThreadSearchFilter.mine:
        return msg.isMine;
    }
  }

  bool _messageMatchesSearch(ChatMessage msg, String q) {
    if (!_messageMatchesFilter(msg)) return false;
    if (q.isEmpty) return true;
    if (msg.content.toLowerCase().contains(q)) return true;
    final sender = msg.senderName ?? _senderNames[msg.senderId] ?? '';
    if (sender.toLowerCase().contains(q)) return true;
    if (msg.type == 'voice' && 'голосовое'.contains(q)) return true;
    if (msg.type == 'image' && 'фото'.contains(q)) return true;
    if (msg.type == 'video' && 'видео'.contains(q)) return true;
    if (msg.type == 'video_note' &&
        ('кружок'.contains(q) ||
            'видеосообщение'.contains(q) ||
            'видео'.contains(q))) {
      return true;
    }
    if (msg.type == 'sticker' && 'стикер'.contains(q)) return true;
    if (msg.type == 'checklist' &&
        ('чеклист'.contains(q) || 'список'.contains(q))) {
      return true;
    }
    if (msg.type == 'file') {
      final name = msg.content.trim().toLowerCase();
      if (name.contains(q) || 'файл'.contains(q)) return true;
    }
    return false;
  }

  bool get _threadSearchHasCriteria {
    return _threadSearchQuery.trim().isNotEmpty ||
        _threadSearchFilter != _ThreadSearchFilter.all ||
        _threadSearchSenderId != null ||
        _threadSearchDate != null;
  }

  bool _serverHitMatchesFilters(ChatMessage msg) {
    if (_threadSearchSenderId != null &&
        msg.senderId != _threadSearchSenderId) {
      return false;
    }
    if (!messageMatchesSearchDate(msg.createdAt, _threadSearchDate)) {
      return false;
    }
    return _messageMatchesFilter(msg);
  }

  List<int> get _searchMatchIds {
    final sourceMessages = _visibleMessages;
    final q = _threadSearchQuery.trim().toLowerCase();
    if (!_threadSearchHasCriteria) return const [];
    final seen = <int>{};
    final ids = <int>[];
    for (final msg in _serverSearchHits) {
      if (_serverHitMatchesFilters(msg) && seen.add(msg.id)) {
        ids.add(msg.id);
      }
    }
    for (final msg in sourceMessages) {
      if (_messageMatchesSearch(msg, q) && seen.add(msg.id)) {
        ids.add(msg.id);
      }
    }
    return ids;
  }

  String? _searchTypeForFilter(_ThreadSearchFilter filter) {
    switch (filter) {
      case _ThreadSearchFilter.files:
        return 'file';
      case _ThreadSearchFilter.text:
        return 'text';
      case _ThreadSearchFilter.media:
      case _ThreadSearchFilter.all:
      case _ThreadSearchFilter.links:
      case _ThreadSearchFilter.mine:
        return null;
    }
  }

  Future<void> _runServerThreadSearch(String query) async {
    if (!_hasFlexFeature('chat_search')) {
      await showCreatorUpsell(context);
      return;
    }
    final q = query.trim();
    final filter = _threadSearchFilter;
    final senderId = _threadSearchSenderId;
    final dateDay = _threadSearchDate;
    final seq = ++_serverSearchSeq;

    // Filter-only media/files/links: full history via media API.
    if (q.length < 2) {
      final kinds = switch (filter) {
        _ThreadSearchFilter.media => const [
            'photos',
            'videos',
            'voices',
            'stickers',
          ],
        _ThreadSearchFilter.files => const ['files'],
        _ThreadSearchFilter.links => const ['links'],
        _ => const <String>[],
      };
      if (kinds.isEmpty) {
        if (dateDay == null) {
          if (_serverSearchHits.isNotEmpty && mounted) {
            setState(() => _serverSearchHits = const []);
          }
          return;
        }
        try {
          final hits = await ChatService.searchMessages(
            query: '',
            conversationId: widget.conversationId,
            type: _searchTypeForFilter(filter),
            senderId: senderId,
            dateFrom: dateDay,
            dateTo: dateDay,
            limit: 60,
          );
          if (!mounted || seq != _serverSearchSeq) return;
          setState(() {
            _serverSearchHits = [for (final hit in hits) hit.message];
            if (_searchMatchIndex >= _searchMatchIds.length) {
              _searchMatchIndex = 0;
            }
          });
          _scrollToCurrentSearchMatch();
        } catch (_) {
          // Keep local matches if server search fails.
        }
        return;
      }
      try {
        final merged = <ChatMessage>[];
        final seen = <int>{};
        for (final kind in kinds) {
          final page = await ChatService.listChatMedia(
            conversationId: widget.conversationId,
            kind: kind,
            senderId: senderId,
            limit: 60,
          );
          if (!mounted || seq != _serverSearchSeq) return;
          for (final msg in page.items) {
            if (!messageMatchesSearchDate(msg.createdAt, dateDay)) continue;
            if (seen.add(msg.id)) merged.add(msg);
          }
        }
        merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (!mounted || seq != _serverSearchSeq) return;
        setState(() {
          _serverSearchHits = merged;
          if (_searchMatchIndex >= _searchMatchIds.length) {
            _searchMatchIndex = 0;
          }
        });
        _scrollToCurrentSearchMatch();
      } catch (_) {
        // Keep local matches if media listing fails.
      }
      return;
    }

    try {
      final hits = await ChatService.searchMessages(
        query: q,
        conversationId: widget.conversationId,
        type: _searchTypeForFilter(filter),
        senderId: senderId,
        dateFrom: dateDay,
        dateTo: dateDay,
        limit: 60,
      );
      if (!mounted || seq != _serverSearchSeq) return;
      var messages = [for (final hit in hits) hit.message];
      // Typed search API may not cover media/links; merge media listing.
      if (filter == _ThreadSearchFilter.media ||
          filter == _ThreadSearchFilter.links) {
        final kinds = filter == _ThreadSearchFilter.links
            ? const ['links']
            : const ['photos', 'videos', 'voices', 'stickers'];
        final seen = {for (final m in messages) m.id};
        for (final kind in kinds) {
          final page = await ChatService.listChatMedia(
            conversationId: widget.conversationId,
            kind: kind,
            senderId: senderId,
            limit: 60,
          );
          if (!mounted || seq != _serverSearchSeq) return;
          for (final msg in page.items) {
            if (!_messageMatchesSearch(msg, q.toLowerCase())) continue;
            if (seen.add(msg.id)) messages.add(msg);
          }
        }
      }
      if (!mounted || seq != _serverSearchSeq) return;
      setState(() {
        _serverSearchHits = messages;
        if (_searchMatchIndex >= _searchMatchIds.length) {
          _searchMatchIndex = 0;
        }
      });
      _scrollToCurrentSearchMatch();
    } catch (_) {
      // Keep local matches if server search fails.
    }
  }

  void _onThreadSearchChanged(String value) {
    final normalized = value.trim().toLowerCase();
    final hasCriteria = normalized.isNotEmpty ||
        _threadSearchFilter != _ThreadSearchFilter.all ||
        _threadSearchSenderId != null ||
        _threadSearchDate != null;
    setState(() {
      _searchBackfillSeq++;
      _threadSearchQuery = value;
      _searchMatchIndex = 0;
      _searchBackfillLoads = 0;
      if (!hasCriteria) {
        _searchAutoloading = false;
        _serverSearchHits = const [];
      }
    });
    _scrollToCurrentSearchMatch();
    if (hasCriteria) {
      unawaited(_runServerThreadSearch(value));
      unawaited(
        _backfillSearchFromHistory(
          normalized,
          _threadSearchFilter,
          _threadSearchSenderId,
          _threadSearchDate,
        ),
      );
    }
  }

  void _onThreadSearchFilterChanged(_ThreadSearchFilter value) {
    if (_threadSearchFilter == value) return;
    final normalized = _threadSearchQuery.trim().toLowerCase();
    final hasCriteria = normalized.isNotEmpty ||
        value != _ThreadSearchFilter.all ||
        _threadSearchSenderId != null ||
        _threadSearchDate != null;
    setState(() {
      _searchBackfillSeq++;
      _threadSearchFilter = value;
      _searchMatchIndex = 0;
      _searchBackfillLoads = 0;
      if (!hasCriteria) {
        _searchAutoloading = false;
        _serverSearchHits = const [];
      }
    });
    _scrollToCurrentSearchMatch();
    if (hasCriteria) {
      unawaited(_runServerThreadSearch(_threadSearchQuery));
      unawaited(
        _backfillSearchFromHistory(
          normalized,
          value,
          _threadSearchSenderId,
          _threadSearchDate,
        ),
      );
    }
  }

  Future<void> _pickThreadSearchSender() async {
    if (!_conversation.isGroup) return;
    if (_groupMembers.isEmpty) {
      try {
        final members = await ChatService.listMembers(widget.conversationId);
        if (!mounted) return;
        setState(() {
          _groupMembers = members;
          _senderNames = {for (final m in members) m.id: m.displayName};
        });
      } catch (_) {
        // Ignore; user can still select "all" if load fails.
      }
    }
    if (!mounted) return;
    final myId = AuthService.instance.currentUser?.id;
    const allValue = -1;
    const myValue = -2;
    final options = <_SearchSenderOption>[
      const _SearchSenderOption(
        value: allValue,
        senderId: null,
        label: 'Все участники',
      ),
      if (myId != null) const _SearchSenderOption(value: myValue, label: 'Я'),
      ..._groupMembers.map(
        (m) => _SearchSenderOption(
          value: m.id,
          senderId: m.id,
          label: m.displayName,
        ),
      ),
    ];
    final selectedValue = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final selectedValue = myId != null && _threadSearchSenderId == myId
            ? myValue
            : (_threadSearchSenderId ?? allValue);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final option in options)
                ListTile(
                  title: HighlightedText(
                    text: option.label,
                    style: Theme.of(ctx).textTheme.bodyLarge ??
                        const TextStyle(fontSize: 16),
                  ),
                  trailing: selectedValue == option.value
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(option.value),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (selectedValue == null) return;
    if (selectedValue == allValue) {
      _onThreadSearchSenderChanged(null);
      return;
    }
    if (selectedValue == myValue && myId != null) {
      _onThreadSearchSenderChanged(myId);
      return;
    }
    for (final option in options) {
      if (option.value == selectedValue) {
        _onThreadSearchSenderChanged(option.senderId);
        return;
      }
    }
  }

  void _onThreadSearchSenderChanged(int? senderId) {
    if (_threadSearchSenderId == senderId) return;
    final normalized = _threadSearchQuery.trim().toLowerCase();
    final hasCriteria = normalized.isNotEmpty ||
        _threadSearchFilter != _ThreadSearchFilter.all ||
        senderId != null ||
        _threadSearchDate != null;
    setState(() {
      _searchBackfillSeq++;
      _threadSearchSenderId = senderId;
      _searchMatchIndex = 0;
      _searchBackfillLoads = 0;
      if (!hasCriteria) {
        _searchAutoloading = false;
        _serverSearchHits = const [];
      }
    });
    _scrollToCurrentSearchMatch();
    if (hasCriteria) {
      unawaited(_runServerThreadSearch(_threadSearchQuery));
      unawaited(
        _backfillSearchFromHistory(
          normalized,
          _threadSearchFilter,
          senderId,
          _threadSearchDate,
        ),
      );
    }
  }

  Future<void> _pickThreadSearchDate() async {
    final now = DateTime.now();
    final oldest = _messages.isNotEmpty
        ? _dateOnly(_messages.first.createdAt)
        : now.subtract(const Duration(days: 3650));
    final firstDate =
        oldest.isBefore(now) ? oldest : now.subtract(const Duration(days: 3650));
    final lastDate = _dateOnly(now);
    final initialCandidate = _threadSearchDate ??
        (_messages.isNotEmpty
            ? _dateOnly(_messages.last.createdAt)
            : lastDate);
    final initialDate = initialCandidate.isAfter(lastDate)
        ? lastDate
        : initialCandidate.isBefore(firstDate)
            ? firstDate
            : initialCandidate;
    final picked = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: initialDate,
      helpText: 'Фильтр по дате',
    );
    if (picked == null || !mounted) return;
    _onThreadSearchDateChanged(_dateOnly(picked));
  }

  void _onThreadSearchDateChanged(DateTime? day) {
    final next = day == null ? null : _dateOnly(day);
    if (_threadSearchDate == next) return;
    final normalized = _threadSearchQuery.trim().toLowerCase();
    final hasCriteria = normalized.isNotEmpty ||
        _threadSearchFilter != _ThreadSearchFilter.all ||
        _threadSearchSenderId != null ||
        next != null;
    setState(() {
      _searchBackfillSeq++;
      _threadSearchDate = next;
      _searchMatchIndex = 0;
      _searchBackfillLoads = 0;
      if (!hasCriteria) {
        _searchAutoloading = false;
        _serverSearchHits = const [];
      }
    });
    _scrollToCurrentSearchMatch();
    if (hasCriteria) {
      unawaited(_runServerThreadSearch(_threadSearchQuery));
      unawaited(
        _backfillSearchFromHistory(
          normalized,
          _threadSearchFilter,
          _threadSearchSenderId,
          next,
        ),
      );
    }
  }

  void _scrollToCurrentSearchMatch() {
    final ids = _searchMatchIds;
    if (ids.isEmpty) return;
    final idx = _searchMatchIndex.clamp(0, ids.length - 1);
    unawaited(_focusSearchMatchId(ids[idx]));
  }

  Future<void> _focusSearchMatchId(int messageId) async {
    if (_messages.any((m) => m.id == messageId)) {
      _scrollToMessage(messageId);
      _focusMessageTemporarily(messageId);
      return;
    }
    await _scrollToReplyMessage(messageId);
    if (!mounted) return;
    _focusMessageTemporarily(messageId);
  }

  void _goToSearchMatch(bool forward) {
    final ids = _searchMatchIds;
    if (ids.isEmpty) return;
    setState(() {
      if (forward) {
        _searchMatchIndex = (_searchMatchIndex + 1) % ids.length;
      } else {
        _searchMatchIndex = (_searchMatchIndex - 1 + ids.length) % ids.length;
      }
    });
    unawaited(_focusSearchMatchId(ids[_searchMatchIndex]));
  }

  void _jumpToFirstSearchMatch() {
    final ids = _searchMatchIds;
    if (ids.isEmpty) return;
    setState(() => _searchMatchIndex = 0);
    unawaited(_focusSearchMatchId(ids.first));
  }

  Future<void> _backfillSearchFromHistory(
    String normalizedQuery,
    _ThreadSearchFilter filter,
    int? senderId,
    DateTime? dateDay,
  ) async {
    if (_searchMatchIds.isNotEmpty || !_hasMore) return;
    final seq = _searchBackfillSeq;
    if (!_searchAutoloading && mounted) {
      setState(() {
        _searchAutoloading = true;
        _searchBackfillLoads = 0;
      });
    }
    var attempts = 0;
    while (mounted &&
        seq == _searchBackfillSeq &&
        attempts < 6 &&
        _threadSearchQuery.trim().toLowerCase() == normalizedQuery &&
        _threadSearchFilter == filter &&
        _threadSearchSenderId == senderId &&
        _threadSearchDate == dateDay &&
        _searchMatchIds.isEmpty &&
        _hasMore) {
      if (_loading || _loadingMore) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      attempts++;
      await _load(refresh: false);
      if (mounted && seq == _searchBackfillSeq) {
        setState(() => _searchBackfillLoads = attempts);
      }
    }
    if (!mounted || seq != _searchBackfillSeq) return;
    setState(() => _searchAutoloading = false);
    if (_threadSearchQuery.trim().toLowerCase() == normalizedQuery &&
        _threadSearchFilter == filter &&
        _threadSearchSenderId == senderId &&
        _threadSearchDate == dateDay &&
        _searchMatchIds.isNotEmpty) {
      _scrollToCurrentSearchMatch();
    }
  }

  String _searchFilterLabel(_ThreadSearchFilter filter) {
    switch (filter) {
      case _ThreadSearchFilter.all:
        return 'Все';
      case _ThreadSearchFilter.text:
        return 'Текст';
      case _ThreadSearchFilter.media:
        return 'Медиа';
      case _ThreadSearchFilter.files:
        return 'Файлы';
      case _ThreadSearchFilter.links:
        return 'Ссылки';
      case _ThreadSearchFilter.mine:
        return 'Мои';
    }
  }

  String _searchSenderLabel() {
    final senderId = _threadSearchSenderId;
    if (senderId == null) return 'Автор';
    final myId = AuthService.instance.currentUser?.id;
    if (myId != null && senderId == myId) return 'Я';
    return _senderNames[senderId] ?? 'Пользователь';
  }

  String _searchDateLabel() {
    final day = _threadSearchDate;
    if (day == null) return 'Дата';
    return searchDateChipLabel(day);
  }

  List<ChatMessage> get _visibleMessages {
    if (_showOnlyFailedMessages) {
      final failedMediaTempId = _pendingMediaRetry?.tempId;
      return _messages
          .where((m) =>
              _failedTextSends.containsKey(m.id) ||
              _failedReadySends.containsKey(m.id) ||
              (failedMediaTempId != null && m.id == failedMediaTempId))
          .toList(growable: false);
    }
    return _messages;
  }

  int get _failedPendingItemsCount =>
      _failedTextSends.length +
      _failedReadySends.length +
      (_pendingMediaRetry != null ? 1 : 0);

  bool _canClusterMessages(ChatMessage a, ChatMessage b) {
    if (a.senderId != b.senderId || a.isMine != b.isMine) return false;
    if (!_isSameChatDay(a.createdAt, b.createdAt)) return false;
    if (a.type == 'poll' || b.type == 'poll') return false;
    if (a.type == 'checklist' || b.type == 'checklist') return false;
    final gap = b.createdAt.difference(a.createdAt).abs();
    return gap <= const Duration(minutes: 5);
  }

  List<_MessageCluster> _computeMessageClusters(List<ChatMessage> messages) {
    if (messages.isEmpty) return const [];
    final clusters = List<_MessageCluster>.filled(
      messages.length,
      const _MessageCluster.single(),
      growable: false,
    );
    for (var index = 0; index < messages.length; index++) {
      final current = messages[index];
      final prevSame =
          index > 0 && _canClusterMessages(messages[index - 1], current);
      final nextSame = index < messages.length - 1 &&
          _canClusterMessages(current, messages[index + 1]);
      clusters[index] = _MessageCluster(starts: !prevSame, ends: !nextSame);
    }
    return clusters;
  }

  List<bool> _computeDateSeparators(List<ChatMessage> messages) {
    if (messages.isEmpty) return const [];
    final separators =
        List<bool>.filled(messages.length, false, growable: false);
    separators[0] = true;
    for (var index = 1; index < messages.length; index++) {
      separators[index] = !_isSameChatDay(
        messages[index - 1].createdAt,
        messages[index].createdAt,
      );
    }
    return separators;
  }

  GlobalKey _messageItemKey(int messageId) {
    return _messageItemKeys.putIfAbsent(
      messageId,
      () => GlobalKey(debugLabel: 'chat_message_$messageId'),
    );
  }

  void _trimMessageItemKeys(Iterable<ChatMessage> visibleMessages) {
    final visibleIds = visibleMessages.map((m) => m.id).toSet();
    _messageItemKeys.removeWhere(
      (id, _) => !visibleIds.contains(id) && _messageItemKeys.length > 160,
    );
  }

  void _bumpChatsHub() {
    try {
      ProviderScope.containerOf(context)
          .read(chatsHubRefreshProvider.notifier)
          .state++;
    } catch (_) {}
  }

  Future<void> _markUnread() async {
    _markReadDebounce?.cancel();
    final previous = _conversation;
    setState(() {
      _suppressMarkRead = true;
      _conversation = ChatInboxOptimistic.applyUnread(_conversation);
    });
    _bumpChatsHub();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Чат помечен непрочитанным')),
    );
    try {
      await ChatService.markUnread(conversationId: widget.conversationId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _suppressMarkRead = false;
        _conversation = previous;
      });
      _bumpChatsHub();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    setState(() {
      _pinned = next;
      _conversation = ChatInboxOptimistic.applyPin(_conversation, pinned: next);
    });
    _bumpChatsHub();
    try {
      await ChatService.setPinned(
        conversationId: widget.conversationId,
        pinned: next,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pinned = !next;
        _conversation =
            ChatInboxOptimistic.applyPin(_conversation, pinned: !next);
      });
      _bumpChatsHub();
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _syncMuteSchedule() async {
    _muteUnmuteTimer?.cancel();
    _muteUnmuteTimer = null;
    if (!_muted) {
      await ChatThreadUiPrefs.setMuteUntil(widget.conversationId, null);
      return;
    }
    // Prefer cloud muted_until; fall back to local cache.
    var until = _conversation.mutedUntil?.toLocal();
    until ??= await ChatThreadUiPrefs.getMuteUntil(widget.conversationId);
    if (until != null) {
      await ChatThreadUiPrefs.setMuteUntil(widget.conversationId, until);
    }
    if (until == null) return; // forever
    final remaining = until.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      await _applyMuted(false);
      return;
    }
    _muteUnmuteTimer = Timer(remaining, () {
      unawaited(_applyMuted(false));
    });
  }

  Future<void> _applyMuted(
    bool muted, {
    DateTime? until,
    String notifyMode = 'mentions',
  }) async {
    if (!mounted) return;
    final mode = muted ? notifyMode : 'all';
    final previousMuted = _muted;
    final previousConv = _conversation;
    setState(() {
      _muted = muted;
      _conversation = ChatInboxOptimistic.applyMute(
        _conversation,
        muted: muted,
        until: until,
        notifyMode: mode,
      );
    });
    unawaited(
      ChatThreadUiPrefs.setMuteUntil(
        widget.conversationId,
        muted ? until : null,
      ),
    );
    _bumpChatsHub();
    try {
      await ChatService.setMuted(
        conversationId: widget.conversationId,
        muted: muted,
        mutedUntil: muted ? until : null,
        notifyMode: mode,
      );
      if (!mounted) return;
      await _syncMuteSchedule();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _muted = previousMuted;
        _conversation = previousConv;
      });
      unawaited(
        ChatThreadUiPrefs.setMuteUntil(
          widget.conversationId,
          previousConv.mutedUntil,
        ),
      );
      _bumpChatsHub();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _toggleMute() async {
    final choice = await showChatMuteDurationSheet(
      context,
      currentlyMuted: _muted,
      mutedUntil: _conversation.mutedUntil,
      currentNotifyMode: _conversation.notifyMode,
    );
    if (choice == null || !mounted) return;
    if (choice.unmute) {
      unawaited(_applyMuted(false));
    } else {
      unawaited(
        _applyMuted(
          true,
          until: choice.until,
          notifyMode: choice.notifyMode,
        ),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(choice.snackLabel)),
    );
  }

  Future<void> _saveContactToPhone(ChatContactPayload contact) async {
    final phone = contact.phone?.trim();
    if (phone == null || phone.isEmpty) return;
    try {
      await PhoneContactsService.addContactToDevice(
        displayName: contact.displayName,
        phoneRaw: phone,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb ? 'Контакт сохранён' : 'Контакт сохранён в телефоне',
          ),
        ),
      );
    } on PhoneContactsPermissionDenied {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Нужен доступ к контактам. '
            'Настройки → HanWe → Контакты → разрешить изменения.',
          ),
        ),
      );
    } on PhoneContactsInvalidInput catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _addHanContactFromBubble(int userId) async {
    if (userId <= 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Добавлено в контакты')),
    );
    try {
      await ChatService.addContact(userId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось добавить контакт'),
          ),
        ),
      );
    }
  }

  Future<void> _sendStarGift() async {
    final peer = _conversation.peer;
    if (peer == null || _sendingStarGift) return;
    final draft = await showStarGiftSendFlow(context);
    if (draft == null || !mounted) return;
    final gift = draft.gift;
    setState(() => _sendingStarGift = true);
    final idem =
        'flutter:gift:${widget.conversationId}:${gift.id}:${const Uuid().v4()}';
    final messenger = ScaffoldMessenger.of(context);
    unawaited(() async {
      try {
        await PaidFeaturesService.sendGift(
          giftId: gift.id,
          conversationId: widget.conversationId,
          message: draft.message,
          hideName: draft.hideName,
          idempotencyKey: idem,
        );
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              draft.hideName
                  ? 'Подарок ${gift.emoji} отправлен анонимно'
                  : 'Подарок ${gift.emoji} отправлен',
            ),
          ),
        );
        unawaited(_pollNew());
      } catch (e) {
        if (!mounted) return;
        if (offerFlexIfRequired(context, e)) return;
        if (offerPackStoreIfRequired(context, e)) return;
        await showStarsRequiredSnack(context, e);
      } finally {
        if (mounted) setState(() => _sendingStarGift = false);
      }
    }());
  }

  int? _userGiftIdFromMessage(ChatMessage msg) {
    try {
      final decoded = jsonDecode(msg.content);
      if (decoded is Map<String, dynamic>) {
        final raw = decoded['user_gift_id'];
        if (raw is int) return raw;
        if (raw is num) return raw.toInt();
      }
    } catch (_) {}
    return null;
  }

  bool _giftMessageIsCollectible(ChatMessage msg) {
    try {
      final decoded = jsonDecode(msg.content);
      if (decoded is Map<String, dynamic>) {
        return decoded['is_collectible'] == true;
      }
    } catch (_) {}
    return false;
  }

  void _patchLocalGiftStatus(ChatMessage msg, String status) {
    try {
      final decoded = jsonDecode(msg.content);
      if (decoded is! Map<String, dynamic>) return;
      decoded['status'] = status;
      final next = msg.copyWith(content: jsonEncode(decoded));
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx >= 0) {
        setState(() => _messages[idx] = next);
      }
    } catch (_) {}
  }

  Future<void> _convertReceivedGift(ChatMessage msg) async {
    final giftId = _userGiftIdFromMessage(msg);
    if (giftId == null || _giftActionMessageIds.contains(msg.id)) return;
    final stars = () {
      try {
        final decoded = jsonDecode(msg.content);
        if (decoded is Map<String, dynamic>) {
          return (decoded['stars'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
      return 0;
    }();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Конвертировать подарок'),
        content: Text('Получить $stars ★ на баланс? Подарок исчезнет из профиля.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Получить $stars ★'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _giftActionMessageIds.add(msg.id));
    _patchLocalGiftStatus(msg, 'converted');
    try {
      await PaidFeaturesService.convertGift(giftId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('+$stars ★ на балансе')),
      );
    } catch (e) {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx >= 0) setState(() => _messages[idx] = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _giftActionMessageIds.remove(msg.id));
      }
    }
  }

  bool _withinStarsRefundWindow(DateTime createdAt) {
    return DateTime.now().toUtc().difference(createdAt.toUtc()) <=
        const Duration(hours: 48);
  }

  bool _giftStatusAllowsRefund(ChatMessage msg) {
    try {
      final decoded = jsonDecode(msg.content);
      if (decoded is Map<String, dynamic>) {
        final status = decoded['status'] as String? ?? 'held';
        return status == 'held' || status == 'kept';
      }
    } catch (_) {}
    return true;
  }

  Future<void> _refundSentGift(ChatMessage msg) async {
    final giftId = _userGiftIdFromMessage(msg);
    if (giftId == null || _giftActionMessageIds.contains(msg.id)) return;
    if (!_giftStatusAllowsRefund(msg)) return;
    final stars = () {
      try {
        final decoded = jsonDecode(msg.content);
        if (decoded is Map<String, dynamic>) {
          return (decoded['stars'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
      return 0;
    }();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Вернуть подарок'),
        content: Text(
          'Вернуть $stars ★ на баланс? Получатель больше не увидит подарок. Можно в течение 48 часов.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Вернуть $stars ★'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _giftActionMessageIds.add(msg.id));
    _patchLocalGiftStatus(msg, 'refunded');
    try {
      await PaidFeaturesService.refundGift(giftId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('+$stars ★ возвращены')),
      );
    } catch (e) {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx >= 0) setState(() => _messages[idx] = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _giftActionMessageIds.remove(msg.id));
      }
    }
  }

  Future<void> _refundPaidMedia(ChatMessage msg) async {
    if (!msg.isMine || !msg.isPaid || msg.id <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Вернуть оплату'),
        content: const Text(
          'Звёзды вернутся покупателям, доступ к медиа закроется. Можно в течение 48 часов после покупки.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Вернуть'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final result = await PaidFeaturesService.refundPaidMedia(msg.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.refunded == 1
                ? 'Оплата возвращена'
                : 'Возвращено покупок: ${result.refunded}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _keepReceivedGift(ChatMessage msg) async {
    final giftId = _userGiftIdFromMessage(msg);
    if (giftId == null || _giftActionMessageIds.contains(msg.id)) return;
    setState(() => _giftActionMessageIds.add(msg.id));
    _patchLocalGiftStatus(msg, 'kept');
    try {
      await PaidFeaturesService.keepGift(giftId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подарок сохранён в профиле')),
      );
    } catch (e) {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx >= 0) setState(() => _messages[idx] = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _giftActionMessageIds.remove(msg.id));
      }
    }
  }

  Future<void> _unlockPaidMedia(ChatMessage msg) async {
    if (!msg.isLockedPaidMedia) return;
    final ok = await confirmStarsSpend(
      context,
      title: 'Открыть медиа',
      body: 'Один раз оплатите звёздами — медиа откроется в этом чате.',
      amountStars: msg.priceStars,
      confirmLabel: 'Открыть',
    );
    if (!ok || !mounted) return;
    final previous = msg;
    setState(() {
      _unlockingMessageIds.add(msg.id);
      final i = _messages.indexWhere((m) => m.id == msg.id);
      if (i >= 0) {
        _messages[i] = msg.copyWith(purchased: true);
      }
    });
    try {
      await PaidFeaturesService.purchaseMessage(msg.id);
      if (!mounted) return;
      unawaited(_pollNew());
      unawaited(_load(refresh: true));
    } catch (e) {
      if (!mounted) return;
      final i = _messages.indexWhere((m) => m.id == previous.id);
      if (i >= 0) setState(() => _messages[i] = previous);
      await showStarsRequiredSnack(context, e);
    } finally {
      if (mounted) {
        setState(() => _unlockingMessageIds.remove(msg.id));
      }
    }
  }

  Future<void> _tipPeerWithStars() async {
    final peer = _conversation.peer;
    if (peer == null) return;
    final payload = await pickStarsTipDraft(
      context,
      title:
          'Отправить звёзды ${previewTextWithCustomEmoji(peer.displayName)}',
      subtitle: 'Как в Telegram: звёзды появятся сообщением в чате.',
    );
    if (payload == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    unawaited(() async {
      try {
        final result = await PaidFeaturesService.donate(
          recipientId: peer.id,
          amountStars: payload.amount,
          message: payload.message,
        );
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Отправлено ${payload.amount} ★')),
        );
        if (result.messageId != null) {
          unawaited(_pollNew());
        }
      } catch (e) {
        if (!mounted) return;
        if (offerFlexIfRequired(context, e)) return;
        if (offerPackStoreIfRequired(context, e)) return;
        await showStarsRequiredSnack(context, e);
      }
    }());
  }

  Future<void> _startVideoCall() async {
    final peer = _conversation.peer;
    if (!_conversation.isGroup && peer == null) return;
    if (_conversation.isGroup && !_canManageGroupCalls) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет права начинать групповые звонки'),
        ),
      );
      return;
    }
    try {
      await CallCoordinator.instance.openOutgoing(
        conversationId: widget.conversationId,
        media: 'video',
        context: context,
        peerName: _conversation.isGroup
            ? (_conversation.title ?? 'Группа')
            : peer?.name,
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: 'Не удалось начать видеозвонок');
    }
  }

  Future<void> _startVoiceCall() async {
    final peer = _conversation.peer;
    if (!_conversation.isGroup && peer == null) return;
    if (_conversation.isGroup && !_canManageGroupCalls) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет права начинать групповые звонки'),
        ),
      );
      return;
    }
    try {
      await CallCoordinator.instance.openOutgoing(
        conversationId: widget.conversationId,
        media: 'voice',
        context: context,
        peerName: _conversation.isGroup
            ? (_conversation.title ?? 'Группа')
            : peer?.name,
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: 'Не удалось начать звонок');
    }
  }

  Future<void> _redialFromCallMessage(ChatMessage msg) async {
    final media = CallMessageLabels.mediaOf(msg.content);
    if (media == 'video') {
      await _startVideoCall();
    } else {
      await _startVoiceCall();
    }
  }

  void _showQuickCallMenu() {
    showTelegramActionSheet<void>(
      context: context,
      title: 'Связь',
      actions: [
        TelegramActionSheetAction(
          icon: Icons.videocam_outlined,
          title: 'Видеозвонок',
          onTap: () => unawaited(_startVideoCall()),
        ),
        TelegramActionSheetAction(
          icon: Icons.call_outlined,
          title: 'Аудиозвонок',
          onTap: () => unawaited(_startVoiceCall()),
        ),
      ],
    );
  }

  Future<void> _blockPeer() async {
    final peer = _conversation.peer;
    if (peer == null) return;
    var deleteHistory = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Заблокировать?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${previewTextWithCustomEmoji(peer.displayName)} не сможет писать вам и видеть ваш профиль в чатах.',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteHistory,
                onChanged: (v) => setLocal(() => deleteHistory = v ?? false),
                title: const Text('Удалить историю переписки'),
                subtitle: const Text(
                  'Чат исчезнет из списка, сообщения будут скрыты у вас',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Заблокировать'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (deleteHistory) {
      _leaveThreadLocally(dropCache: true);
    } else {
      setState(() {
        _conversation = ChatInboxOptimistic.applyBlocked(
          _conversation,
          blocked: true,
        );
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${previewTextWithCustomEmoji(peer.displayName)} заблокирован',
          ),
        ),
      );
    }
    unawaited(() async {
      try {
        await ChatService.blockUser(peer.id);
        if (deleteHistory) {
          await ChatService.clearHistory(
            conversationId: widget.conversationId,
          );
          await ChatService.deleteConversation(
            conversationId: widget.conversationId,
          );
        }
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }());
  }

  Future<void> _unblockPeer() async {
    final peer = _conversation.peer;
    if (peer == null) return;
    setState(() {
      _conversation = ChatInboxOptimistic.applyBlocked(
        _conversation,
        blocked: false,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${previewTextWithCustomEmoji(peer.displayName)} разблокирован',
        ),
      ),
    );
    try {
      await ChatService.unblockUser(peer.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _conversation = ChatInboxOptimistic.applyBlocked(
          _conversation,
          blocked: true,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  void _openGroupInfo() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatGroupInfoScreen(
          conversation: _conversation,
          onConversationChanged: (conv) {
            if (!mounted) return;
            final forumChanged = conv.isForum != _conversation.isForum;
            setState(() {
              _conversation = conv;
              _muted = conv.muted;
            });
            _reconcileSlowModeCooldownWithConversation();
            if (forumChanged || conv.isForum) {
              unawaited(
                _loadForumTopics(
                  selectGeneralIfNeeded: forumChanged && conv.isForum,
                ),
              );
            }
            if (forumChanged && !conv.isForum) {
              unawaited(_load(refresh: true));
            }
          },
          onLeftGroup: () {
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из группы?'),
        content:
            const Text('Вы больше не будете получать сообщения в этом чате.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    _leaveThreadLocally(dropCache: true);
    unawaited(() async {
      try {
        await ChatService.leaveGroup(conversationId: widget.conversationId);
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    _appPaused = state != AppLifecycleState.resumed;
    if (_appPaused) {
      _manualReadyRetryTimer?.cancel();
      _manualReadyRetryTimer = null;
      _stream?.pauseForBackground();
      if (_recording || _holdActive) {
        _holdActive = false;
        unawaited(_cancelRecording());
      }
    } else {
      HanEatHttpClient.ensureHealthy();
      unawaited(ApiReachabilityService.instance.warmUp());
      _stream?.resumeFromBackground();
      unawaited(_pollNew());
      _onConnectionRestored();
      _reconcileManualReadyRetrySchedule();
      _purgeExpiredAutoDeleteMessages();
      _syncAutoDeleteTicker();
    }
  }

  ChatMessage? _replyTargetFor(ChatMessage msg) {
    final id = msg.replyToMessageId;
    if (id == null) return null;
    for (final m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  String _messagePreview(ChatMessage msg) {
    if (msg.type == 'call') {
      return CallMessageLabels.preview(msg.content, mine: msg.isMine);
    }
    if (msg.type == 'voice') return '🎤 Голосовое';
    if (msg.type == 'gift') {
      try {
        final data = jsonDecode(msg.content);
        if (data is Map && data['emoji'] is String) {
          return '🎁 Подарок ${data['emoji']}';
        }
      } catch (_) {}
      return '🎁 Подарок';
    }
    if (msg.type == 'stars_tip') {
      try {
        final data = jsonDecode(msg.content);
        if (data is Map) {
          final amount = data['amount'];
          if (amount is int) return '⭐ $amount ★';
          if (amount is num) return '⭐ ${amount.toInt()} ★';
        }
      } catch (_) {}
      return '⭐ Звёзды';
    }
    if (msg.type == 'image') {
      return msg.isLockedPaidMedia ? '🔒 Платное фото' : '📷 Фото';
    }
    if (msg.type == 'video') {
      return msg.isLockedPaidMedia ? '🔒 Платное видео' : '🎬 Видео';
    }
    if (msg.type == 'video_note') return '⭕ Видеосообщение';
    if (msg.type == 'sticker') return '🧩 Стикер';
    if (msg.type == 'poll') {
      final poll = msg.poll;
      if (poll != null) return chatPollPreviewText(poll);
      return '📊 Опрос';
    }
    if (msg.type == 'checklist') {
      return msg.checklist?.preview ?? '☑ Чеклист';
    }
    if (msg.type == 'file') {
      if (msg.isLockedPaidMedia) return '🔒 Платный файл';
      final name = msg.content.trim();
      return name.isEmpty
          ? '📎 Файл'
          : '📎 ${previewTextWithCustomEmoji(name)}';
    }
    if (msg.type == 'location' ||
        ChatLocationPayload.tryParse(msg.content) != null) {
      final loc = ChatLocationPayload.tryParse(msg.content);
      return loc?.previewText ?? '📍 Геопозиция';
    }
    if (msg.type == 'story_reply' ||
        ChatStoryReplyPayload.tryParse(msg.content) != null) {
      final reply = ChatStoryReplyPayload.tryParse(msg.content);
      return reply?.previewText ?? '🖼 Ответ на сторис';
    }
    final contact = ChatContactPayload.tryParse(msg.content);
    if (contact != null) {
      return '👤 ${previewTextWithCustomEmoji(contact.displayName)}';
    }
    final t = msg.content.trim();
    if (t.isEmpty) return 'Сообщение';
    return previewTextWithCustomEmoji(t);
  }

  String _formatRecordDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onHoldStart() {
    _holdActive = true;
    _voiceLocked = false;
    unawaited(_startRecording());
  }

  void _onHoldDrag(double dx, double dy) {
    if (!_recording || !mounted || _voiceLocked) return;
    // Telegram: swipe up to lock, left to cancel.
    if (dy < -64) {
      setState(() {
        _voiceLocked = true;
        _recordCancelled = false;
        _holdActive = false;
      });
      AppHaptics.medium();
      return;
    }
    final cancel = dx < -72;
    if (cancel != _recordCancelled) {
      setState(() => _recordCancelled = cancel);
    }
  }

  void _onHoldEnd() {
    // Locked mode continues until Send / Delete.
    if (_voiceLocked) {
      _holdActive = false;
      return;
    }
    _holdActive = false;
    if (!_recording) return;
    if (_recordCancelled) {
      unawaited(_cancelRecording());
    } else {
      unawaited(_stopAndSendVoice());
    }
    if (mounted) setState(() => _recordCancelled = false);
  }

  Future<void> _stopRecorderSilently() async {
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    try {
      await _audioRecorder.stop();
    } catch (_) {}
  }

  Future<void> _startRecording() async {
    if (_sending || _recording) return;
    final ok = await _audioRecorder.hasPermission();
    if (!_holdActive || !mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Разрешите доступ к микрофону')),
      );
      return;
    }
    final dir = kIsWeb ? null : await getTemporaryDirectory();
    final path = dir == null
        ? null
        : '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      if (kIsWeb) {
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.opus,
            bitRate: 96000,
            sampleRate: 48000,
          ),
          path: 'voice.webm',
        );
      } else {
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path!,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
      return;
    }
    if (!_holdActive || !mounted) {
      await _stopRecorderSilently();
      return;
    }
    _amplitudeSub?.cancel();
    _waveLevels.clear();
    _amplitudeSub = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amp) {
      if (!mounted) return;
      final norm = ((amp.current + 45) / 45).clamp(0.08, 1.0).toDouble();
      setState(() {
        _waveLevels.add(norm);
        if (_waveLevels.length > 40) _waveLevels.removeAt(0);
      });
    });
    setState(() {
      _recording = true;
      _recordCancelled = false;
      _recordDuration = Duration.zero;
    });
    _startRecordingPresence();
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordDuration += const Duration(seconds: 1));
      if (_recordDuration.inSeconds >= 90) {
        unawaited(_stopAndSendVoice());
      }
    });
  }

  Future<void> _cancelRecording() async {
    _stopRecordingPresence();
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _voiceLocked = false;
      _recordCancelled = false;
      _recordDuration = Duration.zero;
      _waveLevels.clear();
    });
  }

  Future<void> _stopAndSendVoice() async {
    if (!_recording || _voiceSending) return;
    _voiceSending = true;
    _recording = false;
    _voiceLocked = false;
    _stopRecordingPresence();
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final clientMessageId = const Uuid().v4();
    try {
      String? path;
      try {
        path = await _audioRecorder.stop();
      } catch (_) {}
      final durationSec = math.max(1, _recordDuration.inSeconds);
      if (!mounted) return;
      setState(() {
        _recording = false;
        _voiceLocked = false;
        _recordCancelled = false;
        _recordDuration = Duration.zero;
        _waveLevels.clear();
      });
      if (durationSec < 1) return;
      if (!kIsWeb && (path == null || path.isEmpty)) return;

      final XFile file;
      if (kIsWeb) {
        if (path == null || path.isEmpty) {
          throw Exception('Не удалось сохранить запись');
        }
        final bytes = await XFile(path).readAsBytes();
        if (bytes.isEmpty) throw Exception('Пустая запись');
        file = XFile.fromData(
          bytes,
          name: 'voice_${DateTime.now().millisecondsSinceEpoch}.webm',
          mimeType: 'audio/webm',
        );
      } else {
        file = XFile(path!);
      }
      if (!mounted) return;
      final mode = await _askSendOrSchedule();
      if (mode == null || !mounted) return;
      if (_isScheduleMode(mode)) {
        await _scheduleVoiceFile(
          file,
          durationSec: durationSec,
          clientMessageId: clientMessageId,
          silent: _scheduleSilent(mode),
        );
        return;
      }
      int? totalBytes;
      try {
        totalBytes = await file.length();
      } catch (_) {
        totalBytes = null;
      }
      _enqueueMediaSend(_PendingMediaSend(
        tempId: _newLocalTempId(),
        kind: _PendingMediaKind.voice,
        file: file,
        clientMessageId: clientMessageId,
        voiceDurationSec: durationSec,
        replyToMessageId: _replyTo?.id,
        totalBytes: totalBytes,
        silent: mode == 'silent',
        topicId: _activeTopicIdForSend,
        anonymous: _effectiveSendAnonymous,
      ));
    } finally {
      _voiceSending = false;
    }
  }

  Future<void> _scheduleVoiceFile(
    XFile file, {
    required int durationSec,
    required String clientMessageId,
    bool silent = false,
  }) async {
    final delivery = await _pickScheduleDelivery();
    if (delivery == null || !mounted) return;
    setState(() {
      _sending = true;
      _uploadProgress = 0.1;
    });
    try {
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: file,
        fileType: 'audio',
        waitForProcessing: false,
        onProgress: (p) {
          if (!mounted) return;
          _setUploadProgress(0.1 + p * 0.8, status: 'Загрузка…');
        },
      );
      final url = uploaded.url;
      if (url == null || url.isEmpty) {
        throw Exception('Не удалось загрузить голосовое');
      }
      final item = await ChatService.scheduleMessage(
        conversationId: widget.conversationId,
        type: 'voice',
        content: '$durationSec',
        mediaUrl: ServerConfig.resolveMediaUrl(url),
        sendAt: delivery.sendAt,
        sendWhenOnline: delivery.sendWhenOnline,
        silent: silent,
        replyToMessageId: _replyTo?.id,
        clientMessageId: clientMessageId,
        topicId: _activeTopicIdForSend,
      );
      if (!mounted) return;
      setState(() => _replyTo = null);
      _showScheduledSnack(item);
      unawaited(_refreshScheduledPendingCount());
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallback: 'Не удалось запланировать голосовое',
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadProgress = null;
        });
      }
    }
  }

  String _copyableText(ChatMessage msg) {
    final text = msg.content.trim();
    if (text.isNotEmpty) return text;
    final media = msg.mediaUrl?.trim();
    if (media != null && media.isNotEmpty) {
      return ServerConfig.resolveMediaUrl(media);
    }
    return _messagePreview(msg);
  }

  /// Share / export preview — clipboard copy stays raw so `[[e:id]]` can be pasted back.
  String _shareableText(ChatMessage msg) =>
      previewTextWithCustomEmoji(_copyableText(msg));

  int _mediaMessageCount() {
    return _messages
        .where(
          (m) =>
              m.mediaUrl != null &&
              m.mediaUrl!.trim().isNotEmpty &&
              (m.type == 'image' ||
                  m.type == 'video' ||
                  m.type == 'file' ||
                  m.type == 'sticker'),
        )
        .length;
  }

  void _enterSelectionMode(ChatMessage initial) {
    setState(() {
      _selectionMode = true;
      _selectedMessageIds
        ..clear()
        ..add(initial.id);
      _replyTo = null;
      _editingMessage = null;
      _controller.clear();
    });
    AppHaptics.selection();
  }

  void _exitSelectionMode() {
    if (!_selectionMode) return;
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleMessageSelection(int messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
    AppHaptics.selection();
  }

  List<ChatMessage> get _selectedMessages => _messages
      .where((m) => _selectedMessageIds.contains(m.id))
      .toList(growable: false);

  Future<void> _deleteSelectedMessages() async {
    final selected = _selectedMessages;
    if (selected.isEmpty) return;

    final canDeleteForAll =
        selected.every(_canDeleteMessageForEveryone);
    final scope = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final err = Theme.of(ctx).colorScheme.error;
        return AlertDialog(
          title: Text(
            selected.length == 1
                ? 'Удалить сообщение?'
                : 'Удалить ${selected.length} сообщ.?',
          ),
          content: Text(
            canDeleteForAll
                ? (_conversation.isGroup && _conversation.amICanDeleteMessages
                    ? 'Можно убрать только у себя или удалить у всех участников.'
                    : 'Можно убрать только у себя или удалить у всех участников (до 48 часов).')
                : 'Выбранные сообщения исчезнут только в вашем чате.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'me'),
              child: Text('Удалить у меня', style: TextStyle(color: err)),
            ),
            if (canDeleteForAll)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'all'),
                child: Text('Удалить у всех', style: TextStyle(color: err)),
              ),
          ],
        );
      },
    );
    if (scope == null || !mounted) return;

    _exitSelectionMode();
    for (final msg in selected) {
      unawaited(_deleteMessage(msg, scope: scope));
    }
  }

  void _copySelectedMessages() {
    final texts = _selectedMessages
        .map(_copyableText)
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    if (texts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нечего копировать')),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: texts));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Скопировано (${_selectedMessageIds.length})')),
    );
  }

  Future<void> _shareSelectedMessages() async {
    final texts = _selectedMessages
        .map(_shareableText)
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    if (texts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нечего отправить')),
      );
      return;
    }
    await SystemShare.shareText(
      context,
      text: texts,
      webSnackBarText: 'Скопировано в буфер обмена',
    );
  }

  Future<void> _shareMessage(ChatMessage msg) async {
    if (_conversation.protectContent) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В этом чате запрещено делиться сообщениями'),
        ),
      );
      return;
    }
    final text = _shareableText(msg);
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нечего отправить')),
      );
      return;
    }
    await SystemShare.shareText(
      context,
      text: text,
      webSnackBarText: 'Скопировано в буфер обмена',
    );
  }

  String _autoDeleteLabel(int value) {
    if (value <= 0) return 'выкл';
    if (value < 3600) return '${value ~/ 60} мин';
    if (value < 24 * 3600) return '${value ~/ 3600} ч';
    final days = value ~/ (24 * 3600);
    return '$days дн.';
  }

  Future<void> _configureAutoDelete() async {
    const presets = <int>[
      0,
      24 * 3600,
      7 * 24 * 3600,
      30 * 24 * 3600,
    ];
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.auto_delete_outlined),
              title: Text('Автоудаление сообщений'),
              subtitle: Text('Старые сообщения удаляются у обоих'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets
                  .map(
                    (seconds) => ChoiceChip(
                      label: Text(
                        seconds <= 0 ? 'Выкл' : _autoDeleteLabel(seconds),
                      ),
                      selected: _conversation.autoDeleteSeconds == seconds,
                      onSelected: (_) => Navigator.pop(ctx, seconds),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null ||
        picked == _conversation.autoDeleteSeconds ||
        !mounted) {
      return;
    }
    final previousSeconds = _conversation.autoDeleteSeconds;
    _applyAutoDeleteSeconds(picked);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          picked <= 0
              ? 'Автоудаление выключено'
              : 'Автоудаление: ${_autoDeleteLabel(picked)}',
        ),
      ),
    );
    try {
      final conv = await ChatService.setAutoDeleteSeconds(
        conversationId: widget.conversationId,
        seconds: picked,
      );
      if (!mounted) return;
      setState(() {
        _conversation = conv;
        _purgeExpiredAutoDeleteMessages(inSetState: true);
      });
      _syncAutoDeleteTicker();
    } catch (e) {
      if (!mounted) return;
      _applyAutoDeleteSeconds(previousSeconds);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _exportChat() async {
    if (_conversation.protectContent) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В этом чате запрещён экспорт сообщений'),
        ),
      );
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final collected = <ChatMessage>[];
      int? cursor;
      var guard = 0;
      while (guard < 200) {
        guard += 1;
        final page = await ChatService.listMessages(
          conversationId: widget.conversationId,
          cursor: cursor,
          limit: 100,
        );
        collected.addAll(page.items);
        if (!page.hasMore || page.nextCursor == null) break;
        cursor = page.nextCursor;
      }
      collected.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final fmt = DateFormat('yyyy-MM-dd HH:mm');
      final buf = StringBuffer()
        ..writeln('HanWe — экспорт чата')
        ..writeln(previewTextWithCustomEmoji(_conversation.displayTitle))
        ..writeln('Сообщений: ${collected.length}')
        ..writeln('---');
      for (final msg in collected) {
        final who = msg.isMine
            ? 'Вы'
            : (msg.senderName?.trim().isNotEmpty == true
                ? previewTextWithCustomEmoji(msg.senderName!.trim())
                : 'Участник');
        final body = previewTextWithCustomEmoji(
          _copyableText(msg),
        ).replaceAll('\n', ' ');
        buf.writeln('${fmt.format(msg.createdAt.toLocal())} · $who: $body');
      }
      final text = buf.toString();
      final filename = 'haneat_chat_${widget.conversationId}.txt';
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (kIsWeb) {
        await SystemShare.shareText(
          context,
          text: text,
          subject: filename,
          webSnackBarText: 'Экспорт скопирован в буфер обмена',
        );
        return;
      }
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(text)),
        mimeType: 'text/plain',
        name: filename,
      );
      await Share.shareXFiles(
        [file],
        text:
            'Экспорт чата «${previewTextWithCustomEmoji(_conversation.displayTitle)}»',
        subject: filename,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  void _replySelectedMessage() {
    final selected = _selectedMessages;
    if (selected.length != 1) return;
    final msg = selected.first;
    setState(() {
      _replyTo = msg;
      _privateReply = null;
      _editingMessage = null;
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
    _scheduleDraftSave();
    _inputFocusNode.requestFocus();
  }

  Future<void> _forwardSelectedMessages() async {
    final selected = _selectedMessages;
    if (selected.isEmpty) return;
    if (_conversation.protectContent) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В этом чате запрещена пересылка сообщений'),
        ),
      );
      return;
    }
    try {
      final chats = await ChatOpenDirect.listForPicker();
      if (!mounted) return;
      final targets =
          chats.where((c) => c.id != widget.conversationId).toList();
      if (targets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет других чатов для пересылки')),
        );
        return;
      }
      final picked = await showChatTargetPickerResult(
        context,
        title: 'Переслать в...',
        chats: targets,
        enableAsCopy: true,
        allowMultiSelect: true,
      );
      if (picked == null || !mounted) return;
      final dests = picked.targets;
      for (final chat in dests) {
        for (final msg in selected) {
          unawaited(() async {
            try {
              await _sendForwardTo(chat, msg, asCopy: picked.asCopy);
              unawaited(ChatThreadPrefetch.warm(chat.id));
            } catch (e) {
              if (!mounted) return;
              if (offerFlexIfRequired(context, e)) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(userVisibleError(e))),
              );
            }
          }());
        }
      }
      _exitSelectionMode();
      final verb = picked.asCopy ? 'Скопировано' : 'Переслано';
      final destLabel = dests.length == 1
          ? '«${previewTextWithCustomEmoji(dests.first.displayTitle)}»'
          : '${dests.length} чатов';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$verb ${selected.length} → $destLabel'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _saveSelectedMessagesToFavorites() async {
    if (_conversation.isSaved) return;
    final selected = _selectedMessages.where((m) => m.id > 0).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала дождитесь отправки')),
      );
      return;
    }
    try {
      final saved = ChatCacheService.peekSavedChat() ??
          await ChatService.ensureSavedChat();
      if (!mounted) return;
      for (final msg in selected) {
        unawaited(
          ChatService.forwardMessage(
            targetConversationId: saved.id,
            sourceConversationId: widget.conversationId,
            messageId: msg.id,
          ),
        );
      }
      unawaited(ChatThreadPrefetch.warm(saved.id));
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('В избранное: ${selected.length}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  void _handleMessageAction(ChatMessage msg, String action) {
    switch (action) {
      case 'reply':
        setState(() {
          _replyTo = msg;
          _privateReply = null;
          _editingMessage = null;
        });
        _scheduleDraftSave();
        break;
      case 'reply_privately':
        unawaited(_messageContactUser(msg.senderId, quoteFrom: msg));
        break;
      case 'copy':
        if (_conversation.protectContent && !msg.isMine) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Копирование в этом чате ограничено'),
            ),
          );
          break;
        }
        Clipboard.setData(ClipboardData(text: _copyableText(msg)));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скопировано')),
        );
        break;
      case 'copy_link':
        unawaited(_copyMessageLink(msg));
        break;
      case 'edit':
        _startEdit(msg);
        break;
      case 'pin':
        _togglePinMessage(msg);
        break;
      case 'forward':
        unawaited(_forwardMessage(msg));
        break;
      case 'share':
        unawaited(_shareMessage(msg));
        break;
      case 'save':
        unawaited(_saveMessageToFavorites(msg));
        break;
      case 'translate':
        unawaited(_translateMessage(msg));
        break;
      case 'report':
        unawaited(_reportMessage(msg));
        break;
      case 'readers':
        unawaited(_showMessageReaders(msg));
        break;
      case 'delete':
        unawaited(_confirmDeleteMessage(msg));
        break;
      case 'select':
        _enterSelectionMode(msg);
        break;
      case 'refund_media':
        unawaited(_refundPaidMedia(msg));
        break;
      case 'tag':
        unawaited(_editSavedMessageTags(msg));
        break;
    }
  }

  Future<void> _loadSavedTags() async {
    if (!_conversation.isSaved) return;
    try {
      final tags = await ChatService.listSavedTags();
      if (!mounted) return;
      setState(() => _savedTags = tags);
    } catch (_) {}
  }

  Future<void> _selectSavedTagFilter(int? tagId) async {
    if (_activeSavedTagId == tagId) return;
    setState(() => _activeSavedTagId = tagId);
    await _load(refresh: true);
  }

  Future<void> _createSavedTagFromBar() async {
    if (!_hasFlexFeature('saved_tags')) {
      await showCreatorUpsell(context);
      return;
    }
    final created = await _promptNewSavedTag();
    if (created == null || !mounted) return;
    setState(() => _savedTags = [..._savedTags, created]);
  }

  Future<ChatSavedTag?> _promptNewSavedTag() async {
    final titleCtrl = TextEditingController();
    final emojiCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый тег'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Название'),
              textCapitalization: TextCapitalization.sentences,
            ),
            TextField(
              controller: emojiCtrl,
              decoration: const InputDecoration(
                labelText: 'Эмодзи (необязательно)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return null;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return null;
    try {
      return await ChatService.createSavedTag(
        title: title,
        emoji: emojiCtrl.text.trim(),
      );
    } catch (e) {
      if (!mounted) return null;
      if (offerFlexIfRequired(context, e)) return null;
      if (offerPackStoreIfRequired(context, e)) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
      return null;
    }
  }

  Future<void> _editSavedMessageTags(ChatMessage msg) async {
    if (msg.id <= 0 || !_conversation.isSaved) return;
    if (!_hasFlexFeature('saved_tags')) {
      await showCreatorUpsell(context);
      return;
    }
    if (_savedTags.isEmpty) await _loadSavedTags();
    if (!mounted) return;
    var selected = msg.savedTagIds.toSet();
    final applied = await showModalBottomSheet<Set<int>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text('Теги сообщения'),
                      trailing: TextButton(
                        onPressed: () async {
                          final created = await _promptNewSavedTag();
                          if (created == null) return;
                          setState(
                            () => _savedTags = [..._savedTags, created],
                          );
                          setLocal(() => selected.add(created.id));
                        },
                        child: const Text('Новый'),
                      ),
                    ),
                    if (_savedTags.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Пока нет тегов'),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final tag in _savedTags)
                              CheckboxListTile(
                                value: selected.contains(tag.id),
                                title: HighlightedText(
                                  text: tag.label,
                                  style: Theme.of(ctx).textTheme.bodyLarge ??
                                      const TextStyle(fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onChanged: (v) {
                                  setLocal(() {
                                    if (v == true) {
                                      selected.add(tag.id);
                                    } else {
                                      selected.remove(tag.id);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, selected),
                      child: const Text('Готово'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (applied == null || !mounted) return;
    try {
      final updated = await ChatService.setSavedMessageTags(
        conversationId: widget.conversationId,
        messageId: msg.id,
        tagIds: applied.toList(),
      );
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        if (idx >= 0) {
          _messages[idx] =
              _messages[idx].copyWith(savedTagIds: updated.savedTagIds);
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _reportMessage(ChatMessage msg) async {
    if (msg.id <= 0 || msg.isMine) return;
    await reportChatMessageWithDialog(
      context,
      conversationId: widget.conversationId,
      messageId: msg.id,
    );
  }

  String _translationSource(ChatMessage msg) {
    final raw = _copyableText(msg).trim();
    if (raw.isEmpty) return '';
    // Reading — preview tokens so translate/auto-translate never 403 on
    // someone else's `[[e:id]]` and the translator does not see the token.
    return previewTextWithCustomEmoji(raw);
  }

  Future<void> _translateMessage(ChatMessage msg) async {
    final source = _translationSource(msg);
    if (source.isEmpty) return;
    try {
      final translated = await ChatService.translateText(text: source);
      if (!mounted) return;
      if (translated.trim().isEmpty || translated.trim() == source) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Перевод недоступен или не изменился')),
        );
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Перевод',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  HighlightedText(
                    text: translated,
                    style: Theme.of(ctx).textTheme.bodyLarge ??
                        const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: previewTextWithCustomEmoji(translated),
                          ),
                        );
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Перевод скопирован')),
                        );
                      },
                      icon: Icon(Icons.copy_rounded, color: scheme.primary),
                      label: const Text('Копировать'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  String _editHistoryBody(String content, String messageType) {
    final text = content.trim();
    switch (messageType) {
      case 'image':
        return text.isEmpty
            ? '📷 Фото'
            : '📷 Подпись: ${previewTextWithCustomEmoji(text)}';
      case 'video':
        return text.isEmpty
            ? '🎬 Видео'
            : '🎬 Подпись: ${previewTextWithCustomEmoji(text)}';
      case 'video_note':
        return text.isEmpty
            ? '⭕ Видеосообщение'
            : '⭕ Подпись: ${previewTextWithCustomEmoji(text)}';
      case 'file':
        return text.isEmpty
            ? '📎 Файл'
            : '📎 ${previewTextWithCustomEmoji(text)}';
      case 'voice':
        return '🎤 Голосовое';
      case 'sticker':
        return '🧩 Стикер';
      case 'poll':
        return text.isEmpty ? '📊 Опрос' : '📊 ${previewTextWithCustomEmoji(text)}';
      case 'checklist':
        return ChatChecklist.tryParse(content)?.preview ?? '☑ Чеклист';
      case 'location':
        return '📍 Геопозиция';
      default:
        return text.isEmpty ? '—' : previewTextWithCustomEmoji(text);
    }
  }

  String _editHistorySubtitle({
    required DateTime? at,
    int? editorId,
    String? fallbackLabel,
  }) {
    final parts = <String>[];
    if (fallbackLabel != null && fallbackLabel.isNotEmpty) {
      parts.add(fallbackLabel);
    }
    if (editorId != null && editorId > 0) {
      final name = _displayNameForUserId(editorId);
      if (name != null && name.isNotEmpty) {
        parts.add(previewTextWithCustomEmoji(name));
      }
    }
    if (at != null) parts.add(formatChatMessageTime(at));
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  Future<void> _showReadTime(ChatMessage msg) async {
    if (!msg.isMine || !msg.isRead) return;
    if (!_hasFlexFeature('read_timestamps')) {
      await showCreatorUpsell(context);
      return;
    }
    final at = _conversation.peerReadAt;
    final text = at == null
        ? 'Прочитано'
        : 'Прочитано ${formatChatMessageTime(at)}';
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showMessageEditHistory(ChatMessage msg) async {
    if (msg.id <= 0 || !msg.isEdited) return;
    if (!_hasFlexFeature('edit_history')) {
      await showCreatorUpsell(context);
      return;
    }
    try {
      final history = await ChatService.listMessageEdits(
        conversationId: widget.conversationId,
        messageId: msg.id,
      );
      if (!mounted) return;
      final msgType = history.messageType.isNotEmpty
          ? history.messageType
          : msg.type;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          final items = history.items;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.paddingOf(ctx).bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'История изменений',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _editHistoryBody(
                              history.currentContent,
                              msgType,
                            ),
                          ),
                          subtitle: Text(
                            _editHistorySubtitle(
                              at: msg.editedAt,
                              editorId: msg.senderId,
                              fallbackLabel: 'Текущая версия',
                            ),
                            style: TextStyle(color: scheme.primary),
                          ),
                        ),
                        if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('Предыдущие версии недоступны'),
                          )
                        else
                          ...items.map(
                            (item) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                _editHistoryBody(item.content, msgType),
                              ),
                              subtitle: Text(
                                _editHistorySubtitle(
                                  at: item.editedAt,
                                  editorId: item.editorId,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _showMessageReaders(ChatMessage msg) async {
    if (msg.id <= 0) return;
    if (!_hasFlexFeature('group_readers')) {
      await showCreatorUpsell(context);
      return;
    }
    await showChatMessageReadersSheet(
      context,
      conversationId: widget.conversationId,
      messageId: msg.id,
    );
  }

  Future<void> _confirmDeleteMessage(ChatMessage msg) async {
    final canDeleteForAll = _canDeleteMessageForEveryone(msg);
    final scope = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final err = Theme.of(ctx).colorScheme.error;
        return AlertDialog(
          title: const Text('Удалить сообщение?'),
          content: Text(
            canDeleteForAll
                ? (_conversation.isGroup && _conversation.amICanDeleteMessages
                    ? 'Можно убрать только у себя или удалить у всех участников.'
                    : 'Можно убрать только у себя или удалить у всех участников (до 48 часов).')
                : msg.isMine
                    ? 'Прошло больше 48 часов — можно удалить только у себя.'
                    : 'Сообщение исчезнет только в вашем чате.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'me'),
              child: Text('Удалить у меня', style: TextStyle(color: err)),
            ),
            if (canDeleteForAll)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'all'),
                child: Text('Удалить у всех', style: TextStyle(color: err)),
              ),
          ],
        );
      },
    );
    if (scope != null && mounted) {
      await _deleteMessage(msg, scope: scope);
    }
  }

  Widget _failedSendActions(int tempId, ColorScheme scheme) {
    final retryIn = _failedTextAutoRetryRemainingSeconds(tempId);
    final autoRetrying = retryIn > 0;
    // Compact Telegram-like footer — no giant Retry/Delete row under every bubble.
    return Padding(
      padding: const EdgeInsets.only(top: 1, bottom: 2, right: 2),
      child: GestureDetector(
        onTap: _sending || autoRetrying ? null : () => _retryFailedText(tempId),
        onLongPress: _sending ? null : () => _discardFailedText(tempId),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 13, color: scheme.error),
            const SizedBox(width: 4),
            Text(
              autoRetrying
                  ? 'Повтор через ${_formatSlowModeCountdown(retryIn)}'
                  : 'Не отправлено',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                    fontSize: 11.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBubbleWidget({
    required ChatMessage msg,
    required ColorScheme scheme,
    required bool searching,
    bool isActiveSearchMatch = false,
    required bool isGroup,
    _MessageCluster cluster = const _MessageCluster.single(),
    String? replyQuote,
    String? replyAuthor,
    VoidCallback? onReplyTap,
    bool interactive = true,
    bool wrapWithAlign = true,
    ValueChanged<int>? onPollVote,
    bool pollVoting = false,
    VoidCallback? onPollClose,
    bool pollClosing = false,
    VoidCallback? onShowPollVoters,
    VoidCallback? onAddPollOption,
    void Function(int index, bool done)? onChecklistToggle,
    bool checklistBusy = false,
    VoidCallback? onTranscribe,
    bool transcribing = false,
    ValueChanged<ChatInlineKeyboardButton>? onInlineButtonTap,
    Set<String> callbackLoadingData = const <String>{},
  }) {
    if (!_selectionMode && !searching) {
      final visible = _visibleMessages;
      final currentIndex = visible.indexWhere((m) => m.id == msg.id);
      if (currentIndex >= 0) {
        if (currentIndex > 0 &&
            _canMergePhotoAlbum(visible[currentIndex - 1], msg)) {
          return const SizedBox.shrink();
        }
        if (_isPhotoAlbumEligible(msg)) {
          final album = <ChatMessage>[msg];
          final grouped = (msg.mediaGroupId?.trim() ?? '').isNotEmpty;
          var captionSeen = msg.content.trim().isNotEmpty;
          var i = currentIndex + 1;
          while (i < visible.length &&
              _canMergePhotoAlbum(album.last, visible[i])) {
            final next = visible[i];
            final nextHasCaption = next.content.trim().isNotEmpty;
            if (!grouped && nextHasCaption && captionSeen) break;
            album.add(next);
            if (!grouped && nextHasCaption) {
              captionSeen = true;
              break;
            }
            if (album.length >= 10) break;
            i++;
          }
          if (album.length >= 2) {
            return _messageAlbumBubbleWidget(
              messages: album,
              scheme: scheme,
              wrapWithAlign: wrapWithAlign,
            );
          }
        }
      }
    }

    final pendingMedia = msg.id < 0 ? _pendingMediaByTempId[msg.id] : null;
    if (pendingMedia != null) {
      return _pendingMediaBubbleWidget(
        msg: msg,
        pending: pendingMedia,
        scheme: scheme,
        wrapWithAlign: wrapWithAlign,
      );
    }
    final isFailed = msg.isMine &&
        (_failedTextSends.containsKey(msg.id) ||
            _failedReadySends.containsKey(msg.id) ||
            (_pendingMediaRetry?.tempId == msg.id));
    // Temp ids (< 0) that are not failed = still sending (Telegram clock).
    final isPending = msg.isMine && msg.id < 0 && !isFailed;
    return _Bubble(
      message: msg,
      translation: _autoTranslations[msg.id],
      scheme: scheme,
      isPending: isPending,
      isFailed: isFailed,
      autoDeleteSeconds: _conversation.autoDeleteSeconds,
      highlightQuery: searching ? _threadSearchQuery : null,
      isActiveSearchMatch: isActiveSearchMatch,
      replyQuote: replyQuote,
      replyAuthor: replyAuthor,
      onReplyTap: onReplyTap,
      showSenderName: isGroup && !msg.isMine && cluster.starts,
      senderLabel: msg.senderName ?? _senderNames[msg.senderId],
      onSenderTap:
          isGroup && !msg.isMine ? () => _openUserProfile(msg.senderId) : null,
      isConversationPinned: _isMessagePinned(msg.id),
      cluster: cluster,
      wrapWithAlign: wrapWithAlign,
      onPollVote: onPollVote,
      pollVoting: pollVoting,
      onPollClose: onPollClose,
      pollClosing: pollClosing,
      onShowPollVoters: onShowPollVoters,
      onAddPollOption: onAddPollOption,
      onChecklistToggle: onChecklistToggle,
      checklistBusy: checklistBusy,
      onTranscribe: onTranscribe,
      transcribing: transcribing,
      onInlineButtonTap: onInlineButtonTap,
      callbackLoadingData: callbackLoadingData,
      onImageTap: interactive &&
              (msg.type == 'image' || _canOpenStickerInImageViewer(msg)) &&
              msg.mediaUrl != null
          ? () => _openImage(msg.mediaUrl!)
          : null,
      onVideoTap: interactive && msg.type == 'video' && msg.mediaUrl != null
          ? () => _openVideo(msg.mediaUrl!)
          : null,
      onReactionTap:
          interactive ? (emoji) => _toggleReaction(msg, emoji) : null,
      onReactionLongPress: interactive && msg.id > 0
          ? (emoji) => unawaited(_showMessageReactors(msg, emoji: emoji))
          : null,
      onUnlockPaidMedia: interactive && msg.isLockedPaidMedia
          ? () => unawaited(_unlockPaidMedia(msg))
          : null,
      unlockingPaidMedia: _unlockingMessageIds.contains(msg.id),
      onPaidReaction: interactive && !msg.isMine && msg.id > 0
          ? () => unawaited(_sendPaidReaction(msg))
          : null,
      onConvertGift: interactive &&
              !msg.isMine &&
              msg.type == 'gift' &&
              _userGiftIdFromMessage(msg) != null &&
              !_giftMessageIsCollectible(msg)
          ? () => unawaited(_convertReceivedGift(msg))
          : null,
      onKeepGift: interactive &&
              !msg.isMine &&
              msg.type == 'gift' &&
              _userGiftIdFromMessage(msg) != null
          ? () => unawaited(_keepReceivedGift(msg))
          : null,
      onRefundGift: interactive &&
              msg.isMine &&
              msg.type == 'gift' &&
              _userGiftIdFromMessage(msg) != null &&
              !_giftMessageIsCollectible(msg) &&
              _giftStatusAllowsRefund(msg) &&
              _withinStarsRefundWindow(msg.createdAt)
          ? () => unawaited(_refundSentGift(msg))
          : null,
      giftActionBusy: _giftActionMessageIds.contains(msg.id),
      spoilerRevealed: _revealedSpoilerIds.contains(msg.id),
      onRevealSpoiler: interactive && msg.hasSpoiler
          ? () => setState(() => _revealedSpoilerIds.add(msg.id))
          : null,
      onStopLiveLocation: interactive && msg.isMine
          ? () => unawaited(_stopLiveLocation(msg))
          : null,
      onFileTap: interactive && msg.type == 'file' && msg.mediaUrl != null
          ? () => _openFileUrl(msg.mediaUrl!)
          : null,
      onOpenContactUser:
          interactive ? (userId) => _openUserProfile(userId) : null,
      onMessageContactUser: interactive
          ? (userId) => unawaited(_messageContactUser(userId))
          : null,
      onSaveContactToPhone: interactive
          ? (contact) => unawaited(_saveContactToPhone(contact))
          : null,
      onAddHanContact: interactive
          ? (userId) => unawaited(_addHanContactFromBubble(userId))
          : null,
      onMentionTap: interactive ? _openMentionProfile : null,
      mentionLabels: _mentionLabels,
      onForwardFromTap: interactive && msg.isForwarded
          ? () => unawaited(_onForwardAttributionTap(msg))
          : null,
      onVoiceCompleted: interactive ? _playNextVoiceAfter : null,
      onEditedTap: interactive && msg.isEdited && msg.id > 0
          ? () => unawaited(_showMessageEditHistory(msg))
          : null,
      onReadTimeTap: interactive &&
              !isGroup &&
              msg.isMine &&
              msg.isRead &&
              msg.id > 0
          ? () => unawaited(_showReadTime(msg))
          : null,
      onReadersTap: interactive &&
              isGroup &&
              msg.isMine &&
              msg.id > 0 &&
              msg.readCount > 0
          ? () => unawaited(_showMessageReaders(msg))
          : null,
      onCallTap: interactive && msg.type == 'call'
          ? () => unawaited(_redialFromCallMessage(msg))
          : null,
      outgoingBubbleColor: msg.isMine
          ? _bubbleAccent.outgoingColor(
              isDark: Theme.of(context).brightness == Brightness.dark,
            )
          : null,
    );
  }

  bool _isPhotoAlbumEligible(ChatMessage msg) {
    if (msg.type != 'image' && msg.type != 'video') return false;
    if (msg.replyToMessageId != null) return false;
    final groupId = msg.mediaGroupId?.trim();
    final hasGroup = groupId != null && groupId.isNotEmpty;
    final media = msg.mediaUrl?.trim();
    final hasMedia = media != null && media.isNotEmpty;
    // Locked paid album items have no media_url until unlock.
    if (hasGroup && msg.isLockedPaidMedia) return true;
    // Server albums: allow temp ids once grouped; need media for grid.
    if (hasGroup) return hasMedia || msg.id < 0;
    // Legacy heuristic: confirmed image messages only.
    if (msg.id <= 0) return false;
    if (msg.type != 'image') return false;
    return hasMedia;
  }

  bool _canMergePhotoAlbum(ChatMessage left, ChatMessage right) {
    if (!_isPhotoAlbumEligible(left) || !_isPhotoAlbumEligible(right)) {
      return false;
    }
    if (left.senderId != right.senderId || left.isMine != right.isMine) {
      return false;
    }
    final lg = left.mediaGroupId?.trim();
    final rg = right.mediaGroupId?.trim();
    if (lg != null && lg.isNotEmpty && rg != null && rg.isNotEmpty) {
      return lg == rg;
    }
    // Heuristic fallback for older messages without media_group_id.
    if (left.type != 'image' || right.type != 'image') return false;
    if (left.content.trim().isNotEmpty) return false;
    if (left.id <= 0 || right.id <= 0) return false;
    final diff = right.createdAt.difference(left.createdAt).inSeconds.abs();
    return diff <= 90;
  }

  Widget _messageAlbumBubbleWidget({
    required List<ChatMessage> messages,
    required ColorScheme scheme,
    required bool wrapWithAlign,
  }) {
    final anchor = messages.last;
    final mine = anchor.isMine;
    final caption = anchor.content.trim();
    final hasCaption = caption.isNotEmpty;
    final lockedPaid = messages.where((m) => m.isLockedPaidMedia).toList();
    if (lockedPaid.isNotEmpty && lockedPaid.length == messages.length) {
      final price = lockedPaid
          .map((m) => m.priceStars)
          .fold<int>(0, (a, b) => a > b ? a : b);
      final unlockTarget = lockedPaid.first;
      final lockBubble = PaidMediaLockBubble(
        priceStars: price,
        loading: _unlockingMessageIds.contains(unlockTarget.id),
        onUnlock: () => unawaited(_unlockPaidMedia(unlockTarget)),
      );
      if (!wrapWithAlign) return lockBubble;
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: lockBubble,
      );
    }
    final albumItems = messages
        .where((m) => (m.mediaUrl?.trim() ?? '').isNotEmpty)
        .toList(growable: false);
    if (albumItems.length < 2) return const SizedBox.shrink();
    final fg = mine && Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : scheme.onSurface;
    final isPending = mine && anchor.id < 0;
    final isFailed = mine &&
        (_failedTextSends.containsKey(anchor.id) ||
            _failedReadySends.containsKey(anchor.id) ||
            _pendingMediaRetry?.tempId == anchor.id);
    final status = mine
        ? _outgoingStatusVisual(
            isPending: isPending,
            isFailed: isFailed,
            isDelivered: anchor.isDelivered,
            isRead: anchor.isRead,
            fg: fg,
            scheme: scheme,
          )
        : null;
    final album = Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _chatAlbumGrid(
            items: albumItems,
            borderRadius: BorderRadius.circular(12),
            // No-caption albums: meta only on the grid (Telegram-style).
            footerOverlay: hasCaption
                ? null
                : _albumMetaOverlay(
                    anchor: anchor,
                    mine: mine,
                    fg: fg,
                    isPending: isPending,
                    isFailed: isFailed,
                    scheme: scheme,
                  ),
          ),
          if (hasCaption)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HighlightedText(
                    text: caption,
                    style: TextStyle(
                      color: fg,
                      height: 1.24,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_conversation.autoDeleteSeconds > 0) ...[
                        Icon(
                          Icons.timer_outlined,
                          size: 10.5,
                          color: fg.withValues(alpha: 0.62),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          formatAutoDeleteRemaining(
                            anchor.createdAt,
                            _conversation.autoDeleteSeconds,
                          ),
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.62),
                            fontSize: 10.5,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        formatChatMessageTime(anchor.createdAt),
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.62),
                          fontSize: 10.5,
                          height: 1.08,
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(width: 3),
                        Icon(status.$1, size: 12.5, color: status.$2),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!wrapWithAlign) return album;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: album,
    );
  }

  Widget _chatAlbumGrid({
    required List<ChatMessage> items,
    required BorderRadius borderRadius,
    Widget? footerOverlay,
  }) {
    final spacing = 1.0;
    final displayItems = items.take(9).toList(growable: false);
    final count = displayItems.length;
    if (count < 2) return const SizedBox.shrink();

    Widget tile(ChatMessage msg, {required int index, int? remaining}) {
      final url = msg.mediaUrl!.trim();
      final isVideo = msg.type == 'video';
      return GestureDetector(
        onTap: () {
          if (isVideo) {
            _openVideo(url);
          } else {
            _openImage(url);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _chatAlbumImage(url),
            if (isVideo && (remaining == null || remaining <= 0))
              const Align(
                alignment: Alignment.center,
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white70,
                  size: 34,
                ),
              ),
            if (remaining != null && remaining > 0)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.42),
                child: Center(
                  child: Text(
                    '+$remaining',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    Widget body;
    if (count == 2) {
      body = SizedBox(
        height: 214,
        child: Row(
          children: [
            Expanded(child: tile(displayItems[0], index: 0)),
            SizedBox(width: spacing),
            Expanded(child: tile(displayItems[1], index: 1)),
          ],
        ),
      );
    } else if (count == 3) {
      body = SizedBox(
        height: 234,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: tile(displayItems[0], index: 0),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: tile(displayItems[1], index: 1)),
                  SizedBox(height: spacing),
                  Expanded(child: tile(displayItems[2], index: 2)),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      final remaining = items.length - 4;
      body = SizedBox(
        height: 244,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: tile(displayItems[0], index: 0)),
                  SizedBox(width: spacing),
                  Expanded(child: tile(displayItems[1], index: 1)),
                ],
              ),
            ),
            SizedBox(height: spacing),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: tile(displayItems[2], index: 2)),
                  SizedBox(width: spacing),
                  Expanded(
                    child: tile(
                      displayItems[3],
                      index: 3,
                      remaining: remaining > 0 ? remaining : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: [
          ColoredBox(
            color: Colors.black.withValues(alpha: 0.08),
            child: body,
          ),
          if (footerOverlay != null)
            Positioned(
              right: 6,
              bottom: 6,
              child: footerOverlay,
            ),
        ],
      ),
    );
  }

  Widget _chatAlbumImage(String mediaUrl) {
    final resolved = ServerConfig.resolvePublisherAvatarUrl(
      ServerConfig.resolveMediaUrl(mediaUrl),
    );
    final animated =
        _chatIsGifMediaUrl(resolved) || _chatIsGifMediaUrl(mediaUrl);
    return CachedNetworkImage(
      imageUrl: resolved,
      fit: BoxFit.cover,
      memCacheWidth: animated ? null : 720,
      memCacheHeight: animated ? null : 720,
      maxWidthDiskCache: animated ? null : 960,
      maxHeightDiskCache: animated ? null : 960,
      progressIndicatorBuilder: (_, __, progress) => ColoredBox(
        color: const Color(0x22000000),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress.progress,
              color: Colors.white70,
            ),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.22),
        child: const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white70),
        ),
      ),
    );
  }

  Widget _albumMetaOverlay({
    required ChatMessage anchor,
    required bool mine,
    required Color fg,
    required bool isPending,
    required bool isFailed,
    required ColorScheme scheme,
  }) {
    final status = mine
        ? _outgoingStatusVisual(
            isPending: isPending,
            isFailed: isFailed,
            isDelivered: anchor.isDelivered,
            isRead: anchor.isRead,
            fg: fg,
            scheme: scheme,
            onMedia: true,
          )
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatChatMessageTime(anchor.createdAt),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
            if (status != null) ...[
              const SizedBox(width: 2),
              Icon(status.$1, size: 12, color: status.$2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pendingMediaBubbleWidget({
    required ChatMessage msg,
    required _PendingMediaSend pending,
    required ColorScheme scheme,
    required bool wrapWithAlign,
  }) {
    final isUploading =
        _inFlightMediaClientIds.contains(pending.clientMessageId);
    final isQueued = _mediaOutboundQueue
        .any((p) => p.clientMessageId == pending.clientMessageId);
    final isFailed =
        _pendingMediaRetry?.clientMessageId == pending.clientMessageId;
    final progress =
        _pendingMediaProgressByClientId[pending.clientMessageId] ?? 0.0;
    final statusLabel = isFailed
        ? 'Не отправлено'
        : isUploading
            ? _mediaUploadProgressLabel(
                pending,
                progress,
                totalBytes: pending.totalBytes,
              )
            : (isQueued ? 'В очереди…' : _mediaStatusLabel(pending));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleBg = _bubbleAccent.outgoingColor(isDark: isDark);
    final width = switch (pending.kind) {
      _PendingMediaKind.image => 210.0,
      _PendingMediaKind.video => 210.0,
      _PendingMediaKind.file => 220.0,
      _PendingMediaKind.voice => 210.0,
    };
    final height = switch (pending.kind) {
      _PendingMediaKind.image => 220.0,
      _PendingMediaKind.video => 220.0,
      _PendingMediaKind.file => 80.0,
      _PendingMediaKind.voice => 76.0,
    };

    Widget content;
    if (pending.kind == _PendingMediaKind.image &&
        pending.previewBytes != null) {
      content = Image.memory(
        pending.previewBytes!,
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    } else if (pending.kind == _PendingMediaKind.video) {
      content = ColoredBox(
        color: Colors.black.withValues(alpha: 0.25),
        child: SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: Icon(Icons.movie_creation_outlined, color: Colors.white70),
          ),
        ),
      );
    } else if (pending.kind == _PendingMediaKind.file) {
      content = SizedBox(
        width: width,
        height: height,
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.insert_drive_file_outlined, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                pending.fileName ?? 'Файл',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      );
    } else {
      content = SizedBox(
        width: width,
        height: height,
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.mic_none_rounded, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${pending.voiceDurationSec ?? 1} c',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      );
    }

    final bubble = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        height: height,
        color: bubbleBg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (!isFailed)
              Container(color: Colors.black.withValues(alpha: 0.25))
            else
              Container(color: scheme.error.withValues(alpha: 0.18)),
            Positioned(
              left: 10,
              right: 56,
              top: 8,
              child: Text(
                statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _cancelPendingMediaUploadByTempId(msg.id),
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
            if (!isFailed)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 2.5,
                  backgroundColor: Colors.white24,
                  color: _uploadAccent,
                ),
              ),
            // Telegram corner: time + clock / error while media is outgoing.
            Positioned(
              right: 8,
              bottom: isFailed ? 8 : 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatChatMessageTime(msg.createdAt),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        isFailed ? Icons.error_outline : Icons.access_time,
                        size: 12,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final withMeta = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        bubble,
        if (isFailed)
          Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 2),
            child: GestureDetector(
              onTap: _sending ? null : _retryPendingMedia,
              onLongPress: _sending ? null : _discardPendingMedia,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 13, color: scheme.error),
                  const SizedBox(width: 4),
                  Text(
                    'Не отправлено',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.error,
                          fontSize: 11.5,
                        ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (!wrapWithAlign) return withMeta;
    return Align(
      alignment: Alignment.centerRight,
      child: withMeta,
    );
  }

  Widget _uploadTickerBar(ColorScheme scheme) {
    final progress = (_uploadProgress ?? 0).clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();
    return Material(
      color: scheme.surfaceContainerLow.withValues(alpha: 0.95),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Row(
              children: [
                Text(
                  '$percent%',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _sendingStatus,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
            color: _uploadAccent,
          ),
        ],
      ),
    );
  }

  double _overlayComposerReserve() {
    final panelBox =
        _composerPanelKey.currentContext?.findRenderObject() as RenderBox?;
    if (panelBox != null && panelBox.hasSize) {
      return panelBox.size.height + 8;
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    const composerRow = 56.0;
    const bannerRow = 52.0;
    var reserve = bottom + keyboard + composerRow + 12;
    if (_replyTo != null || _privateReply != null) reserve += bannerRow;
    if (_editingMessage != null) reserve += bannerRow;
    if (_composerLinkPreviewUrl != null && _editingMessage == null) {
      reserve += 72;
    }
    if (_recording) reserve += 96;
    if (_sending || _uploadProgress != null) reserve += 40;
    return reserve;
  }

  Future<void> _showMessageActionOverlay(
    ChatMessage msg,
    RenderBox bubbleBox,
  ) async {
    if (_selectionMode) return;
    var rect = Rect.fromPoints(
      bubbleBox.localToGlobal(Offset.zero),
      bubbleBox.localToGlobal(bubbleBox.size.bottomRight(Offset.zero)),
    );
    final composerReserve = _overlayComposerReserve();
    final screenH = MediaQuery.sizeOf(context).height;
    final padding = MediaQuery.paddingOf(context);
    final targetBottom = screenH - composerReserve - 16;
    final isGroup = _conversation.isGroup;
    final canShowReaders = msg.isMine && isGroup && msg.id > 0;
    final canReplyPrivately = isGroup && !msg.isMine && msg.senderId > 0;
    final canSaveToFavorites = msg.id > 0 && !_conversation.isSaved;
    final menuItemCount = 4 +
        (msg.isMine &&
                (msg.type == 'text' ||
                    msg.type == 'image' ||
                    msg.type == 'video' ||
                    msg.type == 'file')
            ? 1
            : 0) +
        (_copyableText(msg).isNotEmpty ? 2 : 0) + // copy + share
        (msg.isMine ? 1 : 0) +
        (canShowReaders ? 1 : 0) +
        (canReplyPrivately ? 1 : 0) +
        (canSaveToFavorites ? 1 : 0) +
        (_conversation.isSaved && msg.id > 0 ? 1 : 0) +
        (msg.id > 0 ? 1 : 0) + // copy link
        1; // reply, pin, forward, select + optional
    final preLayout = ChatMessageOverlayLayout.compute(
      messageRect: rect,
      screenSize: MediaQuery.sizeOf(context),
      padding: padding,
      menuItemCount: menuItemCount,
      hasDivider: msg.isMine,
      reactionCount: _overlayReactions.length,
      isOutgoing: msg.isMine,
      bottomComposerReserve: composerReserve,
    );
    final menuH = menuItemCount * 46 + (msg.isMine ? 8 : 0);
    final clusterOverflow = preLayout.menuTop + menuH - (targetBottom - 8);
    if (clusterOverflow > 0 && _scroll.hasClients) {
      await _scroll.animateTo(
        (_scroll.offset + clusterOverflow)
            .clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      rect = Rect.fromPoints(
        bubbleBox.localToGlobal(Offset.zero),
        bubbleBox.localToGlobal(bubbleBox.size.bottomRight(Offset.zero)),
      );
    } else if (rect.bottom > targetBottom - 80 && _scroll.hasClients) {
      final delta = rect.bottom - (targetBottom - 80);
      await _scroll.animateTo(
        (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      rect = Rect.fromPoints(
        bubbleBox.localToGlobal(Offset.zero),
        bubbleBox.localToGlobal(bubbleBox.size.bottomRight(Offset.zero)),
      );
    }
    final isPinned = _isMessagePinned(msg.id);
    final scheme = Theme.of(context).colorScheme;
    final searching = _threadSearchQuery.trim().isNotEmpty;
    final replyTarget = _replyTargetFor(msg);
    final replyQuote = replyTarget != null
        ? _messagePreview(replyTarget)
        : (msg.replyToMessageId != null ? 'Сообщение' : null);
    final replyAuthor = replyTarget == null
        ? null
        : (replyTarget.isMine
            ? 'Вы'
            : (replyTarget.senderName ??
                _senderNames[replyTarget.senderId] ??
                'Сообщение'));

    final protectContent = _conversation.protectContent;
    final copyable = _copyableText(msg).isNotEmpty;
    await ChatMessageActionOverlay.show(
      context: context,
      messageRect: rect,
      isOutgoing: msg.isMine,
      bottomComposerReserve: composerReserve,
      messagePreview: SizedBox(
        width: rect.width,
        child: _messageBubbleWidget(
          msg: msg,
          scheme: scheme,
          searching: searching,
          isGroup: isGroup,
          replyQuote: replyQuote,
          replyAuthor: replyAuthor,
          onReplyTap: null,
          wrapWithAlign: false,
        ),
      ),
      quickReactions: _overlayReactions,
      canEdit: msg.isMine &&
          msg.id > 0 &&
          (msg.type == 'text' ||
              msg.type == 'image' ||
              msg.type == 'video' ||
              msg.type == 'file'),
      isPinned: isPinned,
      canPin: _canPinMessages && msg.id > 0 && !_conversation.isSaved,
      canDelete: msg.id > 0 &&
          (msg.isMine ||
              (_conversation.isGroup && _conversation.amICanDeleteMessages)),
      hasCopyableText: copyable && (!protectContent || msg.isMine),
      canShowReaders: canShowReaders,
      canSaveToFavorites: canSaveToFavorites && !protectContent,
      canReplyPrivately: canReplyPrivately,
      canCopyLink: msg.id > 0,
      canForward: !protectContent,
      canTranslate: copyable &&
          SubscriptionStatusCache.peek()?.hasFeature('chat_translation') ==
              true,
      canReport: !msg.isMine && msg.id > 0,
      canRefundPaidMedia: msg.isMine &&
          msg.id > 0 &&
          msg.isPaid &&
          msg.priceStars > 0 &&
          _withinStarsRefundWindow(msg.createdAt),
      canTagSaved: _conversation.isSaved && msg.id > 0,
      onReaction: (emoji) => _toggleReaction(msg, emoji),
      onExpandReactions: () => _showReactionPicker(msg),
      onAction: (action) => _handleMessageAction(msg, action),
    );
  }

  Future<void> _copyMessageLink(ChatMessage msg) async {
    if (msg.id <= 0) return;
    final link = ShareLinkService.chatLink(
      widget.conversationId,
      messageId: msg.id,
    );
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка на сообщение скопирована')),
    );
  }

  bool _isScheduleMode(String? mode) =>
      mode == 'schedule' || mode == 'schedule_silent';

  bool _scheduleSilent(String? mode) => mode == 'schedule_silent';

  Widget _silentSendTile({
    required BuildContext sheetContext,
    required String mode,
    required String title,
    String? subtitle,
    IconData icon = Icons.notifications_off_outlined,
  }) {
    final allowed = _hasFlexFeature('silent_send');
    return ListTile(
      leading: Icon(allowed ? icon : Icons.lock_outline),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: () async {
        if (!allowed) {
          await showCreatorUpsell(context);
          return;
        }
        Navigator.pop(sheetContext, mode);
      },
    );
  }

  Future<String?> _askSendOrSchedule() {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.send_rounded),
              title: const Text('Отправить сейчас'),
              onTap: () => Navigator.pop(ctx, 'now'),
            ),
            _silentSendTile(
              sheetContext: ctx,
              mode: 'silent',
              title: 'Без звука',
              subtitle: 'Получатель не получит уведомление',
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Отложить'),
              onTap: () => Navigator.pop(ctx, 'schedule'),
            ),
            _silentSendTile(
              sheetContext: ctx,
              mode: 'schedule_silent',
              title: 'Отложить без звука',
              subtitle: 'Отправка позже, без push-уведомления',
              icon: Icons.schedule_send_outlined,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _selectionIndicator(bool selected, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: 2,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
            : null,
      ),
    );
  }

  Widget _animatedVisibility({
    required bool visible,
    required Widget child,
    required String keyName,
  }) {
    return AnimatedSwitcher(
      duration: _uiAnimDuration,
      reverseDuration: const Duration(milliseconds: 130),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, -0.05),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: slide,
            child: SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: child,
            ),
          ),
        );
      },
      child: visible
          ? KeyedSubtree(key: ValueKey(keyName), child: child)
          : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }

  String _composerHintText({
    required bool canCompose,
    required bool peerBlockedByMe,
    required bool isRestrictedByModeration,
    required int activeCooldownSeconds,
  }) {
    if (!canCompose) {
      if (peerBlockedByMe) return 'Пользователь заблокирован';
      if (_selectedTopicIsClosed) return 'Тема закрыта';
      if (isRestrictedByModeration) return 'Отправка ограничена';
      return 'Только админы';
    }
    if (activeCooldownSeconds > 0) {
      return 'Подождите ${_formatSlowModeCountdown(activeCooldownSeconds)}';
    }
    if (_editingMessage != null) return 'Изменить…';
    final raw = _replyKeyboard?.placeholder?.trim() ?? '';
    if (raw.isEmpty) return 'Сообщение';
    return previewTextWithCustomEmoji(raw);
  }

  Widget _buildReplyKeyboardStrip(ColorScheme scheme) {
    final kb = _replyKeyboard;
    if (kb == null || kb.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1A2632)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in kb.rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (var i = 0; i < row.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              unawaited(_tapReplyKeyboardButton(row[i])),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.onSurface,
                            side: BorderSide(
                              color: scheme.outline.withValues(alpha: 0.45),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                          ),
                          child: HighlightedText(
                            text: row[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelLarge ??
                                const TextStyle(fontSize: 14),
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
    );
  }

  Future<void> _tapReplyKeyboardButton(String text) async {
    final label = text.trim();
    if (label.isEmpty) return;
    _controller.text = label;
    _controller.selection = TextSelection.collapsed(offset: label.length);
    if (_replyKeyboard?.oneTime == true) {
      setState(() => _replyKeyboard = null);
    }
    await _sendText();
  }

  Widget _compactComposerStrip({
    required IconData icon,
    required String label,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            if (secondaryActionLabel != null)
              TextButton(
                onPressed: onSecondaryAction,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(secondaryActionLabel),
              ),
            if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: scheme.primary,
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _telegramReplyStrip({
    required String author,
    required String preview,
    required VoidCallback onClose,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1A2632)
          : scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 2, 6),
        child: Row(
          children: [
            Container(
              width: 2.5,
              height: 34,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HighlightedText(
                      text: author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    HighlightedText(
                      text: preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Отменить ответ',
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _composerInfoBanner({
    required Color backgroundColor,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? foregroundColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fg = foregroundColor ?? scheme.onSurface;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
      child: Row(
        crossAxisAlignment: subtitle == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: subtitle == null ? 0 : 1),
            child: Icon(icon, size: 18, color: fg.withValues(alpha: 0.9)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: subtitle == null ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: fg.withValues(alpha: 0.85),
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
    return Material(
      color: backgroundColor,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              child: content,
            ),
    );
  }

  Future<void> _deleteMessage(ChatMessage msg, {String scope = 'all'}) async {
    if (msg.id <= 0) {
      _discardFailedText(msg.id);
      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        _failedReadySends.remove(msg.id);
        _readyOutboundQueue.removeWhere((p) => p.tempId == msg.id);
      });
      unawaited(_persistReadySends());
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
      return;
    }
    final index = _messages.indexWhere((m) => m.id == msg.id);
    final wasPinned = _isMessagePinned(msg.id);
    setState(() {
      _messages.removeWhere((m) => m.id == msg.id);
      _removePinnedMessageId(msg.id);
    });
    unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    try {
      await ChatService.deleteMessage(
        conversationId: widget.conversationId,
        messageId: msg.id,
        scope: scope,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          final at = index < 0 ? _messages.length : index.clamp(0, _messages.length);
          _messages.insert(at, msg);
        }
        if (wasPinned) _upsertPinnedMessage(msg);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _loadMyBots() async {
    try {
      final bots = await ApiService.getMyBots();
      if (mounted) {
        setState(() => _myBots = bots);
      }
    } catch (_) {
      // Игнорируем ошибку — автодополнение просто не появится
    }
  }

  Future<void> _load({required bool refresh}) async {
    if (widget.conversationId <= 0) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!refresh && (_loading || _loadingMore || !_hasMore)) return;
    final seq = ++_messageLoadSeq;
    if (refresh) {
      setState(() {
        // Keep cached/optimistic bubbles on screen — don't flash a spinner.
        if (_messages.isEmpty) {
          _loading = true;
        }
        _loadError = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      late final ({
        List<ChatMessage> items,
        bool hasMore,
        int? nextCursor,
        ChatMessage? pinnedMessage,
        List<ChatMessage> pinnedMessages,
      }) result;
      final reusePrefetch = refresh &&
          _activeTopicIdForSend == null &&
          _activeSavedTagId == null &&
          !_consumedPrefetchPage;
      if (reusePrefetch) {
        final page = await ChatThreadPrefetch.page(widget.conversationId);
        if (page != null) {
          result = (
            items: page.items,
            hasMore: page.hasMore,
            nextCursor: page.nextCursor,
            pinnedMessage: page.pinnedMessage,
            pinnedMessages: page.pinnedMessages,
          );
        } else {
          result = await ChatService.listMessages(
            conversationId: widget.conversationId,
            topicId: _activeTopicIdForSend,
            tagId: _activeSavedTagId,
          );
        }
        _consumedPrefetchPage = true;
      } else {
        result = await ChatService.listMessages(
          conversationId: widget.conversationId,
          cursor: refresh ? null : _nextCursor,
          topicId: _activeTopicIdForSend,
          tagId: _activeSavedTagId,
        );
      }
      if (!mounted || seq != _messageLoadSeq) return;
      setState(() {
        if (refresh) {
          final closedPolls = <int, ChatMessage>{
            for (final m in _messages)
              if (m.type == 'poll' && (m.poll?.isClosed ?? false)) m.id: m,
          };
          final previous = List<ChatMessage>.from(_messages);
          final keepTempIds = <int>{
            ..._failedTextSends.keys,
            ..._failedReadySends.keys,
            ..._pendingMediaByTempId.keys,
            ..._textOutboundQueue.map((p) => p.tempId),
            ..._readyOutboundQueue.map((p) => p.tempId),
            for (final local in previous)
              if (local.id < 0) local.id,
          };
          final merged = result.items.map((incoming) {
            final local = closedPolls[incoming.id];
            if (local == null) return incoming;
            return applyIncomingChatMessagePreservingLocalPoll(
              local,
              incoming,
            );
          }).toList();
          _messages
            ..clear()
            ..addAll(
              preserveOptimisticOutgoing(
                previous: previous,
                serverItems: merged,
                keepTempIds: keepTempIds,
                isDuplicate: _isDuplicateMessage,
              ),
            );
          _setPinnedMessages(
            result.pinnedMessages.isNotEmpty
                ? result.pinnedMessages
                : (result.pinnedMessage != null ? [result.pinnedMessage!] : const []),
          );
        } else {
          _messages.insertAll(0, result.items);
        }
        _hasMore = result.hasMore;
        _nextCursor = result.nextCursor;
        _loading = false;
        _loadingMore = false;
        _loadError = null;
      });
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
      _prefetchCustomEmojis();
      unawaited(_runAutoTranslate());
      _tryRestorePendingDraftReply();
      if (refresh) {
        unawaited(_refreshScheduledPendingCount());
      }
      // Acknowledge receipt even if the user is still above unread.
      _scheduleMarkDelivered();
      if (refresh) {
        _scrollAfterInitialLoad();
      } else if (_isNearBottom()) {
        // Pagination/background reload should not wipe unread while scrolled up.
        _scheduleMarkRead();
      }
    } catch (e) {
      if (!mounted || seq != _messageLoadSeq) return;
      if (FeedLoadHelper.isSessionError(e)) {
        unawaited(FeedLoadHelper.clearSessionIfExpired(e));
        return;
      }
      final message =
          userVisibleError(e, fallback: 'Не удалось загрузить сообщения');
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (refresh && _messages.isEmpty) {
          _loadError = message;
        }
      });
      if (!refresh || _messages.isNotEmpty) {
        showErrorSnackBar(context, e, fallback: message);
      }
    }
  }

  Future<void> _pollNew() async {
    if (widget.conversationId <= 0) return;
    if (_appPaused || _pollInFlight) return;
    final lastId = _lastServerMessageId();
    if (lastId == null) return;
    _pollInFlight = true;
    try {
      final fresh = await ChatService.listMessagesAfter(
        conversationId: widget.conversationId,
        afterId: lastId,
        topicId: _activeTopicIdForSend,
        tagId: _activeSavedTagId,
      );
      _pollFailureCount = 0;
      if (!mounted || fresh.isEmpty) return;
      var added = 0;
      setState(() {
        for (final msg in fresh) {
          if (_integrateMessage(msg)) added++;
        }
      });
      if (added == 0) return;
      final hasIncoming = fresh.any((m) => !m.isMine);
      if (hasIncoming && _peerTyping) {
        setState(_clearTypingState);
      }
      if (hasIncoming) {
        _scheduleMarkDelivered();
      }
      if (_isNearBottom()) {
        _scrollToBottom();
        _scheduleMarkRead();
      } else {
        setState(() {
          _newMessagesBelow += added;
          _showJumpToBottom = true;
        });
      }
    } catch (e) {
      _pollFailureCount++;
      if (kDebugMode) debugPrint('chat pollNew failed: $e');
      if (mounted && _pollFailureCount == 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Соединение нестабильно, догоняем сообщения…'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      _pollInFlight = false;
    }
  }

  void _scheduleMarkDelivered() {
    _markDeliveredDebounce?.cancel();
    _markDeliveredDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_markLatestDelivered());
    });
  }

  Future<void> _markLatestDelivered() async {
    if (_messages.isEmpty) return;
    ChatMessage? last;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].id > 0) {
        last = _messages[i];
        break;
      }
    }
    if (last == null) return;
    await ChatService.markDelivered(
      conversationId: widget.conversationId,
      messageId: last.id,
    );
  }

  void _scheduleMarkRead() {
    if (_suppressMarkRead) return;
    if (!_isNearBottom()) return;
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_markLatestRead());
    });
  }

  Future<void> _markLatestRead() async {
    if (_messages.isEmpty || _suppressMarkRead) return;
    if (!_isNearBottom()) return;
    ChatMessage? last;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].id > 0) {
        last = _messages[i];
        break;
      }
    }
    if (last == null) return;
    await ChatService.markRead(
      conversationId: widget.conversationId,
      messageId: last.id,
    );
    if (!mounted) return;
    // Keep the unread divider for this open session (Telegram-like);
    // only clear the badge/count once we've marked read on the server.
    if (_conversation.unreadCount > 0 ||
        _conversation.unreadMentionsCount > 0 ||
        _conversation.unreadReactionsCount > 0) {
      setState(() {
        _conversation = _conversation.copyWith(
          unreadCount: 0,
          unreadMentionsCount: 0,
          unreadReactionsCount: 0,
        );
      });
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (animated) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
    if (_suppressMarkRead) {
      setState(() => _suppressMarkRead = false);
    }
    _scheduleMarkRead();
  }

  void _scrollToBottomAfterKeyboard() {
    _scrollToBottom(animated: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom(animated: false);
    });
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _scrollToBottom(animated: false);
    });
  }

  bool get _serializeTextSends =>
      _conversation.isGroup &&
      (_slowModeEnabledForCurrentUser || _isAnyCooldownActive);

  void _kickTextOutbound() {
    if (widget.conversationId <= 0) return;
    if (_serializeTextSends) {
      unawaited(_drainTextOutboundQueue());
      return;
    }
    for (final pending in List<_PendingTextSend>.from(_textOutboundQueue)) {
      if (_inFlightTextClientIds.contains(pending.clientMessageId)) continue;
      unawaited(_flushOneTextSend(pending));
    }
  }

  Future<void> _flushOneTextSend(_PendingTextSend pending) async {
    if (_inFlightTextClientIds.contains(pending.clientMessageId)) return;
    _inFlightTextClientIds.add(pending.clientMessageId);
    try {
      while (mounted) {
        try {
          final msg = await ChatService.sendText(
            conversationId: widget.conversationId,
            content: pending.text,
            replyToMessageId: pending.replyToMessageId,
            clientMessageId: pending.clientMessageId,
            silent: pending.silent,
            disableWebpagePreview: pending.disableWebpagePreview,
            effectId: pending.effectId,
            topicId: pending.topicId,
            anonymous: pending.anonymous,
          );
          _textOutboundQueue.removeWhere(
            (p) => p.clientMessageId == pending.clientMessageId,
          );
          _failedTextSends.remove(pending.tempId);
          unawaited(_persistFailedTextSends());
          _rememberOutgoingForHub(msg, refreshHub: true);
          if (!mounted) return;
          setState(() {
            _clearFailedTextAutoRetry(pending.tempId);
            _integrateMessage(msg, removeTempId: pending.tempId);
            _activateSlowModeCooldownFromNow();
          });
          if ((msg.effectId ?? pending.effectId ?? '').isNotEmpty) {
            _playMessageEffect(
              msg.effectId ?? pending.effectId,
              messageId: msg.id,
            );
          }
          _scrollToBottom();
          unawaited(
            ChatCacheService.saveThread(widget.conversationId, _messages),
          );
          unawaited(ChatCacheService.clearDraft(widget.conversationId));
          unawaited(
            ChatService.deleteCloudDraft(
              conversationId: widget.conversationId,
            ),
          );
          return;
        } catch (e) {
          final err = e.toString().toLowerCase();
          if (err.contains('group_slow_mode')) {
            _textOutboundQueue.removeWhere(
              (p) => p.clientMessageId == pending.clientMessageId,
            );
            final retryAfter =
                e is ApiClientException ? e.retryAfterSeconds : null;
            pending.lastRetryAfterSeconds =
                (retryAfter ?? _conversation.slowModeSeconds).clamp(1, 3600);
            pending.lastLimitedAt = DateTime.now().toUtc();
            _failedTextSends[pending.tempId] = pending;
            unawaited(_persistFailedTextSends());
            if (!mounted) return;
            setState(() {
              _activateSlowModeCooldownForSeconds(retryAfter ?? 0);
            });
            _scheduleFailedTextAutoRetry(
              pending,
              retryAfterSeconds: retryAfter ?? _conversation.slowModeSeconds,
              reason: 'slow',
            );
            if (!_autoRetryOnLimitsEnabled && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Автоповтор отключен — нажмите «Повторить» вручную',
                  ),
                ),
              );
            }
            showErrorSnackBar(context, e);
            return;
          }
          if (err.contains('group_flood_limited')) {
            _textOutboundQueue.removeWhere(
              (p) => p.clientMessageId == pending.clientMessageId,
            );
            final retryAfter =
                e is ApiClientException ? e.retryAfterSeconds : null;
            pending.lastRetryAfterSeconds = (retryAfter ?? 60).clamp(1, 3600);
            pending.lastLimitedAt = DateTime.now().toUtc();
            final wait = (retryAfter != null && retryAfter > 0)
                ? ' Подождите ${_formatSlowModeCountdown(retryAfter)}.'
                : '';
            _failedTextSends[pending.tempId] = pending;
            unawaited(_persistFailedTextSends());
            if (!mounted) return;
            setState(() {
              _activateFloodCooldownForSeconds(retryAfter ?? 0);
            });
            _scheduleFailedTextAutoRetry(
              pending,
              retryAfterSeconds: retryAfter ?? 60,
              reason: 'flood',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Лимит сообщений в минуту достигнут.$wait'),
              ),
            );
            if (!_autoRetryOnLimitsEnabled && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Автоповтор отключен — нажмите «Повторить» вручную',
                  ),
                ),
              );
            }
            return;
          }
          pending.attempts++;
          if (_isRetryableSendError(e) && pending.attempts < 3) {
            final waitMs = pending.attempts == 1 ? 200 : 500;
            await Future<void>.delayed(Duration(milliseconds: waitMs));
            continue;
          }
          _textOutboundQueue.removeWhere(
            (p) => p.clientMessageId == pending.clientMessageId,
          );
          pending.lastRetryAfterSeconds = null;
          pending.lastLimitedAt = null;
          _failedTextSends[pending.tempId] = pending;
          unawaited(_persistFailedTextSends());
          if (!mounted) return;
          setState(() {});
          if (offerFlexIfRequired(context, e)) return;
          if (offerPackStoreIfRequired(context, e)) return;
          if (isStarsRequiredError(e)) {
            await showStarsRequiredSnack(context, e);
          } else {
            showErrorSnackBar(context, e);
          }
          return;
        }
      }
    } finally {
      _inFlightTextClientIds.remove(pending.clientMessageId);
    }
  }

  Future<void> _drainTextOutboundQueue() async {
    if (_textDrainActive) return;
    _textDrainActive = true;
    try {
      while (_textOutboundQueue.isNotEmpty && mounted) {
        // Group slow-mode / flood only — never stall DMs on leftover timers.
        if (_conversation.isGroup && _isAnyCooldownActive) {
          final wait = _activeCooldownRemainingSeconds.clamp(1, 120);
          await Future<void>.delayed(Duration(seconds: wait));
          if (!mounted) return;
          continue;
        }
        final pending = _textOutboundQueue.first;
        await _flushOneTextSend(pending);
      }
    } finally {
      _textDrainActive = false;
      if (mounted && _textOutboundQueue.isNotEmpty) {
        unawaited(_drainTextOutboundQueue());
      }
    }
  }

  Future<bool> _ensurePaidDmFeeConfirmed() async {
    final fee = _conversation.peer?.paidMessageStars ?? 0;
    if (fee <= 0 || _conversation.isGroup || _conversation.isSaved) {
      return true;
    }
    if (_paidDmFeeConfirmed) return true;
    final ok = await confirmStarsSpend(
      context,
      title: 'Платные сообщения',
      body:
          'Собеседник берёт $fee ★ за каждое сообщение. Звёзды спишутся при отправке.',
      amountStars: fee,
      confirmLabel: 'Понятно',
    );
    if (ok) _paidDmFeeConfirmed = true;
    return ok;
  }

  Future<bool> _allowSilent(bool silent) async {
    if (!silent) return true;
    if (_hasFlexFeature('silent_send')) return true;
    await showCreatorUpsell(context);
    return false;
  }

  Future<void> _sendText({bool silent = false, String? effectId}) async {
    if (!await _allowSilent(silent)) return;
    final text = _controller.text.trim();
    final editingMedia = _editingMessage != null &&
        (_editingMessage!.type == 'image' ||
            _editingMessage!.type == 'video' ||
            _editingMessage!.type == 'file');
    if ((!editingMedia && text.isEmpty) || _recording) return;
    // One-time ReplyKeyboard hides after any user reply (Telegram).
    if (_editingMessage == null &&
        _replyKeyboard != null &&
        _replyKeyboard!.oneTime) {
      setState(() => _replyKeyboard = null);
    }
    if (_editingMessage == null) {
      final feeOk = await _ensurePaidDmFeeConfirmed();
      if (!feeOk || !mounted) return;
    }
    if (_conversation.isGroup &&
        _conversation.amISendRestricted &&
        !_conversation.amIGroupAdmin) {
      final until = _conversation.amISendRestrictedUntil;
      final reason = (_conversation.amISendRestrictionReason ?? '').trim();
      final untilText = until == null
          ? 'без срока'
          : DateFormat('dd.MM.yyyy HH:mm').format(until.toLocal());
      final details = reason.isEmpty
          ? untilText
          : '$untilText • ${previewTextWithCustomEmoji(reason)}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Вам ограничили отправку сообщений ($details)')),
        );
      }
      return;
    }
    if (_conversation.isGroup &&
        _conversation.onlyAdminsCanPost &&
        !_conversation.amIGroupAdmin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Писать в этой группе могут только админы')),
        );
      }
      return;
    }

    _hideBotAutocompleteOverlay();

    // === Inline Mode: @bot query ===
    if (text.startsWith('@')) {
      final match = RegExp(r'^@([a-zA-Z0-9_]+)\s*(.*)$').firstMatch(text);
      if (match != null) {
        final botUsername = match.group(1)!;
        final query = match.group(2) ?? '';
        _controller.clear();
        final results = await BotInlineService.getInlineResults(
          botUsername: botUsername,
          query: query,
        );
        if (!mounted) return;
        if (results.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Бот @$botUsername не найден или не имеет команд')),
          );
          return;
        }
        final selected = await showModalBottomSheet<InlineResult>(
          context: context,
          builder: (_) => InlineSuggestions(
            results: results,
            onSelect: (r) => Navigator.pop(context, r),
            botUsername: botUsername,
          ),
        );
        if (selected != null) {
          if (selected.type == 'miniapp') {
            await _openMiniAppFromInline(selected);
            return;
          }
          // Отправляем payload как обычное сообщение
          _controller.text = selected.payload;
          // Рекурсивно вызовем _sendText для отправки
          await _sendText();
        }
        return;
      }
    }
    // Client cooldown only for real group slow-mode / flood — not DMs.
    if (_editingMessage == null &&
        _conversation.isGroup &&
        _isAnyCooldownActive) {
      final remain = _formatSlowModeCountdown(_activeCooldownRemainingSeconds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Подождите $remain перед отправкой')),
        );
      }
      return;
    }
    final failedSame = _failedTextSends.values
        .where((p) => p.text == text)
        .toList(growable: false);
    if (failedSame.isNotEmpty) {
      _controller.clear();
      for (final pending in failedSame) {
        unawaited(_retryFailedText(pending.tempId));
      }
      return;
    }
    final editing = _editingMessage;
    if (editing != null) {
      final previous = editing;
      _controller.clear();
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == editing.id);
        if (idx >= 0) {
          _messages[idx] = editing.copyWith(
            content: text,
            editedAt: DateTime.now(),
          );
        }
        if (_isMessagePinned(editing.id)) {
          _replacePinnedMessage(
            editing.copyWith(content: text, editedAt: DateTime.now()),
          );
        }
        _editingMessage = null;
      });
      unawaited(() async {
        try {
          final msg = await ChatService.editMessage(
            conversationId: widget.conversationId,
            messageId: editing.id,
            content: text,
          );
          if (!mounted) return;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == msg.id);
            if (idx >= 0) _messages[idx] = msg;
            if (_isMessagePinned(msg.id)) _replacePinnedMessage(msg);
          });
          unawaited(
            ChatCacheService.saveThread(widget.conversationId, _messages),
          );
        } catch (e) {
          if (!mounted) return;
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == previous.id);
            if (idx >= 0) _messages[idx] = previous;
            if (_isMessagePinned(previous.id)) _replacePinnedMessage(previous);
            _editingMessage = previous;
          });
          _controller.text = text;
          if (offerFlexIfRequired(context, e)) return;
          if (offerPackStoreIfRequired(context, e)) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userVisibleError(e))),
          );
        }
      }());
      return;
    }
    final privateQuote = _privateReply;
    final sendText = privateQuote != null
        ? composeTextWithPrivateReply(text, privateQuote)
        : text;
    final replyId = privateQuote != null ? null : _replyTo?.id;
    final uid = AuthService.instance.currentUser?.id ?? 0;
    final clientMessageId = const Uuid().v4();
    final firstUrl = extractFirstHttpUrl(sendText);
    final disablePreview = firstUrl != null &&
        firstUrl == _composerLinkPreviewDismissedUrl;
    _controller.clear();
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final topicId = _activeTopicIdForSend;
    final sendAnon = _effectiveSendAnonymous;
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: widget.conversationId,
      senderId: uid,
      senderName: sendAnon
          ? resolveAnonymousSenderLabel(
              isAnonymous: true,
              groupTitle: _conversation.title,
              realSenderName: AuthService.instance.currentUser?.name,
              viewerIsSender: true,
              viewerIsAdmin: true,
            )
          : null,
      type: 'text',
      content: sendText,
      createdAt: DateTime.now(),
      isMine: true,
      replyToMessageId: replyId,
      disableWebpagePreview: disablePreview,
      topicId: topicId,
      isAnonymous: sendAnon,
      clientMessageId: clientMessageId,
    );
    final pending = _PendingTextSend(
      text: sendText,
      replyToMessageId: replyId,
      clientMessageId: clientMessageId,
      tempId: tempId,
      silent: silent,
      disableWebpagePreview: disablePreview,
      effectId: effectId,
      topicId: topicId,
      anonymous: sendAnon,
    );
    setState(() {
      _messages.add(optimistic);
      _replyTo = null;
      _privateReply = null;
      _composerLinkPreviewUrl = null;
      _composerLinkPreviewDismissedUrl = null;
      _textOutboundQueue.add(pending);
    });
    unawaited(_persistFailedTextSends());
    unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    _rememberOutgoingForHub(optimistic);
    _scrollToBottom();
    _kickTextOutbound();
  }

  Future<DateTime?> _pickScheduleDateTime({DateTime? initialDateTime}) async {
    final now = DateTime.now();
    final initial = initialDateTime != null && initialDateTime.isAfter(now)
        ? initialDateTime
        : now.add(const Duration(minutes: 10));
    DateTime atOrNextDay(int hour, int minute) {
      var dt = DateTime(now.year, now.month, now.day, hour, minute);
      if (!dt.isAfter(now.add(const Duration(seconds: 30)))) {
        dt = dt.add(const Duration(days: 1));
      }
      return dt;
    }

    final inOneHour = now.add(const Duration(hours: 1));
    final tonight = atOrNextDay(21, 0);
    final tomorrowMorning = DateTime(
      now.year,
      now.month,
      now.day + 1,
      9,
      0,
    );
    final presetFmt = DateFormat('dd.MM HH:mm');
    final preset = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Через 1 час'),
                subtitle: Text(presetFmt.format(inOneHour)),
                onTap: () => Navigator.pop(ctx, 'in_1h'),
              ),
              ListTile(
                leading: const Icon(Icons.nights_stay_outlined),
                title: const Text('Сегодня вечером'),
                subtitle: Text(presetFmt.format(tonight)),
                onTap: () => Navigator.pop(ctx, 'tonight'),
              ),
              ListTile(
                leading: const Icon(Icons.wb_sunny_outlined),
                title: const Text('Завтра утром'),
                subtitle: Text(presetFmt.format(tomorrowMorning)),
                onTap: () => Navigator.pop(ctx, 'tomorrow_morning'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text('Выбрать дату и время...'),
                onTap: () => Navigator.pop(ctx, 'custom'),
              ),
            ],
          ),
        );
      },
    );
    if (preset == null) return null;
    switch (preset) {
      case 'in_1h':
        return inOneHour;
      case 'tonight':
        return tonight;
      case 'tomorrow_morning':
        return tomorrowMorning;
      default:
        break;
    }

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Дата отправки',
    );
    if (pickedDate == null || !mounted) return null;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Время отправки',
    );
    if (pickedTime == null) return null;
    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<({DateTime sendAt, bool sendWhenOnline})?> _pickScheduleDelivery() async {
    if (!_hasFlexFeature('scheduled_messages')) {
      await showCreatorUpsell(context);
      return null;
    }
    var sendWhenOnline = false;
    DateTime? sendAt;
    final canUseWhenOnline =
        !_conversation.isGroup && _conversation.peer != null;
    if (canUseWhenOnline) {
      final mode = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.circle_outlined),
                title: const Text('Когда пользователь онлайн'),
                subtitle: const Text(
                    'Отправится, как только собеседник появится в сети'),
                onTap: () => Navigator.pop(ctx, 'online'),
              ),
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Отправить по времени'),
                onTap: () => Navigator.pop(ctx, 'time'),
              ),
            ],
          ),
        ),
      );
      if (mode == null || !mounted) return null;
      if (mode == 'online') {
        sendWhenOnline = true;
        sendAt = DateTime.now().add(const Duration(minutes: 1));
      }
    }
    if (!sendWhenOnline) {
      sendAt = await _pickScheduleDateTime();
      if (sendAt == null || !mounted) return null;
      if (!sendAt.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Выберите время минимум на 30 секунд позже'),
          ),
        );
        return null;
      }
    }
    return (sendAt: sendAt!, sendWhenOnline: sendWhenOnline);
  }

  void _showScheduledSnack(ScheduledChatMessage item) {
    final when = DateFormat('dd.MM HH:mm').format(item.sendAt);
    var base = item.sendWhenOnline
        ? 'Сообщение будет отправлено, когда собеседник онлайн'
        : 'Сообщение запланировано на $when';
    if (item.silent) base = '$base (без звука)';
    final effect = (item.effectId ?? '').trim();
    if (effect.isNotEmpty) base = '$base · эффект $effect';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(base)),
    );
  }

  Future<String?> _pickMessageEffect() async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Эффект сообщения'),
              subtitle: Text('Анимация при отправке и у получателя'),
            ),
            for (final effect in _availableMessageEffects)
              ListTile(
                leading: Icon(effect.$3),
                title: Text(effect.$2),
                onTap: () => Navigator.pop(ctx, effect.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Returns empty string for "no effect", null if cancelled.
  Future<String?> _pickOptionalMessageEffect() async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Эффект при отправке'),
              subtitle: Text('Можно отложить с анимацией'),
            ),
            ListTile(
              leading: const Icon(Icons.not_interested_outlined),
              title: const Text('Без эффекта'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final effect in _availableMessageEffects)
              ListTile(
                leading: Icon(effect.$3),
                title: Text(effect.$2),
                onTap: () => Navigator.pop(ctx, effect.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _scheduleCurrentTextMessage() async {
    if (_recording || _editingMessage != null) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final mode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _silentSendTile(
              sheetContext: ctx,
              mode: 'silent',
              title: 'Отправить без звука',
              subtitle: 'Без push-уведомления получателю',
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Эффект'),
              subtitle: const Text('Конфетти, сердца и другие анимации'),
              onTap: () => Navigator.pop(ctx, 'effect'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Отложить'),
              onTap: () => Navigator.pop(ctx, 'schedule'),
            ),
            _silentSendTile(
              sheetContext: ctx,
              mode: 'schedule_silent',
              title: 'Отложить без звука',
              icon: Icons.schedule_send_outlined,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (mode == null || !mounted) return;
    if (mode == 'silent') {
      await _sendText(silent: true);
      return;
    }
    if (mode == 'effect') {
      final effectId = await _pickMessageEffect();
      if (effectId == null || !mounted) return;
      final sendMode = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.send_rounded),
                title: const Text('Отправить сейчас'),
                onTap: () => Navigator.pop(ctx, 'now'),
              ),
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Отложить с эффектом'),
                onTap: () => Navigator.pop(ctx, 'schedule'),
              ),
              _silentSendTile(
                sheetContext: ctx,
                mode: 'schedule_silent',
                title: 'Отложить без звука',
                icon: Icons.schedule_send_outlined,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (sendMode == null || !mounted) return;
      if (sendMode == 'now') {
        await _sendText(effectId: effectId);
        return;
      }
      final delivery = await _pickScheduleDelivery();
      if (delivery == null || !mounted) return;
      await _scheduleTextPayload(
        text: text,
        delivery: delivery,
        silent: _scheduleSilent(sendMode),
        effectId: effectId,
      );
      return;
    }

    final delivery = await _pickScheduleDelivery();
    if (delivery == null || !mounted) return;
    final effectChoice = await _pickOptionalMessageEffect();
    if (effectChoice == null || !mounted) return;
    await _scheduleTextPayload(
      text: text,
      delivery: delivery,
      silent: _scheduleSilent(mode),
      effectId: effectChoice.isEmpty ? null : effectChoice,
    );
  }

  Future<void> _scheduleTextPayload({
    required String text,
    required ({DateTime sendAt, bool sendWhenOnline}) delivery,
    bool silent = false,
    String? effectId,
  }) async {
    final firstUrl = extractFirstHttpUrl(text);
    final disablePreview = firstUrl != null &&
        firstUrl == _composerLinkPreviewDismissedUrl;
    try {
      final item = await ChatService.scheduleText(
        conversationId: widget.conversationId,
        content: text,
        sendAt: delivery.sendAt,
        sendWhenOnline: delivery.sendWhenOnline,
        silent: silent,
        disableWebpagePreview: disablePreview,
        replyToMessageId: _replyTo?.id,
        clientMessageId: const Uuid().v4(),
        effectId: effectId,
        topicId: _activeTopicIdForSend,
      );
      if (!mounted) return;
      setState(() {
        _controller.clear();
        _replyTo = null;
      });
      _showScheduledSnack(item);
      unawaited(_refreshScheduledPendingCount());
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      if (offerPackStoreIfRequired(context, e)) return;
      showErrorSnackBar(context, e,
          fallback: 'Не удалось запланировать сообщение');
    }
  }

  Future<void> _restoreScheduledAfterFailedSend(
    ScheduledChatMessage item,
  ) async {
    try {
      final minAt = DateTime.now().add(const Duration(seconds: 35));
      final sendAt = item.sendWhenOnline
          ? minAt
          : (item.sendAt.isAfter(minAt) ? item.sendAt : minAt);
      final poll = item.type == 'poll'
          ? parseChatPollFromContent(item.content)
          : null;
      final checklist = item.type == 'checklist'
          ? ChatChecklist.tryParse(item.content)
          : null;
      await ChatService.scheduleMessage(
        conversationId: widget.conversationId,
        type: item.type,
        content: item.content,
        mediaUrl: item.mediaUrl,
        sendAt: sendAt,
        sendWhenOnline: item.sendWhenOnline,
        silent: item.silent,
        disableWebpagePreview: item.disableWebpagePreview,
        replyToMessageId: item.replyToMessageId,
        pollQuestion: poll?.question,
        pollDescription: poll?.description,
        pollOptions: poll?.options.map((o) => o.text).toList(),
        pollSettings: poll?.settings.toJson(),
        checklistTitle: checklist?.title,
        checklistItems: checklist?.items.map((e) => e.text).toList(),
        effectId: item.effectId,
        topicId: item.topicId ?? _activeTopicIdForSend,
      );
    } catch (_) {}
  }

  bool _canEditScheduledContent(ScheduledChatMessage item) {
    return item.type == 'text' ||
        item.type == 'image' ||
        item.type == 'video' ||
        item.type == 'video_note' ||
        item.type == 'file';
  }

  Widget? _scheduledLeading(ScheduledChatMessage item) {
    final url = item.mediaUrl?.trim();
    if (url != null &&
        url.isNotEmpty &&
        (item.type == 'image' ||
            item.type == 'sticker' ||
            item.type == 'video' ||
            item.type == 'video_note')) {
      final resolved = ServerConfig.resolveMediaUrl(url);
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 44,
          child: item.type == 'video' || item.type == 'video_note'
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.videocam_outlined, size: 22),
                    ),
                    const Align(
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ],
                )
              : CachedNetworkImage(
                  imageUrl: resolved,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: Icon(
                      item.type == 'sticker'
                          ? Icons.emoji_emotions_outlined
                          : Icons.photo_outlined,
                      size: 22,
                    ),
                  ),
                ),
        ),
      );
    }
    IconData icon;
    switch (item.type) {
      case 'voice':
        icon = Icons.mic_none_rounded;
        break;
      case 'file':
        icon = Icons.insert_drive_file_outlined;
        break;
      case 'poll':
        icon = Icons.poll_outlined;
        break;
      case 'location':
        icon = Icons.location_on_outlined;
        break;
      default:
        icon = Icons.schedule_outlined;
    }
    return CircleAvatar(
      radius: 22,
      child: Icon(icon, size: 20),
    );
  }

  Future<String?> _editScheduledText(ScheduledChatMessage item) async {
    final isCaption = item.type != 'text';
    final controller = TextEditingController(text: item.content);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCaption ? 'Подпись' : 'Изменить отложенное'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          maxLength: 4000,
          decoration: InputDecoration(
            hintText: isCaption ? 'Подпись к медиа' : 'Текст сообщения',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null) return null;
    final trimmed = next.trim();
    if (trimmed == item.content.trim()) return null;
    if (!isCaption && trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> _sendScheduledMessageNow(ScheduledChatMessage item) async {
    var canceled = false;
    try {
      await ChatService.cancelScheduledMessage(
        conversationId: widget.conversationId,
        scheduledMessageId: item.id,
      );
      canceled = true;
      await _enqueueScheduledMessageNow(item);
    } catch (e) {
      if (canceled) {
        await _restoreScheduledAfterFailedSend(item);
      }
      rethrow;
    }
  }

  Future<void> _enqueueScheduledMessageNow(ScheduledChatMessage item) async {
    final replyId = item.replyToMessageId;
    final media = item.mediaUrl?.trim();
    final topicId = item.topicId ?? _activeTopicIdForSend;
    final needsMedia = item.type == 'image' ||
        item.type == 'video' ||
        item.type == 'video_note' ||
        item.type == 'voice' ||
        item.type == 'file' ||
        item.type == 'sticker';
    if (needsMedia && (media == null || media.isEmpty)) {
      throw Exception('Нет медиа для отправки');
    }
    if (item.type == 'poll') {
      final poll = parseChatPollFromContent(item.content);
      if (poll == null || poll.options.length < 2) {
        throw Exception('Не удалось восстановить опрос');
      }
      _enqueueReadyOutgoing(
        ChatReadyOutgoing(
          tempId: _newLocalTempId(),
          clientMessageId: const Uuid().v4(),
          type: 'poll',
          content: item.content,
          replyToMessageId: replyId,
          topicId: topicId,
          pollQuestion: poll.question,
          pollDescription: poll.description,
          pollOptions: poll.options.map((o) => o.text).toList(),
          pollSettings: poll.settings.toJson(),
        ),
      );
      return;
    }
    if (item.type == 'checklist') {
      final list = ChatChecklist.tryParse(item.content);
      if (list == null || list.items.isEmpty) {
        throw Exception('Не удалось восстановить чеклист');
      }
      _enqueueReadyOutgoing(
        ChatReadyOutgoing(
          tempId: _newLocalTempId(),
          clientMessageId: const Uuid().v4(),
          type: 'checklist',
          content: item.content,
          replyToMessageId: replyId,
          topicId: topicId,
          checklistTitle: list.title,
          checklistItems: list.items.map((e) => e.text).toList(),
        ),
      );
      return;
    }
    _enqueueReadyOutgoing(
      ChatReadyOutgoing(
        tempId: _newLocalTempId(),
        clientMessageId: const Uuid().v4(),
        type: item.type,
        content: item.content,
        mediaUrl: media,
        fileName: item.type == 'file'
            ? (item.content.trim().isEmpty ? 'file' : item.content.trim())
            : null,
        durationSec: (item.type == 'voice' || item.type == 'video_note')
            ? (int.tryParse(item.content.trim()) ?? 1)
            : null,
        replyToMessageId: replyId,
        topicId: topicId,
      ),
    );
  }

  String _scheduledPreview(ScheduledChatMessage item) {
    if (item.type == 'poll') {
      final poll = parseChatPollFromContent(item.content);
      if (poll != null) return chatPollPreviewText(poll);
      return '📊 Опрос';
    }
    if (item.type == 'checklist') {
      return ChatChecklist.tryParse(item.content)?.preview ?? '☑ Чеклист';
    }
    if (item.type == 'voice') return '🎤 Голосовое';
    if (item.type == 'image') return '📷 Фото';
    if (item.type == 'video') return '🎬 Видео';
    if (item.type == 'video_note') return '⭕ Видеосообщение';
    if (item.type == 'sticker') return '🧩 Стикер';
    if (item.type == 'file') {
      final name = item.content.trim();
      return name.isEmpty
          ? '📎 Файл'
          : '📎 ${previewTextWithCustomEmoji(name)}';
    }
    if (item.type == 'location') {
      final loc = ChatLocationPayload.tryParse(item.content);
      return loc?.previewText ?? '📍 Геопозиция';
    }
    final text = item.content.trim();
    return text.isEmpty
        ? item.type.toUpperCase()
        : previewTextWithCustomEmoji(text);
  }

  Future<void> _openScheduledMessagesManager() async {
    try {
      final initialItems = await ChatService.listScheduledMessages(
        conversationId: widget.conversationId,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          final items = List<ScheduledChatMessage>.from(initialItems);
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              final pending = items
                  .where((e) => e.status == 'pending' || e.status == 'failed')
                  .toList()
                ..sort((a, b) {
                  if (a.status != b.status) {
                    return a.status == 'failed' ? -1 : 1;
                  }
                  return a.sendAt.compareTo(b.sendAt);
                });
              if (pending.isEmpty) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.schedule_outlined, size: 30),
                        SizedBox(height: 12),
                        Text('Нет отложенных сообщений'),
                      ],
                    ),
                  ),
                );
              }
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Отложенные сообщения',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: math.min(
                          MediaQuery.sizeOf(context).height * 0.55,
                          360,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: pending.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final item = pending[index];
                            final preview = _scheduledPreview(item);
                            final rawCaption = item.type != 'text'
                                ? item.content.trim()
                                : '';
                            final caption = rawCaption.isEmpty
                                ? ''
                                : previewTextWithCustomEmoji(rawCaption);
                            return ListTile(
                              leading: _scheduledLeading(item),
                              title: Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if (caption.isNotEmpty) caption,
                                  if (item.status == 'failed')
                                    item.errorText?.trim().isNotEmpty == true
                                        ? 'Не отправлено: ${item.errorText}'
                                        : 'Не отправлено',
                                  if (item.status != 'failed')
                                    item.sendWhenOnline
                                        ? 'Отправка: когда пользователь онлайн'
                                        : 'Отправка: ${DateFormat('dd.MM.yyyy HH:mm').format(item.sendAt)}',
                                  if (item.silent) 'Без звука',
                                ].join('\n'),
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: caption.isNotEmpty,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.send_rounded),
                                    tooltip: 'Отправить сейчас',
                                    onPressed: () async {
                                      setModalState(
                                        () => items.removeWhere(
                                          (e) => e.id == item.id,
                                        ),
                                      );
                                      try {
                                        await _sendScheduledMessageNow(item);
                                        if (!mounted) return;
                                        unawaited(_load(refresh: true));
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('Отправлено'),
                                          ),
                                        );
                                      } catch (e) {
                                        try {
                                          final refreshed =
                                              await ChatService
                                                  .listScheduledMessages(
                                            conversationId:
                                                widget.conversationId,
                                          );
                                          setModalState(() {
                                            items
                                              ..clear()
                                              ..addAll(refreshed);
                                          });
                                        } catch (_) {
                                          setModalState(
                                            () => items.removeWhere(
                                              (e) => e.id == item.id,
                                            ),
                                          );
                                        }
                                        if (!mounted) return;
                                        if (offerFlexIfRequired(context, e)) {
                                          return;
                                        }
                                        if (offerPackStoreIfRequired(
                                            context, e)) {
                                          return;
                                        }
                                        if (isStarsRequiredError(e)) {
                                          await showStarsRequiredSnack(
                                            context,
                                            e,
                                          );
                                          return;
                                        }
                                        showErrorSnackBar(
                                          context,
                                          e,
                                          fallback:
                                              'Не удалось отправить сейчас',
                                        );
                                      }
                                    },
                                  ),
                                  if (_canEditScheduledContent(item))
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: item.type == 'text'
                                          ? 'Изменить текст'
                                          : 'Изменить подпись',
                                      onPressed: () async {
                                        final next =
                                            await _editScheduledText(item);
                                        if (next == null) return;
                                        setModalState(() {
                                          final idx = items.indexWhere(
                                            (e) => e.id == item.id,
                                          );
                                          if (idx >= 0) {
                                            items[idx] =
                                                items[idx].copyWith(content: next);
                                          }
                                        });
                                        try {
                                          final updated = await ChatService
                                              .rescheduleMessage(
                                            conversationId:
                                                widget.conversationId,
                                            scheduledMessageId: item.id,
                                            content: next,
                                          );
                                          setModalState(() {
                                            final idx = items.indexWhere(
                                              (e) => e.id == item.id,
                                            );
                                            if (idx >= 0) items[idx] = updated;
                                          });
                                        } catch (e) {
                                          setModalState(() {
                                            final idx = items.indexWhere(
                                              (e) => e.id == item.id,
                                            );
                                            if (idx >= 0) items[idx] = item;
                                          });
                                          if (!mounted) return;
                                          if (offerFlexIfRequired(context, e)) {
                                            return;
                                          }
                                          if (offerPackStoreIfRequired(
                                              context, e)) {
                                            return;
                                          }
                                          if (isStarsRequiredError(e)) {
                                            await showStarsRequiredSnack(
                                              context,
                                              e,
                                            );
                                            return;
                                          }
                                          showErrorSnackBar(
                                            context,
                                            e,
                                            fallback:
                                                'Не удалось изменить сообщение',
                                          );
                                        }
                                      },
                                    ),
                                  if (!item.sendWhenOnline)
                                    IconButton(
                                      icon: const Icon(
                                          Icons.edit_calendar_outlined),
                                      tooltip: 'Перенести',
                                      onPressed: () async {
                                        final nextSendAt =
                                            await _pickScheduleDateTime(
                                          initialDateTime: item.sendAt,
                                        );
                                        if (nextSendAt == null) return;
                                        if (!nextSendAt.isAfter(
                                          DateTime.now()
                                              .add(const Duration(seconds: 30)),
                                        )) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Выберите время минимум на 30 секунд позже',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        setModalState(() {
                                          final idx = items.indexWhere(
                                            (e) => e.id == item.id,
                                          );
                                          if (idx >= 0) {
                                            items[idx] = items[idx]
                                                .copyWith(sendAt: nextSendAt);
                                          }
                                        });
                                        try {
                                          final updated = await ChatService
                                              .rescheduleMessage(
                                            conversationId:
                                                widget.conversationId,
                                            scheduledMessageId: item.id,
                                            sendAt: nextSendAt,
                                          );
                                          setModalState(() {
                                            final idx = items.indexWhere(
                                              (e) => e.id == item.id,
                                            );
                                            if (idx >= 0) items[idx] = updated;
                                          });
                                        } catch (e) {
                                          setModalState(() {
                                            final idx = items.indexWhere(
                                              (e) => e.id == item.id,
                                            );
                                            if (idx >= 0) items[idx] = item;
                                          });
                                          if (!mounted) return;
                                          showErrorSnackBar(
                                            context,
                                            e,
                                            fallback:
                                                'Не удалось перенести сообщение',
                                          );
                                        }
                                      },
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: item.status == 'failed'
                                        ? 'Удалить'
                                        : 'Отменить',
                                    onPressed: () async {
                                      setModalState(
                                        () => items.removeWhere(
                                            (e) => e.id == item.id),
                                      );
                                      try {
                                        await ChatService
                                            .cancelScheduledMessage(
                                          conversationId: widget.conversationId,
                                          scheduledMessageId: item.id,
                                        );
                                      } catch (e) {
                                        setModalState(() => items.add(item));
                                        if (!mounted) return;
                                        showErrorSnackBar(
                                          context,
                                          e,
                                          fallback:
                                              'Не удалось отменить сообщение',
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      unawaited(_refreshScheduledPendingCount());
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallback: 'Не удалось загрузить отложенные сообщения',
      );
    }
  }

  Future<void> _refreshScheduledPendingCount() async {
    try {
      final items = await ChatService.listScheduledMessages(
        conversationId: widget.conversationId,
        limit: 200,
      );
      if (!mounted) return;
      setState(
        () => _scheduledPendingCount =
            items.where((e) => e.status == 'pending').length,
      );
    } catch (_) {
      // Silent: this is a decorative badge.
    }
  }

  void _openImage(String url) {
    final imageMsgs = _messages
        .where(
          (m) =>
              (m.type == 'image' || _canOpenStickerInImageViewer(m)) &&
              (m.mediaUrl?.isNotEmpty ?? false),
        )
        .toList(growable: false);
    final urls = imageMsgs.map((m) => m.mediaUrl!).toList(growable: false);
    final captions = imageMsgs.map((m) => m.content).toList(growable: false);
    final index = urls.indexOf(url);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FullscreenImageViewer(
          imageUrls: urls.isEmpty ? [url] : urls,
          captions: urls.isEmpty ? null : captions,
          initialIndex: index >= 0 ? index : 0,
          allowSaveShare: !_conversation.protectContent,
        ),
      ),
    );
  }

  bool _canOpenStickerInImageViewer(ChatMessage msg) {
    if (msg.type != 'sticker') return false;
    final media = msg.mediaUrl?.trim();
    if (media == null || media.isEmpty) return false;
    final lower = media.toLowerCase();
    if (lower.endsWith('.webm') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.json') ||
        lower.endsWith('.lottie') ||
        lower.endsWith('.tgs')) {
      return false;
    }
    return true;
  }

  Future<void> _openVideo(String url) async {
    String? caption;
    for (final m in _messages) {
      if ((m.type == 'video' || m.type == 'video_note') &&
          m.mediaUrl == url) {
        caption = m.content;
        break;
      }
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ChatVideoPlayerPage(
          videoUrl: url,
          caption: caption,
          allowSaveShare: !_conversation.protectContent,
        ),
      ),
    );
  }

  Future<void> _showStickerPicker() async {
    if (_recording) return;
    // Toggle compact panel above composer (Telegram). Full sheet via "Все".
    setState(() {
      _stickerPanelOpen = !_stickerPanelOpen;
      if (_stickerPanelOpen) _inputFocusNode.unfocus();
    });
  }

  Future<void> _showFullStickerSheet() async {
    if (_recording) return;
    setState(() => _stickerPanelOpen = false);
    final selection = await showChatAttachSheet(
      context,
      initialTab: ChatAttachTab.sticker,
      conversationId: widget.conversationId,
    );
    if (!mounted || selection == null) return;
    if (selection.kind == ChatAttachResult.sticker) {
      final stickerUrl = selection.stickerMediaUrl;
      if (stickerUrl != null && stickerUrl.trim().isNotEmpty) {
        await _sendStickerByUrl(stickerUrl, emoji: selection.stickerEmoji);
      }
    }
  }

  Future<void> _showAttachMenu() async {
    if (_recording) return;
    setState(() => _stickerPanelOpen = false);
    final selection = await showChatAttachSheet(
      context,
      conversationId: widget.conversationId,
    );
    if (!mounted || selection == null) return;
    switch (selection.kind) {
      case ChatAttachResult.galleryFiles:
        await _composeAndSendGallery(selection.galleryFiles);
      case ChatAttachResult.file:
        await _pickFile();
      case ChatAttachResult.pickedFile:
        final picked = selection.pickedFile;
        final pickedName = selection.pickedFileName;
        if (picked != null && pickedName != null) {
          await _sendPickedFile(picked, fileName: pickedName);
        }
      case ChatAttachResult.poll:
        final draft = selection.pollDraft;
        if (draft != null) {
          await _sendPollDraft(draft);
        } else {
          await _createAndSendPoll();
        }
      case ChatAttachResult.checklist:
        final draft = selection.checklistDraft;
        if (draft != null) {
          await _sendChecklistDraft(draft);
        } else {
          await _createAndSendChecklist();
        }
      case ChatAttachResult.contact:
        final contact = selection.contact;
        final phoneName = selection.contactPhoneName;
        final phoneE164 = selection.contactPhoneE164;
        if (contact != null) {
          await _sendContact(contact);
        } else if (phoneName != null && phoneE164 != null) {
          await _sendPhoneContact(
            displayName: phoneName,
            phoneE164: phoneE164,
          );
        }
      case ChatAttachResult.location:
        await _sendCurrentLocation(
          latitude: selection.latitude,
          longitude: selection.longitude,
          livePeriodSeconds: selection.livePeriodSeconds,
        );
      case ChatAttachResult.videoNote:
        await _recordAndSendVideoNote();
      case ChatAttachResult.resendFile:
        final url = selection.resendFileUrl;
        final name = selection.resendFileName;
        if (url != null && name != null) {
          await _resendStoredFile(name: name, mediaUrl: url);
        }
      case ChatAttachResult.sticker:
        final stickerUrl = selection.stickerMediaUrl;
        if (stickerUrl != null && stickerUrl.trim().isNotEmpty) {
          await _sendStickerByUrl(stickerUrl, emoji: selection.stickerEmoji);
        }
      case ChatAttachResult.gifResend:
        final gifUrl = selection.resendFileUrl?.trim();
        if (gifUrl != null && gifUrl.isNotEmpty) {
          await _sendGifByUrl(gifUrl);
        }
    }
  }

  Future<void> _sendGifByUrl(String mediaUrl) async {
    final resolved = ServerConfig.resolveMediaUrl(mediaUrl);
    unawaited(ChatRecentGifsStore.remember(resolved));
    _enqueueReadyOutgoing(
      ChatReadyOutgoing(
        tempId: _newLocalTempId(),
        clientMessageId: const Uuid().v4(),
        type: 'image',
        content: '',
        mediaUrl: resolved,
        replyToMessageId: _replyTo?.id,
        topicId: _activeTopicIdForSend,
        anonymous: _effectiveSendAnonymous,
      ),
    );
  }

  Future<void> _sendStickerByUrl(String mediaUrl, {String? emoji}) async {
    _controller.clear();
    _enqueueReadyOutgoing(
      ChatReadyOutgoing(
        tempId: _newLocalTempId(),
        clientMessageId: const Uuid().v4(),
        type: 'sticker',
        content: (emoji ?? '').trim(),
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        replyToMessageId: _replyTo?.id,
        topicId: _activeTopicIdForSend,
        anonymous: _effectiveSendAnonymous,
      ),
    );
  }

  Future<void> _composeAndSendGallery(List<XFile> files) async {
    if (files.isEmpty) return;
    final composed = await showChatMediaCompose(context, files: files);
    if (!mounted || composed == null || composed.files.isEmpty) return;
    if (composed.schedule) {
      await _scheduleGallerySelection(
        composed.files,
        caption: composed.caption,
        hasSpoiler: composed.hasSpoiler,
        silent: composed.silent,
      );
      return;
    }
    await _sendGallerySelection(
      composed.files,
      caption: composed.caption,
      hasSpoiler: composed.hasSpoiler,
      silent: composed.silent,
      isPaid: composed.isPaid,
      priceStars: composed.priceStars,
    );
  }

  Future<void> _scheduleGallerySelection(
    List<XFile> files, {
    String caption = '',
    bool hasSpoiler = false,
    bool silent = false,
  }) async {
    if (files.isEmpty) return;
    final delivery = await _pickScheduleDelivery();
    if (delivery == null || !mounted) return;

    final trimmedCaption = caption.trim();
    setState(() {
      _sending = true;
      _uploadProgress = 0.05;
    });
    try {
      ScheduledChatMessage? lastItem;
      final mediaGroupId =
          files.length >= 2 ? const Uuid().v4() : null;
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        if (!mounted) return;
        final itemCaption =
            (i == files.length - 1 && trimmedCaption.isNotEmpty)
                ? trimmedCaption
                : '';
        final isVideo = _looksLikeVideoFile(file);
        final prepared =
            isVideo ? await _normalizeVideoFileForUpload(file) : file;
        final uploaded = await MediaUploadService.uploadMediaFile(
          file: prepared,
          fileType: isVideo ? 'video' : 'image',
          waitForProcessing: false,
          onProgress: (p) {
            if (!mounted) return;
            final base = i / files.length;
            final span = 1 / files.length;
            _setUploadProgress(0.05 + (base + p * span) * 0.85, status: 'Загрузка…');
          },
        );
        final url = uploaded.url;
        if (url == null || url.isEmpty) {
          throw Exception('Не удалось загрузить медиа');
        }
        lastItem = await ChatService.scheduleMessage(
          conversationId: widget.conversationId,
          type: isVideo ? 'video' : 'image',
          content: itemCaption,
          mediaUrl: ServerConfig.resolveMediaUrl(url),
          sendAt: delivery.sendAt,
          sendWhenOnline: delivery.sendWhenOnline,
          silent: silent,
          mediaGroupId: mediaGroupId,
          hasSpoiler: hasSpoiler,
          replyToMessageId: i == 0 ? _replyTo?.id : null,
          clientMessageId: const Uuid().v4(),
          topicId: _activeTopicIdForSend,
        );
      }
      if (!mounted) return;
      setState(() => _replyTo = null);
      if (lastItem != null) _showScheduledSnack(lastItem);
      unawaited(_refreshScheduledPendingCount());
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e,
          fallback: 'Не удалось запланировать медиа');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _sendGallerySelection(
    List<XFile> files, {
    String caption = '',
    bool hasSpoiler = false,
    bool silent = false,
    bool isPaid = false,
    int priceStars = 0,
  }) async {
    if (files.isEmpty) return;
    final feeOk = await _ensurePaidDmFeeConfirmed();
    if (!feeOk || !mounted) return;
    final trimmedCaption = caption.trim();
    final mediaGroupId =
        files.length >= 2 ? const Uuid().v4() : null;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (!mounted) return;
      // Caption on the last item (Telegram album caption).
      final itemCaption =
          (i == files.length - 1 && trimmedCaption.isNotEmpty)
              ? trimmedCaption
              : '';
      if (_looksLikeVideoFile(file)) {
        final bytes = await file.length();
        if (bytes > 80 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Видео слишком большое (макс. 80 МБ). Пропущено.',
                ),
              ),
            );
          }
          continue;
        }
        await _sendPickedVideo(
          await _normalizeVideoFileForUpload(file),
          caption: itemCaption,
          mediaGroupId: mediaGroupId,
          hasSpoiler: hasSpoiler,
          silent: silent,
          isPaid: isPaid,
          priceStars: priceStars,
        );
      } else {
        await _sendPickedImage(
          file,
          caption: itemCaption,
          mediaGroupId: mediaGroupId,
          hasSpoiler: hasSpoiler,
          silent: silent,
          isPaid: isPaid,
          priceStars: priceStars,
        );
      }
    }
  }

  Future<int> _probeVideoDurationSec(XFile file) async {
    VideoPlayerController? controller;
    try {
      final path = file.path.trim();
      if (path.isEmpty) return 1;
      final uri = kIsWeb ||
              path.startsWith('blob:') ||
              path.startsWith('http://') ||
              path.startsWith('https://')
          ? Uri.parse(path)
          : Uri.file(path);
      controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize().timeout(const Duration(seconds: 8));
      return math.max(1, controller.value.duration.inSeconds);
    } catch (_) {
      return 1;
    } finally {
      final c = controller;
      controller = null;
      await c?.dispose();
    }
  }

  Future<void> _recordAndSendVideoNote() async {
    if (!_hasFlexFeature('video_notes')) {
      await showCreatorUpsell(context);
      return;
    }
    try {
      final picker = ImagePicker();
      final file = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 60),
      );
      if (file == null || !mounted) return;

      _setUploadProgress(0.05, status: 'Загрузка…');
      final prepared = await _normalizeVideoFileForUpload(file);
      if (!mounted) return;
      final durationSec = await _probeVideoDurationSec(prepared);
      if (!mounted) return;
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: prepared,
        fileType: 'video',
        waitForProcessing: false,
        onProgress: (p) {
          if (!mounted) return;
          _setUploadProgress(0.05 + p * 0.85, status: 'Загрузка…');
        },
      );
      final url = uploaded.url;
      if (url == null || url.isEmpty) {
        throw Exception('Не удалось загрузить видео');
      }
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadProgress = null;
        });
      }
      _enqueueReadyOutgoing(
        ChatReadyOutgoing(
          tempId: _newLocalTempId(),
          clientMessageId: const Uuid().v4(),
          type: 'video_note',
          content: '${durationSec < 1 ? 1 : durationSec}',
          mediaUrl: ServerConfig.resolveMediaUrl(url),
          replyToMessageId: _replyTo?.id,
          topicId: _activeTopicIdForSend,
          anonymous: _effectiveSendAnonymous,
          durationSec: durationSec,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _sendCurrentLocation({
    double? latitude,
    double? longitude,
    int? livePeriodSeconds,
  }) async {
    try {
      DeviceLatLng? pos;
      if (latitude != null && longitude != null) {
        pos = DeviceLatLng(latitude: latitude, longitude: longitude);
      } else {
        pos = await getDeviceLocation();
      }
      if (!mounted) return;
      if (pos == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb
                  ? 'Не удалось получить геолокацию. Разрешите доступ в браузере.'
                  : 'Не удалось получить геолокацию. Включите GPS и разрешите доступ к местоположению.',
            ),
          ),
        );
        return;
      }

      final isLive = livePeriodSeconds != null && livePeriodSeconds > 0;
      if (isLive) {
        final mode = await _askSendOrSchedule();
        if (mode == null || !mounted) return;
        if (_isScheduleMode(mode)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Трансляцию геопозиции нельзя отложить'),
            ),
          );
          return;
        }
        final expires = DateTime.now().toUtc().add(
          Duration(seconds: livePeriodSeconds),
        );
        _enqueueReadyOutgoing(
          ChatReadyOutgoing(
            tempId: _newLocalTempId(),
            clientMessageId: const Uuid().v4(),
            type: 'live_location',
            content: ChatLocationPayload.encode(
              latitude: pos.latitude,
              longitude: pos.longitude,
              isLive: true,
              periodSeconds: livePeriodSeconds,
              expiresAt: expires,
              updatedAt: DateTime.now().toUtc(),
            ),
            replyToMessageId: _replyTo?.id,
            silent: mode == 'silent',
            durationSec: livePeriodSeconds,
            latitude: pos.latitude,
            longitude: pos.longitude,
          ),
        );
        return;
      }

      final content = ChatLocationPayload.encode(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      final mode = await _askSendOrSchedule();
      if (mode == null || !mounted) return;
      if (_isScheduleMode(mode)) {
        final delivery = await _pickScheduleDelivery();
        if (delivery == null || !mounted) return;
        final item = await ChatService.scheduleMessage(
          conversationId: widget.conversationId,
          type: 'location',
          content: content,
          sendAt: delivery.sendAt,
          sendWhenOnline: delivery.sendWhenOnline,
          silent: _scheduleSilent(mode),
          replyToMessageId: _replyTo?.id,
          clientMessageId: const Uuid().v4(),
          topicId: _activeTopicIdForSend,
        );
        if (!mounted) return;
        setState(() => _replyTo = null);
        _showScheduledSnack(item);
        unawaited(_refreshScheduledPendingCount());
        return;
      }
      _enqueueReadyOutgoing(
        ChatReadyOutgoing(
          tempId: _newLocalTempId(),
          clientMessageId: const Uuid().v4(),
          type: 'location',
          content: content,
          replyToMessageId: _replyTo?.id,
          silent: mode == 'silent',
          topicId: _activeTopicIdForSend,
          anonymous: _effectiveSendAnonymous,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _stopLiveLocation(ChatMessage message) async {
    final previous = message;
    final optimistic = message.copyWith(
      content: ChatLocationPayload.patchStoppedInContent(message.content),
    );
    setState(() {
      final i = _messages.indexWhere((m) => m.id == message.id);
      if (i >= 0) _messages[i] = optimistic;
      if (_isMessagePinned(optimistic.id)) _replacePinnedMessage(optimistic);
    });
    try {
      final session = LiveLocationSession.activeFor(message.id);
      if (session != null) {
        await session.stopRemote();
      } else {
        await ChatService.stopLiveLocation(
          conversationId: widget.conversationId,
          messageId: message.id,
        );
      }
      unawaited(_pollNew());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == previous.id);
        if (i >= 0) _messages[i] = previous;
        if (_isMessagePinned(previous.id)) _replacePinnedMessage(previous);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _sendContact(ChatContact contact) async {
    if (_recording) return;
    final user = contact.user;
    await _sendContactText(
      ChatContactPayload.encode(
        displayName: user.displayName,
        username: user.username,
        userId: user.id,
      ),
    );
  }

  Future<void> _sendPhoneContact({
    required String displayName,
    required String phoneE164,
  }) async {
    if (_recording) return;
    await _sendContactText(
      ChatContactPayload.encode(
        displayName: displayName,
        phone: phoneE164,
      ),
    );
  }

  Future<void> _sendContactText(String text) async {
    _enqueueReadyOutgoing(
      ChatReadyOutgoing(
        tempId: _newLocalTempId(),
        clientMessageId: const Uuid().v4(),
        type: 'text',
        content: text,
        replyToMessageId: _replyTo?.id,
        topicId: _activeTopicIdForSend,
        anonymous: _effectiveSendAnonymous,
      ),
    );
  }

  Future<void> _createAndSendPoll() async {
    if (_recording) return;
    final draft = await CreateChatPollSheet.show(context);
    if (!mounted || draft == null) return;
    await _sendPollDraft(draft);
  }

  Future<void> _sendPollDraft(ChatPollDraft draft) async {
    if (_recording) return;
    final mode = await _askSendOrSchedule();
    if (mode == null || !mounted) return;
    if (_isScheduleMode(mode)) {
      final delivery = await _pickScheduleDelivery();
      if (delivery == null || !mounted) return;
      try {
        final item = await ChatService.scheduleMessage(
          conversationId: widget.conversationId,
          type: 'poll',
          content: draft.question,
          sendAt: delivery.sendAt,
          sendWhenOnline: delivery.sendWhenOnline,
          silent: _scheduleSilent(mode),
          replyToMessageId: _replyTo?.id,
          clientMessageId: const Uuid().v4(),
          pollQuestion: draft.question,
          pollDescription: draft.description,
          pollOptions: draft.options,
          pollSettings: draft.settings.toJson(),
          topicId: _activeTopicIdForSend,
        );
        if (!mounted) return;
        setState(() => _replyTo = null);
        _showScheduledSnack(item);
        unawaited(_refreshScheduledPendingCount());
      } catch (e) {
        if (!mounted) return;
        showErrorSnackBar(
          context,
          e,
          fallback: 'Не удалось запланировать опрос',
        );
      }
      return;
    }
    _enqueueReadyOutgoing(
      ChatReadyOutgoing(
        tempId: _newLocalTempId(),
        clientMessageId: const Uuid().v4(),
        type: 'poll',
        content: optimisticPollContent(
          question: draft.question,
          description: draft.description,
          options: draft.options,
          settings: draft.settings.toJson(),
        ),
        replyToMessageId: _replyTo?.id,
        silent: mode == 'silent',
        topicId: _activeTopicIdForSend,
        pollQuestion: draft.question,
        pollDescription: draft.description,
        pollOptions: draft.options,
        pollSettings: draft.settings.toJson(),
      ),
    );
  }

  Future<void> _createAndSendChecklist() async {
    if (_recording) return;
    final draft = await CreateChatChecklistSheet.show(context);
    if (!mounted || draft == null) return;
    await _sendChecklistDraft(draft);
  }

  Future<void> _sendChecklistDraft(ChatChecklistDraft draft) async {
    if (_recording) return;
    if (!hasFlexFeature('checklist')) {
      await showCreatorUpsell(context);
      return;
    }
    final mode = await _askSendOrSchedule();
    if (mode == null || !mounted) return;
    if (_isScheduleMode(mode)) {
      final delivery = await _pickScheduleDelivery();
      if (delivery == null || !mounted) return;
      try {
        final item = await ChatService.scheduleMessage(
          conversationId: widget.conversationId,
          type: 'checklist',
          content: draft.optimisticContent,
          sendAt: delivery.sendAt,
          sendWhenOnline: delivery.sendWhenOnline,
          silent: _scheduleSilent(mode),
          replyToMessageId: _replyTo?.id,
          clientMessageId: const Uuid().v4(),
          checklistTitle: draft.title,
          checklistItems: draft.items,
          topicId: _activeTopicIdForSend,
        );
        if (!mounted) return;
        setState(() => _replyTo = null);
        _showScheduledSnack(item);
        unawaited(_refreshScheduledPendingCount());
      } catch (e) {
        if (!mounted) return;
        if (offerFlexIfRequired(context, e)) return;
        showErrorSnackBar(
          context,
          e,
          fallback: 'Не удалось запланировать чеклист',
        );
      }
      return;
    }
    _enqueueReadyOutgoing(
      ChatReadyOutgoing(
        tempId: _newLocalTempId(),
        clientMessageId: const Uuid().v4(),
        type: 'checklist',
        content: draft.optimisticContent,
        replyToMessageId: _replyTo?.id,
        silent: mode == 'silent',
        topicId: _activeTopicIdForSend,
        checklistTitle: draft.title,
        checklistItems: draft.items,
      ),
    );
  }

  Future<void> _resendStoredFile({
    required String name,
    required String mediaUrl,
  }) async {
    if (_recording) return;
    final mode = await _askSendOrSchedule();
    if (mode == null || !mounted) return;
    final resolved = ServerConfig.resolveMediaUrl(mediaUrl);
    if (_isScheduleMode(mode)) {
      final delivery = await _pickScheduleDelivery();
      if (delivery == null || !mounted) return;
      try {
        final item = await ChatService.scheduleMessage(
          conversationId: widget.conversationId,
          type: 'file',
          content: name,
          mediaUrl: resolved,
          sendAt: delivery.sendAt,
          sendWhenOnline: delivery.sendWhenOnline,
          silent: _scheduleSilent(mode),
          replyToMessageId: _replyTo?.id,
          clientMessageId: const Uuid().v4(),
          topicId: _activeTopicIdForSend,
        );
        if (!mounted) return;
        setState(() => _replyTo = null);
        _showScheduledSnack(item);
        unawaited(_refreshScheduledPendingCount());
      } catch (e) {
        if (!mounted) return;
        showErrorSnackBar(
          context,
          e,
          fallback: 'Не удалось запланировать файл',
        );
      }
      return;
    }
    _enqueueReadyOutgoing(
      ChatReadyOutgoing(
        tempId: _newLocalTempId(),
        clientMessageId: const Uuid().v4(),
        type: 'file',
        content: name,
        mediaUrl: resolved,
        fileName: name,
        replyToMessageId: _replyTo?.id,
        silent: mode == 'silent',
        topicId: _activeTopicIdForSend,
        anonymous: _effectiveSendAnonymous,
      ),
    );
  }

  Future<void> _toggleChecklist(ChatMessage msg, int index, bool done) async {
    if (msg.id <= 0 || _togglingChecklistIds.contains(msg.id)) return;
    final previous = msg;
    final current = msg.checklist;
    final optimistic = current == null
        ? msg
        : msg.copyWith(content: current.toggled(index, done).encode());
    setState(() {
      _togglingChecklistIds.add(msg.id);
      final i = _messages.indexWhere((m) => m.id == msg.id);
      if (i >= 0) _messages[i] = optimistic;
    });
    try {
      final updated = await ChatService.toggleChecklist(
        conversationId: widget.conversationId,
        messageId: msg.id,
        index: index,
        done: done,
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i >= 0) _messages[i] = updated;
      });
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    } catch (e) {
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.id == previous.id);
          if (i >= 0) _messages[i] = previous;
        });
        showErrorSnackBar(context, e, fallback: 'Не удалось отметить пункт');
      }
    } finally {
      if (mounted) setState(() => _togglingChecklistIds.remove(msg.id));
    }
  }

  Future<void> _transcribeVoice(ChatMessage msg) async {
    if (msg.id <= 0 || _transcribingIds.contains(msg.id)) return;
    if (!_hasFlexFeature('voice_to_text')) {
      await showCreatorUpsell(context);
      return;
    }
    setState(() => _transcribingIds.add(msg.id));
    try {
      final updated = await ChatService.transcribeMessage(
        conversationId: widget.conversationId,
        messageId: msg.id,
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i >= 0) _messages[i] = updated;
      });
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    } catch (e) {
      if (!mounted) return;
      if (offerFlexIfRequired(context, e)) return;
      showErrorSnackBar(context, e, fallback: 'Не удалось распознать голос');
    } finally {
      if (mounted) setState(() => _transcribingIds.remove(msg.id));
    }
  }

  Future<void> _votePoll(ChatMessage msg, int optionIndex) async {
    if (msg.id <= 0 || _votingPollIds.contains(msg.id)) return;
    final previous = msg;
    final optimistic = msg.copyWith(
      content: applyOptimisticPollVoteToContent(msg.content, optionIndex),
    );
    setState(() {
      _votingPollIds.add(msg.id);
      final i = _messages.indexWhere((m) => m.id == msg.id);
      if (i >= 0) _messages[i] = optimistic;
    });
    try {
      final updated = await ChatService.votePoll(
        conversationId: widget.conversationId,
        messageId: msg.id,
        optionIndex: optionIndex,
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i >= 0) _messages[i] = updated;
      });
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    } catch (e) {
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.id == previous.id);
          if (i >= 0) _messages[i] = previous;
        });
        showErrorSnackBar(context, e, fallback: 'Не удалось проголосовать');
      }
    } finally {
      if (mounted) setState(() => _votingPollIds.remove(msg.id));
    }
  }

  Future<void> _closePoll(ChatMessage msg) async {
    if (_closingPollIds.contains(msg.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Закрыть опрос?'),
        content: const Text(
          'После закрытия голосовать будет нельзя. Результаты останутся видны.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final previous = msg;
    final optimistic = msg.copyWith(
      content: patchChatPollClosedInContent(msg.content, isClosed: true),
    );
    setState(() {
      _closingPollIds.add(msg.id);
      final i = _messages.indexWhere((m) => m.id == msg.id);
      if (i >= 0) _messages[i] = optimistic;
      if (_isMessagePinned(msg.id)) _replacePinnedMessage(optimistic);
    });
    try {
      final updated = await ChatService.closePoll(
        conversationId: widget.conversationId,
        messageId: msg.id,
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i >= 0) _messages[i] = updated;
        if (_isMessagePinned(updated.id)) _replacePinnedMessage(updated);
      });
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    } catch (e) {
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.id == previous.id);
          if (i >= 0) _messages[i] = previous;
          if (_isMessagePinned(previous.id)) _replacePinnedMessage(previous);
        });
        showErrorSnackBar(context, e, fallback: 'Не удалось закрыть опрос');
      }
    } finally {
      if (mounted) setState(() => _closingPollIds.remove(msg.id));
    }
  }

  Future<void> _addPollOption(ChatMessage msg) async {
    if (msg.id <= 0 || msg.type != 'poll') return;
    final controller = TextEditingController();
    String? text;
    try {
      text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Новый вариант'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(
              hintText: 'Текст варианта',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Добавить'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (text == null || text.isEmpty || !mounted) return;
    final previous = msg;
    final optimistic = msg.copyWith(
      content: applyOptimisticPollOptionToContent(msg.content, text),
    );
    setState(() {
      final i = _messages.indexWhere((m) => m.id == msg.id);
      if (i >= 0) _messages[i] = optimistic;
      if (_isMessagePinned(optimistic.id)) _replacePinnedMessage(optimistic);
    });
    try {
      final updated = await ChatService.addPollOption(
        conversationId: widget.conversationId,
        messageId: msg.id,
        text: text,
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i >= 0) _messages[i] = updated;
        if (_isMessagePinned(updated.id)) _replacePinnedMessage(updated);
      });
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    } catch (e) {
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.id == previous.id);
          if (i >= 0) _messages[i] = previous;
          if (_isMessagePinned(previous.id)) _replacePinnedMessage(previous);
        });
        showErrorSnackBar(context, e, fallback: 'Не удалось добавить вариант');
      }
    }
  }

  Future<void> _tapInlineButton(
    ChatMessage msg,
    ChatInlineKeyboardButton button,
  ) async {
    if (button.isWebApp) {
      try {
        final launch = await MiniAppsService.getLaunchContext(
          button.miniAppId!,
          conversationId: widget.conversationId,
        );
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MiniAppWebViewScreen(
              title: button.text.trim().isNotEmpty ? button.text.trim() : 'Mini App',
              subtitle: '',
              url: launch.url,
              initData: launch.initData,
              initDataUnsafe: launch.initDataUnsafe,
              miniAppId: button.miniAppId,
              conversationId: widget.conversationId,
            ),
          ),
        );
      } catch (e) {
        if (mounted) {
          showErrorSnackBar(context, e, fallback: 'Не удалось открыть Mini App');
        }
      }
      return;
    }
    final url = button.url?.trim();
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Некорректная ссылка кнопки')),
          );
        }
        return;
      }
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть ссылку')),
        );
      }
      return;
    }
    final data = button.callbackData?.trim();
    if (data == null || data.isEmpty) return;
    final key = '${msg.id}:$data';
    if (_callbackInFlightKeys.contains(key)) return;
    setState(() => _callbackInFlightKeys.add(key));
    unawaited(() async {
      try {
        final botReply = await ChatService.sendInlineCallback(
          conversationId: widget.conversationId,
          messageId: msg.id,
          data: data,
        );
        if (!mounted) return;
        setState(() {
          _integrateMessage(botReply);
        });
        _scrollToBottom();
        unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
      } catch (e) {
        if (mounted) {
          showErrorSnackBar(context, e,
              fallback: 'Не удалось выполнить действие');
        }
      } finally {
        if (mounted) {
          setState(() => _callbackInFlightKeys.remove(key));
        }
      }
    }());
  }

  bool _looksLikeVideoFile(XFile file) {
    final name = file.name.toLowerCase();
    return name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.avi') ||
        name.endsWith('.mkv');
  }

  Future<void> _pickFromMediaLibrary() async {
    if (_recording) return;
    final picker = ImagePicker();
    final file = await picker.pickMedia(
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null) return;
    if (_looksLikeVideoFile(file)) {
      final bytes = await file.length();
      if (bytes > 80 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Видео слишком большое (макс. 80 МБ). Выберите короче или сожмите файл.',
              ),
            ),
          );
        }
        return;
      }
      await _sendPickedVideo(await _normalizeVideoFileForUpload(file));
    } else {
      await _sendPickedImage(file);
    }
  }

  Future<void> _sendPickedImage(
    XFile file, {
    int? replyToId,
    String? clientMessageId,
    String caption = '',
    String? mediaGroupId,
    bool hasSpoiler = false,
    bool silent = false,
    bool isPaid = false,
    int priceStars = 0,
  }) async {
    int? totalBytes;
    Uint8List? previewBytes;
    try {
      totalBytes = await file.length();
      if (totalBytes <= 8 * 1024 * 1024) {
        previewBytes = await file.readAsBytes();
      }
    } catch (_) {
      try {
        totalBytes = await file.length();
      } catch (_) {
        totalBytes = null;
      }
    }
    _enqueueMediaSend(_PendingMediaSend(
      tempId: _newLocalTempId(),
      kind: _PendingMediaKind.image,
      file: file,
      clientMessageId: clientMessageId ?? const Uuid().v4(),
      replyToMessageId: replyToId ?? _replyTo?.id,
      caption: caption,
      totalBytes: totalBytes,
      previewBytes: previewBytes,
      payloadBytes: previewBytes,
      silent: silent,
      mediaGroupId: mediaGroupId,
      hasSpoiler: hasSpoiler,
      isPaid: isPaid,
      priceStars: priceStars,
      topicId: _activeTopicIdForSend,
      anonymous: _effectiveSendAnonymous,
    ));
  }

  Future<void> _sendPickedVideo(
    XFile file, {
    int? replyToId,
    String? clientMessageId,
    String caption = '',
    String? mediaGroupId,
    bool hasSpoiler = false,
    bool silent = false,
    bool isPaid = false,
    int priceStars = 0,
  }) async {
    int? totalBytes;
    try {
      totalBytes = await file.length();
    } catch (_) {
      totalBytes = null;
    }
    _enqueueMediaSend(_PendingMediaSend(
      tempId: _newLocalTempId(),
      kind: _PendingMediaKind.video,
      file: file,
      clientMessageId: clientMessageId ?? const Uuid().v4(),
      replyToMessageId: replyToId ?? _replyTo?.id,
      caption: caption,
      totalBytes: totalBytes,
      silent: silent,
      mediaGroupId: mediaGroupId,
      hasSpoiler: hasSpoiler,
      isPaid: isPaid,
      priceStars: priceStars,
      topicId: _activeTopicIdForSend,
      anonymous: _effectiveSendAnonymous,
    ));
  }

  /// На web браузер часто отдаёт webm без расширения в имени — бэкенд тогда отклоняет upload.
  Future<XFile> _normalizeVideoFileForUpload(XFile file) async {
    if (!kIsWeb) return file;
    final name = file.name.trim();
    final lower = name.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.avi')) {
      return file;
    }
    final bytes = await file.readAsBytes();
    final ext = lower.contains('quicktime') ? 'mov' : 'webm';
    final safeName = name.isEmpty
        ? 'video_${DateTime.now().millisecondsSinceEpoch}.$ext'
        : '$name.$ext';
    return XFile.fromData(bytes, name: safeName, mimeType: 'video/$ext');
  }

  Future<void> _pickFile() async {
    if (_recording) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'doc', 'docx', 'zip'],
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final XFile file;
      if (kIsWeb) {
        final bytes = picked.bytes;
        if (bytes == null || bytes.isEmpty) return;
        file = XFile.fromData(bytes, name: picked.name);
      } else {
        final path = picked.path;
        if (path == null || path.isEmpty) return;
        file = XFile(path);
      }
      await _sendPickedFile(file, fileName: picked.name);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: 'Не удалось выбрать файл');
    }
  }

  Future<void> _sendPickedFile(
    XFile file, {
    required String fileName,
    int? replyToId,
    String? clientMessageId,
  }) async {
    final mode = await _askSendOrSchedule();
    if (mode == null || !mounted) return;
    if (_isScheduleMode(mode)) {
      await _schedulePickedFile(
        file,
        fileName: fileName,
        replyToId: replyToId,
        silent: _scheduleSilent(mode),
      );
      return;
    }
    int? totalBytes;
    try {
      totalBytes = await file.length();
    } catch (_) {
      totalBytes = null;
    }
    _enqueueMediaSend(_PendingMediaSend(
      tempId: _newLocalTempId(),
      kind: _PendingMediaKind.file,
      file: file,
      fileName: fileName,
      clientMessageId: clientMessageId ?? const Uuid().v4(),
      replyToMessageId: replyToId ?? _replyTo?.id,
      totalBytes: totalBytes,
      silent: mode == 'silent',
      topicId: _activeTopicIdForSend,
      anonymous: _effectiveSendAnonymous,
    ));
  }

  Future<void> _schedulePickedFile(
    XFile file, {
    required String fileName,
    int? replyToId,
    bool silent = false,
  }) async {
    final delivery = await _pickScheduleDelivery();
    if (delivery == null || !mounted) return;
    setState(() {
      _sending = true;
      _uploadProgress = 0.1;
    });
    try {
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: file,
        fileType: 'document',
        waitForProcessing: false,
        onProgress: (p) {
          if (!mounted) return;
          _setUploadProgress(0.1 + p * 0.8, status: 'Загрузка…');
        },
      );
      final url = uploaded.url;
      if (url == null || url.isEmpty) {
        throw Exception('Не удалось загрузить файл');
      }
      final item = await ChatService.scheduleMessage(
        conversationId: widget.conversationId,
        type: 'file',
        content: fileName,
        mediaUrl: ServerConfig.resolveMediaUrl(url),
        sendAt: delivery.sendAt,
        sendWhenOnline: delivery.sendWhenOnline,
        silent: silent,
        replyToMessageId: replyToId ?? _replyTo?.id,
        clientMessageId: const Uuid().v4(),
        topicId: _activeTopicIdForSend,
      );
      if (!mounted) return;
      setState(() => _replyTo = null);
      _showScheduledSnack(item);
      unawaited(_refreshScheduledPendingCount());
      unawaited(
        _rememberRecentFile(name: fileName, file: file, mediaUrl: url),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: 'Не удалось запланировать файл');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _rememberRecentFile({
    required String name,
    required XFile file,
    required String mediaUrl,
  }) async {
    var size = 0;
    try {
      size = await file.length();
    } catch (_) {}
    await ChatRecentFilesStore.remember(
      name: name,
      sizeBytes: size,
      mediaUrl: mediaUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isGroup = _conversation.isGroup;
    final isSaved = _conversation.isSaved;
    final peer = _conversation.peer;
    final apiReachable = ApiReachabilityService.instance.isApiReachable.value;
    final apiConnecting = ApiReachabilityService.instance.isApiConnecting.value;
    String subtitle = '';
    // Telegram-style: connection status takes priority over last-seen.
    if (!FeedSyncService.onlineListenable.value) {
      subtitle = 'Ожидание сети…';
    } else if (!apiReachable || apiConnecting) {
      subtitle = 'соединение…';
    } else if (!_sseConnected) {
      subtitle = 'обновление…';
    } else if (isSaved) {
      subtitle = 'Сохраняйте сообщения и заметки';
    } else if (_peerTyping) {
      subtitle = _typingSubtitleLabel(isGroup: isGroup);
    } else if (isGroup) {
      subtitle = '${_conversation.memberCount} участников';
    } else if (peer != null) {
      subtitle =
          peer.isOnline ? 'в сети' : formatLastSeen(peer.lastSeenAt);
    }
    if (_muted &&
        subtitle.isNotEmpty &&
        !subtitle.startsWith('соединение') &&
        !subtitle.startsWith('обновление') &&
        !subtitle.startsWith('Ожидание')) {
      subtitle =
          '$subtitle · ${formatChatMuteUntilLabel(
            _conversation.mutedUntil,
            notifyMode: _conversation.notifyMode,
          )}';
    } else if (_muted && subtitle.isEmpty) {
      subtitle = formatChatMuteUntilLabel(
        _conversation.mutedUntil,
        notifyMode: _conversation.notifyMode,
      );
    }
    final connectingHeader = subtitle == 'соединение…' ||
        subtitle == 'обновление…' ||
        subtitle == 'Ожидание сети…';
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: isSaved
              ? scheme.onSurfaceVariant
              : connectingHeader ||
                      _peerTyping ||
                      (!isGroup && (peer?.isOnline ?? false))
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
        );
    final visibleMessages = _visibleMessages;
    final messageClusters = _computeMessageClusters(visibleMessages);
    final messageDateSeparators = _computeDateSeparators(visibleMessages);
    _trimMessageItemKeys(visibleMessages);
    final searchHasCriteria = _threadSearchHasCriteria;
    final searchMatchIds = searchHasCriteria ? _searchMatchIds : const <int>[];
    final searching = _threadSearchQuery.trim().isNotEmpty;
    final activeSearchMatchId = searchMatchIds.isNotEmpty
        ? searchMatchIds[_searchMatchIndex.clamp(0, searchMatchIds.length - 1)]
        : _focusedMessageId;
    final mediaCount = _mediaMessageCount();
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isRestrictedByModeration = _conversation.isGroup &&
        _conversation.amISendRestricted &&
        !_conversation.amIGroupAdmin;
    final peerBlockedByMe = !isGroup &&
        !isSaved &&
        _conversation.peerBlockedByMe;
    final canSendInGroup = !(_conversation.isGroup &&
            _conversation.onlyAdminsCanPost &&
            !_conversation.amIGroupAdmin) &&
        !isRestrictedByModeration;
    final canCompose =
        canSendInGroup && !peerBlockedByMe && !_selectedTopicIsClosed;
    String formatSlowMode(int seconds) {
      if (seconds <= 0) return 'выкл';
      if (seconds < 60) return '$seconds сек';
      if (seconds % 60 == 0) return '${seconds ~/ 60} мин';
      return '${seconds ~/ 60}м ${seconds % 60}с';
    }

    final showPostingLimitsHint = _conversation.isGroup &&
        canCompose &&
        !_conversation.amIGroupAdmin &&
        (_conversation.slowModeSeconds > 0 ||
            _conversation.antiFloodMaxMessagesPerMinute > 0);
    final slowModeRemainingSeconds = _slowModeRemainingSeconds;
    final floodRemainingSeconds = _floodRemainingSeconds;
    final activeCooldownSeconds = _activeCooldownRemainingSeconds;
    final floodCooldownActive = floodRemainingSeconds > 0 &&
        floodRemainingSeconds >= slowModeRemainingSeconds;
    final activeCooldownLabel = floodCooldownActive ? 'Антифлуд' : 'Slow mode';
    final activeCooldownIcon =
        floodCooldownActive ? Icons.speed_outlined : Icons.timer_outlined;
    final activeCooldownProgress = floodCooldownActive &&
            _floodCooldownTotalSeconds > 0
        ? ((1 - (floodRemainingSeconds / _floodCooldownTotalSeconds))
                .clamp(0.0, 1.0))
            .toDouble()
        : (_conversation.slowModeSeconds > 0 && slowModeRemainingSeconds > 0)
            ? ((1 - (slowModeRemainingSeconds / _conversation.slowModeSeconds))
                    .clamp(0.0, 1.0))
                .toDouble()
            : null;
    final isSlowModeUnlockSoon =
        activeCooldownSeconds > 0 && activeCooldownSeconds <= 3;
    final slowModePulseScale =
        isSlowModeUnlockSoon && activeCooldownSeconds.isOdd ? 1.08 : 1.0;
    final canSendNow = canCompose && activeCooldownSeconds <= 0;
    final retryBulkProgressLabel = _retryAllBulkBusy && _retryAllBulkTotal > 0
        ? '${_retryAllBulkDone.clamp(0, _retryAllBulkTotal)}/$_retryAllBulkTotal'
        : null;
    final postingLimitsHint = [
      if (_conversation.slowModeSeconds > 0)
        'Slow mode: ${formatSlowMode(_conversation.slowModeSeconds)}',
      if (_conversation.antiFloodMaxMessagesPerMinute > 0)
        'Антифлуд: ${_conversation.antiFloodMaxMessagesPerMinute}/мин',
      if (activeCooldownSeconds > 0)
        '$activeCooldownLabel: отправка через ${_formatSlowModeCountdown(activeCooldownSeconds)}',
    ].join(' • ');

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _exitSelectionMode();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.telegramChatBgDark
            : AppColors.telegramChatBgLight,
        resizeToAvoidBottomInset: false,
        appBar: _selectionMode
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Закрыть',
                  onPressed: _exitSelectionMode,
                  icon: const Icon(Icons.close),
                ),
                title: Text(
                  _selectedMessageIds.length == 1
                      ? '1'
                      : '${_selectedMessageIds.length}',
                ),
                centerTitle: true,
              )
            : AppBar(
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF18222D)
                    : scheme.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                toolbarHeight: 56,
                titleSpacing: 4,
                iconTheme: IconThemeData(
                  size: 21,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.9)
                      : scheme.onSurface,
                ),
                title: GestureDetector(
                  onTap: isSaved
                      ? null
                      : isGroup
                          ? _openGroupInfo
                          : () => unawaited(_openDirectChatInfo()),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      if (!isSaved && !isGroup && peer != null) ...[
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AppUserAvatar(
                              radius: 18,
                              imageUrl: peer.avatarUrl,
                              displayName: peer.displayName,
                              onTap: _openPeerProfile,
                            ),
                            if (peer.isOnline)
                              Positioned(
                                right: -1,
                                bottom: -1,
                                child: Container(
                                  width: 11,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? const Color(0xFF18222D)
                                          : scheme.surface,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: HighlightedText(
                                    text: _conversation.isGroup
                                        ? _conversation.displayTitle
                                        : (_conversation.peer?.displayName ??
                                            _conversation.displayTitle),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.1,
                                              color: () {
                                                final hex = profileColorHex(
                                                  _conversation.peer?.profileColor,
                                                );
                                                if (hex.isEmpty ||
                                                    _conversation.isGroup) {
                                                  return null;
                                                }
                                                return Color(
                                                  int.parse(
                                                    hex.replaceFirst('#', '0xFF'),
                                                  ),
                                                );
                                              }(),
                                            ) ??
                                        const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                  ),
                                ),
                                if (!_conversation.isGroup &&
                                    (_conversation.peer?.emojiStatus ?? '')
                                        .trim()
                                        .isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  StatusEmojiView(
                                    status: _conversation.peer!.emojiStatus,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                            if (subtitle.isNotEmpty)
                              _peerTyping
                                  ? Row(
                                      children: [
                                        Flexible(
                                          child: HighlightedText(
                                            text: subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: subtitleStyle?.copyWith(
                                                  fontSize: 12,
                                                ) ??
                                                const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        TelegramTypingDots(
                                          color: scheme.primary,
                                          size: 3.2,
                                        ),
                                      ],
                                    )
                                  : Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          subtitleStyle?.copyWith(fontSize: 12),
                                    ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                bottom: _threadSearchOpen
                    ? PreferredSize(
                        preferredSize: const Size.fromHeight(102),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Builder(
                            builder: (context) {
                              final matches = searchMatchIds;
                              final hasCriteria = searchHasCriteria;
                              final hasMatches = matches.isNotEmpty;
                              final currentIndex = hasMatches
                                  ? _searchMatchIndex.clamp(
                                          0, matches.length - 1) +
                                      1
                                  : 0;
                              final chipBorderColor =
                                  Theme.of(context).colorScheme.outlineVariant;
                              final chipSelectedColor = Theme.of(context)
                                  .colorScheme
                                  .primaryContainer;
                              final chipLabelColor = Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant;
                              final chipSelectedLabelColor = Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer;
                              return Column(
                                children: [
                                  Focus(
                                    onKeyEvent: (_, event) {
                                      if (event is! KeyDownEvent ||
                                          !hasMatches ||
                                          event.logicalKey !=
                                              LogicalKeyboardKey.enter) {
                                        return KeyEventResult.ignored;
                                      }
                                      final pressed = HardwareKeyboard
                                          .instance.logicalKeysPressed;
                                      if (pressed.contains(
                                            LogicalKeyboardKey.shiftLeft,
                                          ) ||
                                          pressed.contains(
                                            LogicalKeyboardKey.shiftRight,
                                          )) {
                                        _goToSearchMatch(false);
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                    child: TextField(
                                      focusNode: _threadSearchFocusNode,
                                      controller: _threadSearchController,
                                      autofocus: true,
                                      onChanged: _onThreadSearchChanged,
                                      onSubmitted: (_) {
                                        if (hasMatches) _goToSearchMatch(true);
                                      },
                                      decoration: InputDecoration(
                                        hintText: 'Поиск в чате',
                                        prefixIcon: const Icon(Icons.search),
                                        helperText: hasCriteria && !hasMatches
                                            ? (_searchAutoloading
                                                ? 'Ищем в истории…'
                                                : 'Ничего не найдено')
                                            : null,
                                        suffixIcon: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_searchAutoloading)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 4,
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '$_searchBackfillLoads',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            IconButton(
                                              tooltip: 'К первому совпадению',
                                              icon: const Icon(
                                                Icons.vertical_align_top,
                                              ),
                                              onPressed: hasMatches
                                                  ? _jumpToFirstSearchMatch
                                                  : null,
                                            ),
                                            Text(
                                              '$currentIndex/${matches.length}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall,
                                            ),
                                            IconButton(
                                              tooltip: 'Предыдущее',
                                              icon: const Icon(
                                                Icons.keyboard_arrow_up,
                                              ),
                                              onPressed: hasMatches
                                                  ? () =>
                                                      _goToSearchMatch(false)
                                                  : null,
                                            ),
                                            IconButton(
                                              tooltip: 'Следующее',
                                              icon: const Icon(
                                                Icons.keyboard_arrow_down,
                                              ),
                                              onPressed: hasMatches
                                                  ? () => _goToSearchMatch(true)
                                                  : null,
                                            ),
                                            IconButton(
                                              tooltip: 'Закрыть',
                                              icon: const Icon(Icons.close),
                                              onPressed: _toggleThreadSearch,
                                            ),
                                          ],
                                        ),
                                        isDense: true,
                                        filled: true,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: 28,
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      children: [
                                        for (final filter
                                            in _ThreadSearchFilter.values)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: ChoiceChip(
                                              label: Text(
                                                _searchFilterLabel(filter),
                                              ),
                                              selected:
                                                  _threadSearchFilter == filter,
                                              onSelected: (_) =>
                                                  _onThreadSearchFilterChanged(
                                                filter,
                                              ),
                                              shape: StadiumBorder(
                                                side: BorderSide(
                                                  color: _threadSearchFilter ==
                                                          filter
                                                      ? chipSelectedColor
                                                      : chipBorderColor,
                                                ),
                                              ),
                                              backgroundColor:
                                                  Colors.transparent,
                                              selectedColor: chipSelectedColor,
                                              labelStyle: TextStyle(
                                                color: _threadSearchFilter ==
                                                        filter
                                                    ? chipSelectedLabelColor
                                                    : chipLabelColor,
                                                fontWeight:
                                                    _threadSearchFilter ==
                                                            filter
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ),
                                        if (isGroup)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: FilterChip(
                                              avatar: Icon(
                                                _threadSearchSenderId == null
                                                    ? Icons.person_outline
                                                    : Icons.person,
                                                size: 16,
                                                color: _threadSearchSenderId ==
                                                        null
                                                    ? chipLabelColor
                                                    : chipSelectedLabelColor,
                                              ),
                                              label: HighlightedText(
                                                text: _searchSenderLabel(),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: _threadSearchSenderId ==
                                                          null
                                                      ? chipLabelColor
                                                      : chipSelectedLabelColor,
                                                ),
                                              ),
                                              selected:
                                                  _threadSearchSenderId != null,
                                              onSelected: (_) =>
                                                  _pickThreadSearchSender(),
                                              onDeleted: _threadSearchSenderId ==
                                                      null
                                                  ? null
                                                  : () =>
                                                      _onThreadSearchSenderChanged(
                                                        null,
                                                      ),
                                              deleteIcon: const Icon(
                                                Icons.close,
                                                size: 16,
                                              ),
                                              shape: StadiumBorder(
                                                side: BorderSide(
                                                  color:
                                                      _threadSearchSenderId !=
                                                              null
                                                          ? chipSelectedColor
                                                          : chipBorderColor,
                                                ),
                                              ),
                                              backgroundColor:
                                                  Colors.transparent,
                                              selectedColor: chipSelectedColor,
                                              labelStyle: TextStyle(
                                                color: _threadSearchSenderId !=
                                                        null
                                                    ? chipSelectedLabelColor
                                                    : chipLabelColor,
                                                fontWeight:
                                                    _threadSearchSenderId !=
                                                            null
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: FilterChip(
                                            avatar: Icon(
                                              _threadSearchDate == null
                                                  ? Icons.calendar_today_outlined
                                                  : Icons.calendar_today,
                                              size: 16,
                                              color: _threadSearchDate == null
                                                  ? chipLabelColor
                                                  : chipSelectedLabelColor,
                                            ),
                                            label: Text(_searchDateLabel()),
                                            selected: _threadSearchDate != null,
                                            onSelected: (_) =>
                                                unawaited(_pickThreadSearchDate()),
                                            onDeleted: _threadSearchDate == null
                                                ? null
                                                : () =>
                                                    _onThreadSearchDateChanged(
                                                      null,
                                                    ),
                                            deleteIcon: const Icon(
                                              Icons.close,
                                              size: 16,
                                            ),
                                            shape: StadiumBorder(
                                              side: BorderSide(
                                                color: _threadSearchDate != null
                                                    ? chipSelectedColor
                                                    : chipBorderColor,
                                              ),
                                            ),
                                            backgroundColor: Colors.transparent,
                                            selectedColor: chipSelectedColor,
                                            labelStyle: TextStyle(
                                              color: _threadSearchDate != null
                                                  ? chipSelectedLabelColor
                                                  : chipLabelColor,
                                              fontWeight:
                                                  _threadSearchDate != null
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      )
                    : null,
                actions: [
                  IconButton(
                    tooltip: _scheduledPendingCount > 0
                        ? 'Отложенные ($_scheduledPendingCount)'
                        : 'Отложенные',
                    onPressed: _openScheduledMessagesManager,
                    icon: Badge(
                      isLabelVisible: _scheduledPendingCount > 0,
                      label: Text(
                        _scheduledPendingCount > 99
                            ? '99+'
                            : '$_scheduledPendingCount',
                        style: const TextStyle(fontSize: 10),
                      ),
                      child: const Icon(Icons.schedule_outlined),
                    ),
                  ),
                  if ((!isGroup && peer != null) || isGroup) ...[
                    IconButton(
                      tooltip: 'Связь',
                      icon: const Icon(Icons.call_outlined),
                      onPressed: _showQuickCallMenu,
                    ),
                  ],
                  IconButton(
                    tooltip: 'Ещё',
                    icon: const Icon(Icons.more_vert),
                    onPressed: _showThreadActionsSheet,
                  ),
                ],
              ),
        body: Stack(
          children: [
            AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: ChatWallpaper(
            isDark: Theme.of(context).brightness == Brightness.dark,
            style: _wallpaperStyle,
            backgroundImage: _wallpaperImage,
            child: Column(
            children: [
              _animatedVisibility(
                visible: _loading,
                keyName: 'thread-loading',
                child: const SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              ),
              if (_conversation.isForum) _buildForumTopicsStrip(scheme),
              if (_conversation.isSaved) _buildSavedTagsBar(scheme),
              _animatedVisibility(
                visible: _showOnlyFailedMessages,
                keyName: 'thread-failed-filter',
                child: Material(
                  color: scheme.primaryContainer.withValues(alpha: 0.75),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.filter_alt_outlined,
                          size: 16,
                          color: scheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _failedPendingItemsCount == 0
                                ? 'Фильтр: только неотправленные (пусто)'
                                : 'Фильтр: только неотправленные ($_failedPendingItemsCount)',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _setShowOnlyFailedMessages(false);
                          },
                          child: const Text('Сбросить'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _animatedVisibility(
                visible: _pinnedMessage != null,
                keyName: 'thread-pinned',
                child: _pinnedMessage == null
                    ? const SizedBox.shrink()
                    : Material(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF18222D)
                            : scheme.surface,
                        child: InkWell(
                          onTap: _cyclePinnedBanner,
                          onLongPress: () =>
                              unawaited(_showPinnedMessagesSheet()),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 2.5,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (_pinnedMediaLeading(_pinnedMessage!)
                                    case final thumb?) ...[
                                  thumb,
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _pinnedMessages.length > 1
                                            ? 'Закреплено (${_pinnedMessages.length})'
                                            : 'Закреплено',
                                        style: TextStyle(
                                          color: scheme.primary,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.15,
                                        ),
                                      ),
                                      Text(
                                        _pinnedPreview(_pinnedMessage!),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 13,
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_pinnedMessages.length > 1)
                                  IconButton(
                                    tooltip: 'Все закреплённые',
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.list_alt_outlined,
                                      size: 18,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    onPressed: () =>
                                        unawaited(_showPinnedMessagesSheet()),
                                  ),
                                if (_canPinMessages)
                                  IconButton(
                                    tooltip: 'Открепить',
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    onPressed: () =>
                                        _togglePinMessage(_pinnedMessage!),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              // Connection status lives in the AppBar subtitle (Telegram-style).
              // No sticky "polling" strip — it made the chat feel broken.
              Expanded(
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    _loadError != null && _messages.isEmpty
                        ? AppEmptyState(
                            icon: Icons.cloud_off_outlined,
                            title: 'Сообщения не загрузились',
                            subtitle: _loadError!,
                            action: FilledButton(
                              onPressed: () => _load(refresh: true),
                              child: const Text('Повторить'),
                            ),
                          )
                        : visibleMessages.isEmpty && !_loading
                            ? Center(
                                child: Text(
                                  _showOnlyFailedMessages
                                      ? _pendingMediaRetry != null
                                          ? 'Есть неотправленное медиа.\nПовтор/удаление доступны прямо у сообщения.'
                                          : 'Нет неотправленных сообщений'
                                      : 'Напишите первое сообщение',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.builder(
                                controller: _scroll,
                                cacheExtent: 900,
                                addAutomaticKeepAlives: false,
                                addRepaintBoundaries: true,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                itemCount:
                                    visibleMessages.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (_hasMore && index == 0) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Center(
                                        child: _loadingMore
                                            ? SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: scheme.primary
                                                      .withValues(alpha: 0.7),
                                                ),
                                              )
                                            : const SizedBox(height: 18),
                                      ),
                                    );
                                  }
                                  final msgIndex = index - (_hasMore ? 1 : 0);
                                  final msg = visibleMessages[msgIndex];
                                  final replyTarget = _replyTargetFor(msg);
                                  final replyQuote = replyTarget != null
                                      ? _messagePreview(replyTarget)
                                      : (msg.replyToMessageId != null
                                          ? 'Сообщение'
                                          : null);
                                  final replyAuthor = replyTarget == null
                                      ? null
                                      : (replyTarget.isMine
                                          ? 'Вы'
                                          : (replyTarget.senderName ??
                                              _senderNames[
                                                  replyTarget.senderId] ??
                                              'Сообщение'));
                                  final selected =
                                      _selectedMessageIds.contains(msg.id);
                                  final failed =
                                      _failedTextSends.containsKey(msg.id) ||
                                          _failedReadySends.containsKey(msg.id) ||
                                          _pendingMediaRetry?.tempId == msg.id;
                                  final cluster = messageClusters[msgIndex];
                                  final showDateSeparator =
                                      messageDateSeparators[msgIndex];
                                  final focusedByJump =
                                      _focusedMessageId == msg.id;
                                  final shouldAnimateIn =
                                      _animatedMessageIds.add(msg.id) &&
                                          DateTime.now()
                                                  .difference(msg.createdAt)
                                                  .inSeconds <=
                                              20;
                                  return KeyedSubtree(
                                    key: _messageItemKey(msg.id),
                                    child: RepaintBoundary(
                                      child: TweenAnimationBuilder<double>(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        curve: Curves.easeOutCubic,
                                        tween: Tween<double>(
                                          begin: shouldAnimateIn ? 0.985 : 1,
                                          end: 1,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (showDateSeparator)
                                              _chatDateSeparator(msg.createdAt),
                                            if (_unreadDividerBeforeId ==
                                                msg.id)
                                              _unreadMessagesSeparator(),
                                            AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 140),
                                              curve: Curves.easeOutCubic,
                                              decoration: BoxDecoration(
                                                color: selected
                                                    ? scheme.primary.withValues(
                                                        alpha: 0.12,
                                                      )
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 1,
                                              ),
                                              child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                if (_selectionMode)
                                                  _selectionIndicator(
                                                      selected, scheme),
                                                if (!isSaved && !msg.isMine)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      right: 4,
                                                      bottom: 1,
                                                    ),
                                                    child: cluster.ends
                                                        ? _incomingMessageAvatar(
                                                            msg,
                                                          )
                                                        : const SizedBox(
                                                            width: 26,
                                                          ),
                                                  ),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: msg
                                                            .isMine
                                                        ? CrossAxisAlignment.end
                                                        : CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Align(
                                                        alignment: msg.isMine
                                                            ? Alignment
                                                                .centerRight
                                                            : Alignment
                                                                .centerLeft,
                                                        child: Builder(
                                                          builder:
                                                              (bubbleContext) =>
                                                                  GestureDetector(
                                                            behavior:
                                                                HitTestBehavior
                                                                    .opaque,
                                                            onTap:
                                                                _selectionMode
                                                                    ? () =>
                                                                        _toggleMessageSelection(
                                                                          msg.id,
                                                                        )
                                                                    : (failed
                                                                        ? () {
                                                                            if (_failedTextSends.containsKey(msg.id)) {
                                                                              unawaited(_retryFailedText(msg.id));
                                                                            } else if (_failedReadySends.containsKey(msg.id)) {
                                                                              unawaited(_retryFailedReady(msg.id));
                                                                            } else if (_pendingMediaRetry?.tempId == msg.id) {
                                                                              unawaited(_retryPendingMedia());
                                                                            }
                                                                          }
                                                                        : null),
                                                            onDoubleTap:
                                                                _selectionMode
                                                                    ? null
                                                                    : () =>
                                                                        _toggleReaction(
                                                                          msg,
                                                                          '👍',
                                                                        ),
                                                            onHorizontalDragUpdate:
                                                                _selectionMode
                                                                    ? null
                                                                    : (details) {
                                                                        final next = (_replySwipeDx +
                                                                                details
                                                                                    .delta
                                                                                    .dx)
                                                                            .clamp(
                                                                                0.0,
                                                                                72.0);
                                                                        if (_replySwipeMsgId !=
                                                                                msg.id ||
                                                                            (next - _replySwipeDx)
                                                                                    .abs() >
                                                                                0.5) {
                                                                          setState(
                                                                            () {
                                                                              _replySwipeMsgId =
                                                                                  msg.id;
                                                                              _replySwipeDx =
                                                                                  next;
                                                                            },
                                                                          );
                                                                        }
                                                                      },
                                                            onHorizontalDragEnd:
                                                                _selectionMode
                                                                    ? null
                                                                    : (details) {
                                                                        final v =
                                                                            details.primaryVelocity;
                                                                        final shouldReply =
                                                                            _replySwipeDx >
                                                                                    48 ||
                                                                                (v != null &&
                                                                                    v >
                                                                                        280);
                                                                        setState(
                                                                          () {
                                                                            _replySwipeMsgId =
                                                                                null;
                                                                            _replySwipeDx =
                                                                                0;
                                                                            if (shouldReply) {
                                                                              _replyTo =
                                                                                  msg;
                                                                              _editingMessage =
                                                                                  null;
                                                                            }
                                                                          },
                                                                        );
                                                                        if (shouldReply) {
                                                                          _inputFocusNode
                                                                              .requestFocus();
                                                                        }
                                                                      },
                                                            onHorizontalDragCancel:
                                                                _selectionMode
                                                                    ? null
                                                                    : () {
                                                                        if (_replySwipeMsgId ==
                                                                            null) {
                                                                          return;
                                                                        }
                                                                        setState(
                                                                          () {
                                                                            _replySwipeMsgId =
                                                                                null;
                                                                            _replySwipeDx =
                                                                                0;
                                                                          },
                                                                        );
                                                                      },
                                                            onLongPress:
                                                                _selectionMode
                                                                    ? null
                                                                    : () {
                                                                        final box =
                                                                            bubbleContext.findRenderObject()
                                                                                as RenderBox?;
                                                                        if (box !=
                                                                                null &&
                                                                            box.hasSize) {
                                                                          unawaited(
                                                                            _showMessageActionOverlay(
                                                                              msg,
                                                                              box,
                                                                            ),
                                                                          );
                                                                        }
                                                                      },
                                                            child: Transform
                                                                .translate(
                                                              offset: Offset(
                                                                _replySwipeMsgId ==
                                                                        msg.id
                                                                    ? _replySwipeDx
                                                                    : 0,
                                                                0,
                                                              ),
                                                              child: Stack(
                                                                clipBehavior:
                                                                    Clip.none,
                                                                children: [
                                                                  if (_replySwipeMsgId ==
                                                                          msg
                                                                              .id &&
                                                                      _replySwipeDx >
                                                                          8)
                                                                    Positioned(
                                                                      left: msg
                                                                              .isMine
                                                                          ? null
                                                                          : -28,
                                                                      right: msg
                                                                              .isMine
                                                                          ? -28
                                                                          : null,
                                                                      top: 0,
                                                                      bottom: 0,
                                                                      child:
                                                                          Opacity(
                                                                        opacity:
                                                                            (_replySwipeDx /
                                                                                    56)
                                                                                .clamp(0.0, 1.0),
                                                                        child:
                                                                            Icon(
                                                                          Icons
                                                                              .reply_rounded,
                                                                          size:
                                                                              20,
                                                                          color:
                                                                              scheme.primary,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  Opacity(
                                                                    opacity:
                                                                        failed
                                                                            ? 0.55
                                                                            : 1,
                                                                    child:
                                                                        _messageBubbleWidget(
                                                                msg: msg,
                                                                scheme: scheme,
                                                                searching:
                                                                    searching,
                                                                isActiveSearchMatch:
                                                                    activeSearchMatchId ==
                                                                        msg.id,
                                                                isGroup:
                                                                    isGroup,
                                                                cluster:
                                                                    cluster,
                                                                replyQuote:
                                                                    replyQuote,
                                                                replyAuthor:
                                                                    replyAuthor,
                                                                interactive:
                                                                    !_selectionMode,
                                                                wrapWithAlign:
                                                                    false,
                                                                onPollVote:
                                                                    !_selectionMode
                                                                        ? (idx) =>
                                                                            _votePoll(
                                                                              msg,
                                                                              idx,
                                                                            )
                                                                        : null,
                                                                pollVoting:
                                                                    _votingPollIds
                                                                        .contains(
                                                                            msg.id),
                                                                onPollClose: (!_selectionMode &&
                                                                        msg
                                                                            .isMine &&
                                                                        msg.type ==
                                                                            'poll' &&
                                                                        msg.poll !=
                                                                            null &&
                                                                        !msg.poll!
                                                                            .isEffectivelyClosed)
                                                                    ? () =>
                                                                        _closePoll(
                                                                            msg)
                                                                    : null,
                                                                pollClosing:
                                                                    _closingPollIds
                                                                        .contains(
                                                                            msg.id),
                                                                onShowPollVoters: (!_selectionMode &&
                                                                        msg.type ==
                                                                            'poll' &&
                                                                        msg.poll !=
                                                                            null &&
                                                                        msg.poll!
                                                                            .settings
                                                                            .showVoterNames &&
                                                                        msg.poll!
                                                                            .showResults &&
                                                                        msg.poll!
                                                                                .totalVotes >
                                                                            0)
                                                                    ? () => unawaited(
                                                                          showChatPollVotersSheet(
                                                                            context,
                                                                            conversationId:
                                                                                widget.conversationId,
                                                                            messageId:
                                                                                msg.id,
                                                                          ),
                                                                        )
                                                                    : null,
                                                                onAddPollOption: (!_selectionMode &&
                                                                        msg.type ==
                                                                            'poll' &&
                                                                        msg.poll !=
                                                                            null &&
                                                                        !msg.poll!
                                                                            .isEffectivelyClosed &&
                                                                        msg.poll!
                                                                            .settings
                                                                            .allowAddOptions &&
                                                                        msg.poll!
                                                                                .options
                                                                                .length <
                                                                            12)
                                                                    ? () => unawaited(
                                                                          _addPollOption(
                                                                            msg,
                                                                          ),
                                                                        )
                                                                    : null,
                                                                onChecklistToggle:
                                                                    !_selectionMode &&
                                                                            msg.type ==
                                                                                'checklist'
                                                                        ? (index, done) =>
                                                                            _toggleChecklist(
                                                                              msg,
                                                                              index,
                                                                              done,
                                                                            )
                                                                        : null,
                                                                checklistBusy:
                                                                    _togglingChecklistIds
                                                                        .contains(
                                                                            msg.id),
                                                                onTranscribe: (!_selectionMode &&
                                                                        (msg.type ==
                                                                                'voice' ||
                                                                            msg.type ==
                                                                                'video_note') &&
                                                                        (msg.transcription ??
                                                                                '')
                                                                            .isEmpty)
                                                                    ? () =>
                                                                        _transcribeVoice(
                                                                          msg,
                                                                        )
                                                                    : null,
                                                                transcribing:
                                                                    _transcribingIds
                                                                        .contains(
                                                                            msg.id),
                                                                onInlineButtonTap:
                                                                    !_selectionMode
                                                                        ? (button) =>
                                                                            _tapInlineButton(
                                                                              msg,
                                                                              button,
                                                                            )
                                                                        : null,
                                                                callbackLoadingData:
                                                                    _callbackInFlightKeys,
                                                                onReplyTap:
                                                                    msg.replyToMessageId !=
                                                                            null
                                                                        ? () =>
                                                                            _scrollToReplyMessage(
                                                                              msg.replyToMessageId!,
                                                                            )
                                                                        : null,
                                                              ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      if (failed &&
                                                          _failedTextSends
                                                              .containsKey(
                                                                  msg.id))
                                                        _failedSendActions(
                                                            msg.id, scheme),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            ),
                                          ],
                                        ),
                                        builder: (context, value, child) {
                                          return AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 220),
                                            curve: Curves.easeOutCubic,
                                            decoration: BoxDecoration(
                                              color: focusedByJump
                                                  ? scheme.primaryContainer
                                                      .withValues(alpha: 0.22)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 2,
                                            ),
                                            child: Opacity(
                                              opacity: value.clamp(0.0, 1.0),
                                              child: Transform.scale(
                                                scale: value,
                                                alignment: Alignment.topCenter,
                                                child: child,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                    if (_floatingDateVisible &&
                        (_floatingDateLabel?.isNotEmpty ?? false) &&
                        !_selectionMode)
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: AnimatedOpacity(
                          opacity: _floatingDateVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Center(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () =>
                                    unawaited(_pickAndJumpToDate()),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.black.withValues(alpha: 0.4)
                                        : Colors.black.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _floatingDateLabel!,
                                    style: TextStyle(
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                              .withValues(alpha: 0.92)
                                          : scheme.onSurface,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_showJumpToBottom && !_selectionMode)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            begin: 0.9,
                            end: 1,
                          ),
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutBack,
                          builder: (context, value, child) => Transform.scale(
                            scale: value,
                            child: child,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Material(
                                elevation: 2,
                                shape: const CircleBorder(),
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFF2B3A4A)
                                    : scheme.surface,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _onJumpFabTap,
                                  child: SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: Icon(
                                      _hasMentionJumpTargets ||
                                              (_jumpFabTargetsUnread &&
                                                  _conversation
                                                          .unreadMentionsCount >
                                                      0)
                                          ? Icons.alternate_email_rounded
                                          : (_hasReactionJumpTargets ||
                                                  _conversation
                                                          .unreadReactionsCount >
                                                      0
                                              ? Icons.favorite_rounded
                                              : (_jumpFabTargetsUnread
                                                  ? Icons
                                                      .keyboard_double_arrow_down_rounded
                                                  : Icons
                                                      .keyboard_arrow_down_rounded)),
                                      size: 28,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                              if (_newMessagesBelow > 0 ||
                                  (_jumpFabTargetsUnread &&
                                      _conversation.unreadCount > 0) ||
                                  _hasMentionJumpTargets ||
                                  _hasReactionJumpTargets ||
                                  _conversation.unreadReactionsCount > 0)
                                Positioned(
                                  top: -6,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: TelegramUnreadBadge(
                                      count: _hasMentionJumpTargets
                                          ? _remainingMentionJumps
                                          : (_hasReactionJumpTargets
                                              ? _remainingReactionJumps
                                              : (_jumpFabTargetsUnread
                                                  ? math.max(
                                                      _conversation.unreadCount,
                                                      _newMessagesBelow,
                                                    )
                                                  : _newMessagesBelow)),
                                      hasMention: _hasMentionJumpTargets ||
                                          (_jumpFabTargetsUnread &&
                                              _conversation
                                                      .unreadMentionsCount >
                                                  0),
                                      hasReaction: !_hasMentionJumpTargets &&
                                          (_hasReactionJumpTargets ||
                                              _conversation
                                                      .unreadReactionsCount >
                                                  0),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_selectionMode)
                ChatMessageSelectionToolbar(
                  enabled: _selectedMessageIds.isNotEmpty,
                  canReply: _selectedMessageIds.length == 1,
                  onReply: _replySelectedMessage,
                  onDelete: _deleteSelectedMessages,
                  onCopy: _copySelectedMessages,
                  onShare: _shareSelectedMessages,
                  onForward: _forwardSelectedMessages,
                  onSaveToFavorites: _conversation.isSaved
                      ? null
                      : _saveSelectedMessagesToFavorites,
                )
              else
                KeyedSubtree(
                  key: _composerPanelKey,
                  child: AnimatedSize(
                    duration: _uiAnimDuration,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_replyKeyboard != null &&
                            !_replyKeyboard!.isEmpty)
                          _buildReplyKeyboardStrip(scheme),
                        if ((_conversation.peer?.paidMessageStars ?? 0) > 0 &&
                            !_conversation.isGroup &&
                            !_conversation.isSaved)
                          _compactComposerStrip(
                            icon: Icons.stars_rounded,
                            label:
                                'Сообщения стоят ${_conversation.peer!.paidMessageStars} ★',
                          ),
                        if (_isAutoRetryActive && !_sending)
                          _compactComposerStrip(
                            icon: _autoRetryReasonIcon,
                            label: _autoRetryPendingCount > 1
                                ? 'Повтор $_autoRetryPendingCount сообщ. через ${_formatSlowModeCountdown(_autoRetryRemainingSeconds)}'
                                : 'Повтор через ${_formatSlowModeCountdown(_autoRetryRemainingSeconds)}',
                            actionLabel: 'Откл.',
                            onAction: () => unawaited(
                              _toggleAutoRetryOnLimitsInThread(false),
                            ),
                          ),
                        if (!_autoRetryOnLimitsEnabled &&
                            _hasFailedPendingItems &&
                            !_sending)
                          _compactComposerStrip(
                            icon: Icons.error_outline_rounded,
                            label: _retryAllBulkBusy
                                ? 'Повтор… ${retryBulkProgressLabel ?? ''}'
                                : 'Не отправлено · ${_failedTextSends.length + (_pendingMediaRetry != null ? 1 : 0)}',
                            actionLabel: _retryAllBulkBusy
                                ? 'Стоп'
                                : 'Повторить',
                            onAction: _retryAllBulkBusy
                                ? _cancelRetryAllBulk
                                : (_sending
                                    ? null
                                    : _retryAllFailedPendingWithGuard),
                            secondaryActionLabel: _retryAllBulkBusy
                                ? null
                                : 'Очистить',
                            onSecondaryAction: (_sending || _retryAllBulkBusy)
                                ? null
                                : _clearAllFailedPending,
                          ),
                        if (_uploadProgress != null)
                          _uploadTickerBar(scheme),
                        if (_pendingMediaRetry != null &&
                            !_pendingMediaByTempId
                                .containsKey(_pendingMediaRetry!.tempId))
                          _pendingMediaRetryBanner(scheme),
                        _animatedVisibility(
                          visible: _composerLinkPreviewUrl != null &&
                              _editingMessage == null,
                          keyName: 'composer-link-preview',
                          child: _composerLinkPreviewUrl == null
                              ? const SizedBox.shrink()
                              : Material(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? const Color(0xFF1A2632)
                                      : scheme.surface,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(10, 4, 2, 4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: ChatLinkPreview(
                                            url: _composerLinkPreviewUrl!,
                                            foregroundColor: scheme.onSurface,
                                            accentColor: scheme.primary,
                                            backgroundColor: scheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.55),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Скрыть превью',
                                          icon: const Icon(Icons.close, size: 18),
                                          onPressed: () {
                                            setState(() {
                                              _composerLinkPreviewDismissedUrl =
                                                  _composerLinkPreviewUrl;
                                              _composerLinkPreviewUrl = null;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                        _animatedVisibility(
                          visible: _editingMessage != null,
                          keyName: 'edit-banner',
                          child: _editingMessage == null
                              ? const SizedBox.shrink()
                              : _telegramReplyStrip(
                                  author: _editingMessage!.type == 'text'
                                      ? 'Редактирование'
                                      : 'Подпись',
                                  preview: _editingMessage!.content.trim().isEmpty
                                      ? (_editingMessage!.type == 'image'
                                          ? 'Фото'
                                          : _editingMessage!.type == 'video'
                                              ? 'Видео'
                                              : 'Файл')
                                      : _editingMessage!.content,
                                  onClose: _cancelEdit,
                                ),
                        ),
                        _animatedVisibility(
                          visible: _privateReply != null,
                          keyName: 'private-reply-banner',
                          child: _privateReply == null
                              ? const SizedBox.shrink()
                              : _telegramReplyStrip(
                                  author: _privateReply!.stripAuthor,
                                  preview: _privateReply!.preview,
                                  onTap: () {
                                    final q = _privateReply;
                                    if (q == null) return;
                                    unawaited(
                                      _openForwardedOriginal(
                                        conversationId: q.sourceConversationId,
                                        messageId: q.sourceMessageId,
                                      ),
                                    );
                                  },
                                  onClose: () {
                                    setState(() => _privateReply = null);
                                  },
                                ),
                        ),
                        _animatedVisibility(
                          visible: _replyTo != null && _privateReply == null,
                          keyName: 'reply-banner',
                          child: _replyTo == null
                              ? const SizedBox.shrink()
                              : _telegramReplyStrip(
                                  author: _replyTo!.isMine
                                      ? 'Вы'
                                      : (_replyTo!.senderName ??
                                          _senderNames[_replyTo!.senderId] ??
                                          _conversation.displayTitle),
                                  preview: _messagePreview(_replyTo!),
                                  onClose: () {
                                    setState(() => _replyTo = null);
                                    _scheduleDraftSave();
                                  },
                                ),
                        ),
                        _animatedVisibility(
                          visible: !canSendInGroup,
                          keyName: 'group-readonly-banner',
                          child: _composerInfoBanner(
                            backgroundColor: scheme.secondaryContainer
                                .withValues(alpha: 0.45),
                            foregroundColor: scheme.onSecondaryContainer,
                            icon: Icons.lock_outline,
                            title: isRestrictedByModeration
                                ? 'Отправка сообщений ограничена модератором'
                                : 'Только админы могут отправлять сообщения',
                          ),
                        ),
                        _animatedVisibility(
                          visible: peerBlockedByMe,
                          keyName: 'peer-blocked-banner',
                          child: _composerInfoBanner(
                            backgroundColor: scheme.errorContainer
                                .withValues(alpha: 0.55),
                            foregroundColor: scheme.onErrorContainer,
                            icon: Icons.block_outlined,
                            title: 'Пользователь заблокирован',
                            subtitle: 'Вы не можете писать друг другу',
                            trailing: TextButton(
                              onPressed: () => unawaited(_unblockPeer()),
                              child: const Text('Разблокировать'),
                            ),
                          ),
                        ),
                        if (!canSendNow && canCompose)
                          _compactComposerStrip(
                            icon: activeCooldownIcon,
                            label:
                                '$activeCooldownLabel · ${_formatSlowModeCountdown(activeCooldownSeconds)}',
                            actionLabel: 'Инфо',
                            onAction: () => _showPostingLimitsInfo(
                              floodCooldownActive: floodCooldownActive,
                              activeCooldownSeconds: activeCooldownSeconds,
                            ),
                          )
                        else if (showPostingLimitsHint)
                          _compactComposerStrip(
                            icon: activeCooldownIcon,
                            label: postingLimitsHint,
                            actionLabel: 'Инфо',
                            onAction: () => _showPostingLimitsInfo(
                              floodCooldownActive: floodCooldownActive,
                              activeCooldownSeconds: activeCooldownSeconds,
                            ),
                          ),
                        if (_stickerPanelOpen && !_recording)
                          ChatInlineStickerPanel(
                            onOpenFull: () =>
                                unawaited(_showFullStickerSheet()),
                            onInsertCustomEmoji: (id) {
                              if (!_hasFlexFeature('custom_emoji')) {
                                unawaited(showCreatorUpsell(context));
                                return;
                              }
                              _insertComposerToken(customEmojiToken(id));
                            },
                            onPick: (url, {emoji}) {
                              setState(() => _stickerPanelOpen = false);
                              unawaited(
                                _sendStickerByUrl(url, emoji: emoji),
                              );
                            },
                          ),
                        if (_showFormatBar && !_recording)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                            child: Row(
                              children: [
                                _ComposerFormatChip(
                                  label: 'B',
                                  tooltip: 'Жирный',
                                  onTap: () => _wrapComposerMarkup('*', '*'),
                                ),
                                const SizedBox(width: 6),
                                _ComposerFormatChip(
                                  label: 'I',
                                  tooltip: 'Курсив',
                                  italic: true,
                                  onTap: () => _wrapComposerMarkup('_', '_'),
                                ),
                                const SizedBox(width: 6),
                                _ComposerFormatChip(
                                  label: '</>',
                                  tooltip: 'Код',
                                  onTap: () => _wrapComposerMarkup('`', '`'),
                                ),
                                const SizedBox(width: 6),
                                _ComposerFormatChip(
                                  label: 'S',
                                  tooltip: 'Спойлер',
                                  onTap: () =>
                                      _wrapComposerMarkup('||', '||'),
                                ),
                              ],
                            ),
                          ),
                        if (canSendAnonymously(
                              isGroup: _conversation.isGroup,
                              amIGroupAdmin: _conversation.amIGroupAdmin,
                            ) &&
                            !_recording)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FilterChip(
                                avatar: Icon(
                                  _sendAnonymously
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  _sendAnonymously
                                      ? 'Анонимно как группа'
                                      : 'От своего имени',
                                ),
                                selected: _sendAnonymously,
                                onSelected: (v) =>
                                    setState(() => _sendAnonymously = v),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        if (!_recording &&
                            (_quickReplies.isNotEmpty ||
                                _hasFlexFeature('quick_replies')))
                          SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                              children: [
                                for (final reply in _quickReplies)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: InputChip(
                                      label: HighlightedText(
                                        text: reply.title.isNotEmpty
                                            ? reply.title
                                            : reply.text,
                                        style: Theme.of(context)
                                                .textTheme
                                                .labelLarge ??
                                            const TextStyle(fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onPressed: () =>
                                          unawaited(_insertQuickReply(reply)),
                                      onDeleted: () =>
                                          unawaited(_deleteQuickReply(reply)),
                                    ),
                                  ),
                                ActionChip(
                                  avatar: Icon(
                                    _hasFlexFeature('quick_replies')
                                        ? Icons.add
                                        : Icons.lock_outline,
                                    size: 16,
                                  ),
                                  label: const Text('Ответ'),
                                  onPressed: () =>
                                      unawaited(_createQuickReply()),
                                ),
                              ],
                            ),
                          ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (!_recording)
                                  IconButton(
                                    onPressed: !canSendNow
                                        ? null
                                        : _showAttachMenu,
                                    icon:
                                        const Icon(Icons.attach_file_outlined),
                                    tooltip: 'Вложение',
                                    color: scheme.onSurfaceVariant,
                                    iconSize: _composerIconSize,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: _composerButtonSide,
                                      height: _composerButtonSide,
                                    ),
                                  ),
                                if (!_recording)
                                  IconButton(
                                    onPressed: !canCompose
                                        ? null
                                        : () => setState(
                                              () => _showFormatBar =
                                                  !_showFormatBar,
                                            ),
                                    icon: Icon(
                                      _showFormatBar
                                          ? Icons.text_format
                                          : Icons.text_format_outlined,
                                    ),
                                    tooltip: 'Форматирование',
                                    color: _showFormatBar
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                    iconSize: _composerIconSize,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: _composerButtonSide,
                                      height: _composerButtonSide,
                                    ),
                                  ),
                                if (!_recording && _hasBotCommands)
                                  IconButton(
                                    onPressed:
                                        !canSendNow ? null : _openBotCommandsMenu,
                                    icon: const Icon(Icons.flash_on_outlined),
                                    tooltip: 'Команды бота',
                                    color: scheme.onSurfaceVariant,
                                    iconSize: _composerIconSize,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: _composerButtonSide,
                                      height: _composerButtonSide,
                                    ),
                                  ),
                                Expanded(
                                  child: _recording
                                      ? Container(
                                          height: 44,
                                          alignment: Alignment.centerLeft,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _recordCancelled &&
                                                    !_voiceLocked
                                                ? scheme.errorContainer
                                                    .withValues(alpha: 0.55)
                                                : (Theme.of(context)
                                                            .brightness ==
                                                        Brightness.dark
                                                    ? const Color(0xCC1A2632)
                                                    : scheme
                                                        .surfaceContainerLow),
                                            borderRadius:
                                                BorderRadius.circular(22),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                _voiceLocked
                                                    ? Icons.lock_rounded
                                                    : Icons.mic_rounded,
                                                size: 18,
                                                color: _recordCancelled &&
                                                        !_voiceLocked
                                                    ? scheme.error
                                                    : scheme.primary,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                _formatRecordDuration(
                                                  _recordDuration,
                                                ),
                                                style: TextStyle(
                                                  color: _recordCancelled &&
                                                          !_voiceLocked
                                                      ? scheme.error
                                                      : scheme.onSurface,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: ChatVoiceWaveform(
                                                  levels: List<double>.from(
                                                    _waveLevels,
                                                  ),
                                                  color: scheme
                                                      .onSurfaceVariant,
                                                  activeColor: _recordCancelled &&
                                                          !_voiceLocked
                                                      ? scheme.error
                                                      : scheme.primary,
                                                  barCount: 28,
                                                  height: 22,
                                                ),
                                              ),
                                              if (_voiceLocked) ...[
                                                IconButton(
                                                  tooltip: 'Удалить',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints
                                                          .tightFor(
                                                    width: 34,
                                                    height: 34,
                                                  ),
                                                  onPressed: () => unawaited(
                                                    _cancelRecording(),
                                                  ),
                                                  icon: Icon(
                                                    Icons.delete_outline,
                                                    color: scheme.error,
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Отправить',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints
                                                          .tightFor(
                                                    width: 34,
                                                    height: 34,
                                                  ),
                                                  onPressed: () => unawaited(
                                                    _stopAndSendVoice(),
                                                  ),
                                                  icon: Icon(
                                                    Icons.send_rounded,
                                                    color: scheme.primary,
                                                  ),
                                                ),
                                              ] else ...[
                                                const SizedBox(width: 8),
                                                Text(
                                                  _recordCancelled
                                                      ? 'Отмена'
                                                      : '← отмена · ↑ lock',
                                                  style: TextStyle(
                                                    color: _recordCancelled
                                                        ? scheme.error
                                                        : scheme
                                                            .onSurfaceVariant,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        )
                                      : DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                        .brightness ==
                                                    Brightness.dark
                                                ? const Color(0xCC1A2632)
                                                : scheme.surfaceContainerLow,
                                            borderRadius:
                                                BorderRadius.circular(22),
                                          ),
                                          child: TextField(
                                            controller: _controller,
                                            focusNode: _inputFocusNode,
                                            enabled: canCompose,
                                            minLines: 1,
                                            maxLines: 5,
                                            textInputAction:
                                                TextInputAction.newline,
                                            keyboardType:
                                                TextInputType.multiline,
                                            scrollPadding:
                                                const EdgeInsets.only(
                                              bottom: 96,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: _composerHintText(
                                                canCompose: canCompose,
                                                peerBlockedByMe: peerBlockedByMe,
                                                isRestrictedByModeration:
                                                    isRestrictedByModeration,
                                                activeCooldownSeconds:
                                                    activeCooldownSeconds,
                                              ),
                                              filled: true,
                                              fillColor: Colors.transparent,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(22),
                                                borderSide: BorderSide.none,
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 10,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                                if (!_hasText && !_recording)
                                  IconButton(
                                    onPressed: !canSendNow
                                        ? null
                                        : () => unawaited(
                                              _showStickerPicker(),
                                            ),
                                    icon: Icon(
                                      _stickerPanelOpen
                                          ? Icons.keyboard_outlined
                                          : Icons.emoji_emotions_outlined,
                                    ),
                                    tooltip: _stickerPanelOpen
                                        ? 'Клавиатура'
                                        : 'Стикеры',
                                    color: _stickerPanelOpen
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                    iconSize: _composerIconSize,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: _composerButtonSide,
                                      height: _composerButtonSide,
                                    ),
                                  ),
                                const SizedBox(width: 2),
                                AnimatedSwitcher(
                                  duration: _uiAnimDuration,
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.94,
                                        end: 1,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                                  child: ((_hasText ||
                                              _editingMessage != null) &&
                                          !_recording)
                                      ? GestureDetector(
                                          key: const ValueKey('send-btn'),
                                          onLongPress:
                                              _editingMessage == null &&
                                                      canSendNow
                                                  ? _scheduleCurrentTextMessage
                                                  : null,
                                          child: IconButton.filled(
                                            style: IconButton.styleFrom(
                                              backgroundColor: _telegramAccent,
                                              foregroundColor: Colors.white,
                                              shape: const CircleBorder(),
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(
                                                _composerButtonSide,
                                                _composerButtonSide,
                                              ),
                                            ),
                                            onPressed:
                                                (_recording || !canSendNow)
                                                    ? null
                                                    : _sendText,
                                            icon: activeCooldownSeconds > 0
                                                    ? AnimatedScale(
                                                        duration:
                                                            const Duration(
                                                          milliseconds: 180,
                                                        ),
                                                        scale:
                                                            slowModePulseScale,
                                                        child: SizedBox(
                                                          width: 26,
                                                          height: 26,
                                                          child: Stack(
                                                            alignment: Alignment
                                                                .center,
                                                            children: [
                                                              SizedBox(
                                                                width: 24,
                                                                height: 24,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      isSlowModeUnlockSoon
                                                                          ? 2.4
                                                                          : 2,
                                                                  value:
                                                                      activeCooldownProgress,
                                                                  backgroundColor: scheme
                                                                      .onPrimary
                                                                      .withValues(
                                                                    alpha: 0.28,
                                                                  ),
                                                                  color:
                                                                      isSlowModeUnlockSoon
                                                                          ? scheme
                                                                              .onPrimary
                                                                              .withValues(
                                                                              alpha: 0.98,
                                                                            )
                                                                          : scheme
                                                                              .onPrimary,
                                                                ),
                                                              ),
                                                              AnimatedSwitcher(
                                                                duration:
                                                                    const Duration(
                                                                  milliseconds:
                                                                      180,
                                                                ),
                                                                transitionBuilder: (
                                                                  child,
                                                                  animation,
                                                                ) =>
                                                                    FadeTransition(
                                                                  opacity:
                                                                      animation,
                                                                  child:
                                                                      ScaleTransition(
                                                                    scale: Tween<
                                                                        double>(
                                                                      begin:
                                                                          0.92,
                                                                      end: 1,
                                                                    ).animate(
                                                                      animation,
                                                                    ),
                                                                    child:
                                                                        child,
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  _formatSlowModeCompact(
                                                                    activeCooldownSeconds,
                                                                  ),
                                                                  key: ValueKey(
                                                                    activeCooldownSeconds,
                                                                  ),
                                                                  style:
                                                                      TextStyle(
                                                                    color: scheme
                                                                        .onPrimary,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    fontSize: 9,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      )
                                                    : Icon(
                                                        _editingMessage != null
                                                            ? Icons
                                                                .check_rounded
                                                            : Icons
                                                                .send_rounded,
                                                        size: _composerIconSize,
                                                      ),
                                          ),
                                        )
                                      : Row(
                                          key: ValueKey(
                                            _videoNoteComposerMode
                                                ? 'video-note-btn'
                                                : 'mic-btn',
                                          ),
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (!_recording)
                                              IconButton(
                                                tooltip: _videoNoteComposerMode
                                                    ? 'Голосовое'
                                                    : 'Кружок',
                                                onPressed: !canSendNow
                                                    ? null
                                                    : () async {
                                                        if (!_videoNoteComposerMode &&
                                                            !_hasFlexFeature(
                                                              'video_notes',
                                                            )) {
                                                          await showCreatorUpsell(
                                                            context,
                                                          );
                                                          return;
                                                        }
                                                        setState(() {
                                                          _videoNoteComposerMode =
                                                              !_videoNoteComposerMode;
                                                        });
                                                      },
                                                icon: Icon(
                                                  _videoNoteComposerMode
                                                      ? Icons.mic_none_rounded
                                                      : (_hasFlexFeature(
                                                              'video_notes')
                                                          ? Icons
                                                              .videocam_outlined
                                                          : Icons.lock_outline),
                                                ),
                                                color: scheme.onSurfaceVariant,
                                                iconSize: _composerIconSize,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints
                                                        .tightFor(
                                                  width: 32,
                                                  height: _composerButtonSide,
                                                ),
                                              ),
                                            ChatVoiceMicButton(
                                              enabled: canSendNow,
                                              recording: _recording,
                                              locked: _voiceLocked,
                                              tapToRecord:
                                                  _videoNoteComposerMode,
                                              idleIcon: _videoNoteComposerMode
                                                  ? Icons.videocam_rounded
                                                  : Icons.mic_none_rounded,
                                              activeIcon:
                                                  _videoNoteComposerMode
                                                      ? Icons.videocam_rounded
                                                      : Icons.mic_rounded,
                                              onHoldStart: _onHoldStart,
                                              onHoldEnd: _onHoldEnd,
                                              onHoldDrag: _onHoldDrag,
                                              onTap: _videoNoteComposerMode
                                                  ? () => unawaited(
                                                        _recordAndSendVideoNote(),
                                                      )
                                                  : null,
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          ),
        ),
            if (_activeEffectId != null)
              Positioned.fill(
                child: MessageEffectOverlay(
                  key: ValueKey('fx_$_activeEffectToken'),
                  effectId: _activeEffectId!,
                  onCompleted: () {
                    if (!mounted) return;
                    setState(() => _activeEffectId = null);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PendingMediaKind { image, video, file, voice }

class _MentionCandidate {
  const _MentionCandidate({
    required this.username,
    required this.title,
    this.subtitle,
    this.avatarUrl,
    this.isBot = false,
    this.isSlashCommand = false,
  });

  final String username;
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final bool isBot;
  final bool isSlashCommand;
}

class _CancelledPendingMediaException implements Exception {}

class _PendingMediaSend {
  _PendingMediaSend({
    required this.tempId,
    required this.kind,
    required this.file,
    required this.clientMessageId,
    this.fileName,
    this.replyToMessageId,
    this.caption = '',
    this.voiceDurationSec,
    this.totalBytes,
    this.previewBytes,
    this.payloadBytes,
    this.silent = false,
    this.mediaGroupId,
    this.hasSpoiler = false,
    this.isPaid = false,
    this.priceStars = 0,
    this.topicId,
    this.anonymous = false,
  });

  final int tempId;
  final _PendingMediaKind kind;
  final XFile file;
  final String clientMessageId;
  final String? fileName;
  final int? replyToMessageId;
  final String caption;
  final int? voiceDurationSec;
  final int? totalBytes;
  final Uint8List? previewBytes;
  /// Full bytes for Hive outbox / reload retry (web-safe).
  Uint8List? payloadBytes;
  final bool silent;
  final String? mediaGroupId;
  final bool hasSpoiler;
  final bool isPaid;
  final int priceStars;
  final int? topicId;
  final bool anonymous;
  String? uploadedMediaUrl;
  int attempts = 0;
  int? lastRetryAfterSeconds;
  DateTime? lastLimitedAt;
}

class _PendingTextSend {
  _PendingTextSend({
    required this.text,
    required this.clientMessageId,
    required this.tempId,
    this.replyToMessageId,
    this.silent = false,
    this.disableWebpagePreview = false,
    this.effectId,
    this.topicId,
    this.anonymous = false,
  });

  final String text;
  final String clientMessageId;
  final int tempId;
  final int? replyToMessageId;
  final bool silent;
  final bool disableWebpagePreview;
  final String? effectId;
  final int? topicId;
  final bool anonymous;
  int attempts = 0;
  int? lastRetryAfterSeconds;
  DateTime? lastLimitedAt;
}

class _ManualRetryTask {
  _ManualRetryTask({
    required this.remainingSeconds,
    required this.isMedia,
    required this.action,
  });

  final int? remainingSeconds;
  final bool isMedia;
  final Future<void> Function() action;
}

class _MessageCluster {
  const _MessageCluster({
    required this.starts,
    required this.ends,
  });

  const _MessageCluster.single()
      : starts = true,
        ends = true;

  final bool starts;
  final bool ends;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.scheme,
    this.isPending = false,
    this.isFailed = false,
    this.autoDeleteSeconds = 0,
    this.highlightQuery,
    this.isActiveSearchMatch = false,
    this.replyQuote,
    this.replyAuthor,
    this.onReplyTap,
    this.showSenderName = false,
    this.senderLabel,
    this.onSenderTap,
    this.isConversationPinned = false,
    this.onImageTap,
    this.onVideoTap,
    this.onFileTap,
    this.onReactionTap,
    this.onReactionLongPress,
    this.wrapWithAlign = true,
    this.cluster = const _MessageCluster.single(),
    this.onPollVote,
    this.pollVoting = false,
    this.onPollClose,
    this.pollClosing = false,
    this.onShowPollVoters,
    this.onAddPollOption,
    this.onChecklistToggle,
    this.checklistBusy = false,
    this.onTranscribe,
    this.transcribing = false,
    this.onInlineButtonTap,
    this.callbackLoadingData = const <String>{},
    this.onOpenContactUser,
    this.onMessageContactUser,
    this.onSaveContactToPhone,
    this.onAddHanContact,
    this.onMentionTap,
    this.mentionLabels,
    this.onForwardFromTap,
    this.onVoiceCompleted,
    this.onEditedTap,
    this.onReadTimeTap,
    this.onReadersTap,
    this.onCallTap,
    this.outgoingBubbleColor,
    this.onUnlockPaidMedia,
    this.unlockingPaidMedia = false,
    this.onPaidReaction,
    this.onConvertGift,
    this.onKeepGift,
    this.onRefundGift,
    this.giftActionBusy = false,
    this.spoilerRevealed = false,
    this.onRevealSpoiler,
    this.onStopLiveLocation,
    this.translation,
  });

  final ChatMessage message;
  final String? translation;
  final ColorScheme scheme;
  final Color? outgoingBubbleColor;
  final VoidCallback? onUnlockPaidMedia;
  final bool unlockingPaidMedia;
  final VoidCallback? onPaidReaction;
  final VoidCallback? onConvertGift;
  final VoidCallback? onKeepGift;
  final VoidCallback? onRefundGift;
  final bool giftActionBusy;
  final bool spoilerRevealed;
  final VoidCallback? onRevealSpoiler;
  final VoidCallback? onStopLiveLocation;
  /// Still sending to server (Telegram clock icon).
  final bool isPending;
  /// Send failed (tap to retry).
  final bool isFailed;
  /// Conversation TTL; when > 0 show remaining countdown in meta.
  final int autoDeleteSeconds;
  final String? highlightQuery;
  final bool isActiveSearchMatch;
  final String? replyQuote;
  final String? replyAuthor;
  final VoidCallback? onReplyTap;
  final bool showSenderName;
  final String? senderLabel;
  final VoidCallback? onSenderTap;
  final bool isConversationPinned;
  final VoidCallback? onImageTap;
  final VoidCallback? onVideoTap;
  final VoidCallback? onFileTap;
  final ValueChanged<String>? onReactionTap;
  final ValueChanged<String>? onReactionLongPress;
  final bool wrapWithAlign;
  final _MessageCluster cluster;
  final ValueChanged<int>? onPollVote;
  final bool pollVoting;
  final VoidCallback? onPollClose;
  final bool pollClosing;
  final VoidCallback? onShowPollVoters;
  final VoidCallback? onAddPollOption;
  final void Function(int index, bool done)? onChecklistToggle;
  final bool checklistBusy;
  final VoidCallback? onTranscribe;
  final bool transcribing;
  final ValueChanged<ChatInlineKeyboardButton>? onInlineButtonTap;
  final Set<String> callbackLoadingData;
  final ValueChanged<int>? onOpenContactUser;
  final ValueChanged<int>? onMessageContactUser;
  final ValueChanged<ChatContactPayload>? onSaveContactToPhone;
  final ValueChanged<int>? onAddHanContact;
  final ValueChanged<String>? onMentionTap;
  final Map<String, String>? mentionLabels;
  final VoidCallback? onForwardFromTap;
  final ValueChanged<ChatMessage>? onVoiceCompleted;
  final VoidCallback? onEditedTap;
  final VoidCallback? onReadTimeTap;
  final VoidCallback? onReadersTap;
  final VoidCallback? onCallTap;

  double _metaReserveWidth(bool mine) {
    var width = 42.0; // time
    if (message.isEdited) width += 28;
    if (isConversationPinned) width += 16;
    if (autoDeleteSeconds > 0) width += 36;
    if (mine) width += 16; // single/double check mark area
    if (mine && message.readCount > 0) width += 22;
    return width;
  }

  BorderRadius _bubbleRadius(bool mine) {
    // Telegram-like corner radii (tighter than a card).
    const large = Radius.circular(12);
    const small = Radius.circular(3);
    return BorderRadius.only(
      topLeft: !mine && !cluster.starts ? small : large,
      topRight: mine && !cluster.starts ? small : large,
      bottomLeft: !mine && !cluster.ends ? small : (mine ? large : small),
      bottomRight: mine && !cluster.ends ? small : (mine ? small : large),
    );
  }

  Widget _messageMeta({
    required Color fg,
    required bool mine,
    bool onMedia = false,
  }) {
    final timeColor = onMedia
        ? Colors.white.withValues(alpha: 0.92)
        : fg.withValues(alpha: 0.55);
    final editedColor = onMedia
        ? Colors.white.withValues(alpha: 0.75)
        : fg.withValues(alpha: 0.45);
    final IconData statusIcon;
    final Color statusColor;
    if (isFailed) {
      statusIcon = Icons.error_outline;
      statusColor = onMedia ? Colors.white : scheme.error;
    } else if (isPending) {
      // Telegram: clock while the message is still leaving the device.
      statusIcon = Icons.access_time;
      statusColor = onMedia
          ? Colors.white.withValues(alpha: 0.85)
          : fg.withValues(alpha: 0.55);
    } else if (message.isRead) {
      statusIcon = Icons.done_all;
      statusColor = onMedia
          ? Colors.white.withValues(alpha: 0.95)
          : scheme.primary;
    } else if (message.isDelivered) {
      // Telegram gray ✓✓ = delivered to peer device.
      statusIcon = Icons.done_all;
      statusColor = onMedia
          ? Colors.white.withValues(alpha: 0.78)
          : fg.withValues(alpha: 0.55);
    } else {
      statusIcon = Icons.done;
      statusColor = onMedia
          ? Colors.white.withValues(alpha: 0.7)
          : fg.withValues(alpha: 0.45);
    }

    final ttlLabel = autoDeleteSeconds > 0
        ? formatAutoDeleteRemaining(message.createdAt, autoDeleteSeconds)
        : '';
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isConversationPinned) ...[
          Icon(
            Icons.push_pin,
            size: 10.5,
            color:
                onMedia ? Colors.white.withValues(alpha: 0.9) : scheme.primary,
          ),
          const SizedBox(width: 3),
        ],
        if (ttlLabel.isNotEmpty) ...[
          Icon(
            Icons.timer_outlined,
            size: 10.5,
            color: timeColor,
          ),
          const SizedBox(width: 2),
          Text(
            ttlLabel,
            style: TextStyle(color: timeColor, fontSize: 10.5, height: 1.08),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          formatChatMessageTime(message.createdAt),
          style: TextStyle(color: timeColor, fontSize: 10.5, height: 1.08),
        ),
        if (message.isEdited) ...[
          const SizedBox(width: 3),
          GestureDetector(
            onTap: onEditedTap,
            behavior: HitTestBehavior.opaque,
            child: Text(
              'изм.',
              style: TextStyle(
                color: editedColor,
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                height: 1.08,
                decoration: onEditedTap != null
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: editedColor,
              ),
            ),
          ),
        ],
        if (mine) ...[
          const SizedBox(width: 3),
          GestureDetector(
            onTap: onReadTimeTap,
            behavior: HitTestBehavior.opaque,
            child: Icon(
              statusIcon,
              size: 12.5,
              color: statusColor,
            ),
          ),
        ],
        if (mine && message.readCount > 0) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onReadersTap,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 11,
                  color: timeColor,
                ),
                const SizedBox(width: 2),
                Text(
                  '${message.readCount}',
                  style: TextStyle(
                    color: timeColor,
                    fontSize: 10.5,
                    height: 1.08,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (!onMedia) return row;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: row,
      ),
    );
  }

  Widget _withBottomMeta({
    required Color fg,
    required bool mine,
    required Widget child,
    bool onMedia = false,
    bool inlineMeta = false,
  }) {
    final meta = _messageMeta(fg: fg, mine: mine, onMedia: onMedia);
    if (!onMedia) {
      // IntrinsicWidth keeps short texts tight (Telegram). Inline meta sits
      // on the last text line via trailingReserveWidth on HighlightedText.
      if (inlineMeta) {
        return IntrinsicWidth(
          child: Stack(
            children: [
              child,
              Positioned(
                right: 0,
                bottom: 0,
                child: meta,
              ),
            ],
          ),
        );
      }
      return IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            child,
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Align(
                alignment: Alignment.centerRight,
                child: meta,
              ),
            ),
          ],
        ),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: child,
        ),
        Positioned(
          right: 6,
          bottom: 4,
          child: meta,
        ),
      ],
    );
  }

  Color _senderNameColor() {
    // Telegram-like stable pastel palette from sender id.
    const palette = <Color>[
      Color(0xFFE17076),
      Color(0xFFFAA774),
      Color(0xFFA695E7),
      Color(0xFF7BC862),
      Color(0xFF6EC9CB),
      Color(0xFF65AADD),
      Color(0xFFEE7AAE),
    ];
    return palette[message.senderId.abs() % palette.length];
  }

  Widget _buildReactions(Color fg, Color quoteBg) {
    final chips = message.reactions
        .where((r) => r.emoji.isNotEmpty && r.count > 0)
        .toList();
    if (chips.isEmpty && onPaidReaction == null) {
      return const SizedBox.shrink();
    }
    final isDark = scheme.brightness == Brightness.dark;

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final r in chips)
          Material(
            elevation: 0.5,
            color: r.reactedByMe
                ? scheme.primary.withValues(alpha: isDark ? 0.28 : 0.16)
                : (isDark
                    ? const Color(0xFF2B3A4A)
                    : scheme.surface.withValues(alpha: 0.95)),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onReactionTap == null ? null : () => onReactionTap!(r.emoji),
              onLongPress: onReactionLongPress == null
                  ? null
                  : () => onReactionLongPress!(r.emoji),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReactionEmojiView(token: r.emoji, size: 16),
                    if (r.starsTotal > 0)
                      Text(
                        ' ${r.starsTotal}★',
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.92),
                          fontSize: 13,
                          height: 1.1,
                        ),
                      )
                    else if (r.count > 1)
                      Text(
                        ' ${r.count}',
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.92),
                          fontSize: 13,
                          height: 1.1,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (onPaidReaction != null)
          Material(
            elevation: 0.5,
            color: scheme.secondary.withValues(alpha: isDark ? 0.28 : 0.14),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onPaidReaction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Text(
                  '★+',
                  style: TextStyle(
                    color: scheme.secondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReplyQuote(Color fg, Color quoteBg) {
    if (replyQuote == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onReplyTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            decoration: BoxDecoration(
              color: quoteBg,
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(color: scheme.primary, width: 2.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyAuthor != null && replyAuthor!.isNotEmpty)
                  HighlightedText(
                    text: replyAuthor!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                HighlightedText(
                  text: replyQuote!,
                  query: highlightQuery,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineKeyboard(Color fg, Color quoteBg) {
    if (message.inlineKeyboard.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in message.inlineKeyboard)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final btn in row)
                    OutlinedButton(
                      onPressed: onInlineButtonTap == null ||
                              (!btn.isWebApp &&
                                  (btn.callbackData == null ||
                                      btn.callbackData!.trim().isEmpty) &&
                                  (btn.url == null || btn.url!.trim().isEmpty))
                          ? null
                          : () => onInlineButtonTap!(btn),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: fg.withValues(alpha: 0.25),
                        ),
                        backgroundColor: quoteBg,
                        foregroundColor: fg,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HighlightedText(
                            text: btn.text,
                            style: Theme.of(context).textTheme.labelLarge ??
                                const TextStyle(fontSize: 14),
                          ),
                          if (btn.isWebApp) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.open_in_browser_rounded,
                              size: 14,
                              color: fg.withValues(alpha: 0.7),
                            ),
                          ],
                          if (btn.callbackData != null &&
                              callbackLoadingData.contains(
                                  '${message.id}:${btn.callbackData}'))
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: fg.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = mine
        ? (outgoingBubbleColor ??
            (isDark
                ? AppColors.telegramOutgoingDark
                : AppColors.telegramOutgoingLight))
        : (isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest);
    final fg = mine && isDark ? Colors.white : scheme.onSurface;
    final quoteBg = mine
        ? scheme.primary.withValues(alpha: 0.12)
        : scheme.onSurface.withValues(alpha: 0.06);

    if (message.type == 'call') {
      final label = CallMessageLabels.preview(message.content, mine: mine);
      final chip = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onCallTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (onCallTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    CallMessageLabels.mediaOf(message.content) == 'video'
                        ? Icons.videocam_outlined
                        : Icons.call_outlined,
                    size: 16,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      if (!wrapWithAlign) return chip;
      return Align(alignment: Alignment.center, child: chip);
    }

    final isLockedPaid = message.isLockedPaidMedia;
    final isImage =
        !isLockedPaid && message.type == 'image' && message.mediaUrl != null;
    final isVideo =
        !isLockedPaid && message.type == 'video' && message.mediaUrl != null;
    final isSticker = message.type == 'sticker' && message.mediaUrl != null;
    final isVideoNote = message.type == 'video_note' && message.mediaUrl != null;
    final isMedia = isImage || isVideo || isSticker;
    final hasCaption = message.content.trim().isNotEmpty;
    final isFullBleedMedia = (isImage || isVideo) && !hasCaption;
    final bubbleRadius = _bubbleRadius(mine);
    final contentPadding = (isSticker || isVideoNote)
        ? const EdgeInsets.fromLTRB(2, 2, 2, 0)
        : (isMedia ? EdgeInsets.zero : const EdgeInsets.fromLTRB(8, 4, 8, 3));
    // Stickers / video notes / full-bleed media stay transparent.
    final isForwarded = message.isForwarded;
    final bubbleNeedsBackground = (isSticker || isVideoNote)
        ? (replyQuote != null ||
            isForwarded ||
            (showSenderName && (senderLabel?.isNotEmpty ?? false)))
        : (!isFullBleedMedia ||
            replyQuote != null ||
            isForwarded ||
            (showSenderName && (senderLabel?.isNotEmpty ?? false)));
    final hasReactions = message.reactions.isNotEmpty;
    final activeBorderColor = scheme.primary.withValues(alpha: 0.75);
    final activeShadowColor = scheme.primary.withValues(alpha: 0.28);

    Widget mainContent;
    if (isLockedPaid) {
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: PaidMediaLockBubble(
          priceStars: message.priceStars,
          loading: unlockingPaidMedia,
          onUnlock: onUnlockPaidMedia ?? () {},
        ),
      );
    } else if (message.type == 'web_app_data') {
      Map<String, dynamic>? payload;
      try {
        final decoded = jsonDecode(message.content);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } catch (_) {}
      final buttonText = payload?['button_text'] as String? ?? 'Mini App';
      final dataPreview = (payload?['data'] as String? ?? message.content).trim();
      final shortData = dataPreview.length > 120
          ? '${dataPreview.substring(0, 120)}…'
          : dataPreview;
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: Container(
          width: 240,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: quoteBg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Данные Mini App',
                style: TextStyle(color: fg, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              HighlightedText(
                text: buttonText,
                style: TextStyle(
                  color: scheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (shortData.isNotEmpty) ...[
                const SizedBox(height: 6),
                HighlightedText(
                  text: shortData,
                  style: TextStyle(color: fg.withValues(alpha: 0.85)),
                ),
              ],
            ],
          ),
        ),
      );
    } else if (message.type == 'stars_tip') {
      Map<String, dynamic>? tip;
      try {
        final decoded = jsonDecode(message.content);
        if (decoded is Map<String, dynamic>) tip = decoded;
      } catch (_) {}
      final amount = tip?['amount'] as int? ??
          (tip?['amount'] is num ? (tip!['amount'] as num).toInt() : 0);
      final note = tip?['message'] as String?;
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: Container(
          width: 220,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: quoteBg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⭐', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 6),
              Text(
                mine ? 'Вы отправили звёзды' : 'Вам отправили звёзды',
                style: TextStyle(color: fg, fontWeight: FontWeight.w800),
              ),
              Text(
                '$amount ★',
                style: TextStyle(
                  color: scheme.secondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              if (note != null && note.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                HighlightedText(
                  text: note.trim(),
                  style: TextStyle(color: fg.withValues(alpha: 0.8)),
                ),
              ],
            ],
          ),
        ),
      );
    } else if (message.type == 'gift') {
      Map<String, dynamic>? gift;
      try {
        final decoded = jsonDecode(message.content);
        if (decoded is Map<String, dynamic>) gift = decoded;
      } catch (_) {}
      final emoji = gift?['emoji'] as String? ?? '🎁';
      final title = gift?['title'] as String? ?? 'Подарок';
      final stars = gift?['stars'] as int? ?? 0;
      final note = gift?['message'] as String?;
      final status = gift?['status'] as String? ?? 'held';
      final isCollectible = gift?['is_collectible'] == true;
      final isAnonymousGift = gift?['is_anonymous'] == true;
      final serial = gift?['serial'];
      final totalSupply = gift?['total_supply'];
      final serialText = isCollectible && serial != null
          ? (totalSupply != null ? '#$serial / $totalSupply' : '#$serial')
          : null;
      final canAct = !mine &&
          status != 'transferred' &&
          status != 'converted' &&
          status != 'refunded' &&
          (status == 'held' || status == 'kept') &&
          (onConvertGift != null || onKeepGift != null);
      final canRefund = mine &&
          onRefundGift != null &&
          !isCollectible &&
          (status == 'held' || status == 'kept');
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: Container(
          width: 220,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: quoteBg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 6),
              HighlightedText(
                text: title,
                style: TextStyle(color: fg, fontWeight: FontWeight.w800),
              ),
              if (isAnonymousGift)
                Text(
                  'Имя скрыто',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              if (serialText != null)
                Text(
                  'Collectible $serialText',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              Text(
                status == 'converted'
                    ? 'Конвертирован · $stars ★'
                    : status == 'transferred'
                        ? 'Передан · $stars ★'
                        : status == 'refunded'
                            ? 'Возвращён · $stars ★'
                            : status == 'kept'
                                ? 'В профиле · $stars ★'
                                : '$stars ★',
                style: TextStyle(
                  color: scheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (note != null && note.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                HighlightedText(
                  text: note.trim(),
                  style: TextStyle(color: fg.withValues(alpha: 0.8)),
                ),
              ],
              if (canAct || canRefund) ...[
                const SizedBox(height: 10),
                if (giftActionBusy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (status == 'held' && onKeepGift != null)
                        FilledButton.tonal(
                          onPressed: onKeepGift,
                          child: const Text('Оставить'),
                        ),
                      if (onConvertGift != null && !isCollectible)
                        FilledButton(
                          onPressed: onConvertGift,
                          child: Text('В ★ · $stars'),
                        ),
                      if (canRefund)
                        OutlinedButton(
                          onPressed: onRefundGift,
                          child: const Text('Вернуть'),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      );
    } else if (message.type == 'voice' && message.mediaUrl != null) {
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: ChatVoiceBubble(
          message: message,
          foregroundColor: fg,
          accentColor: scheme.primary,
          activeColor: mine ? scheme.primary : scheme.secondary,
          onCompleted: onVoiceCompleted,
          onTranscribe: onTranscribe,
          transcribing: transcribing,
        ),
      );
    } else if (message.type == 'video_note' && message.mediaUrl != null) {
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatVideoNoteBubble(
              mediaUrl: message.mediaUrl!,
              durationSec: message.voiceDurationSec,
              accentColor: scheme.primary,
            ),
            if ((message.transcription ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: HighlightedText(
                  text: message.transcription!,
                  style: TextStyle(color: fg, fontSize: 13),
                ),
              )
            else if (onTranscribe != null)
              TextButton(
                onPressed: transcribing ? null : onTranscribe,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: transcribing
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      )
                    : const Text('Текст'),
              ),
          ],
        ),
      );
    } else if (message.type == 'poll' && message.poll != null) {
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: ChatPollBubble(
          poll: message.poll!,
          foregroundColor: fg,
          accentColor: scheme.primary,
          mutedColor: fg.withValues(alpha: 0.65),
          optionBackground: quoteBg,
          onVote: onPollVote,
          voting: pollVoting,
          canClose: onPollClose != null,
          onClose: onPollClose,
          closing: pollClosing,
          onShowVoters: onShowPollVoters,
          onAddOption: onAddPollOption,
        ),
      );
    } else if (message.type == 'checklist' && message.checklist != null) {
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: ChatChecklistBubble(
          checklist: message.checklist!,
          foregroundColor: fg,
          accentColor: scheme.primary,
          mutedColor: fg.withValues(alpha: 0.65),
          onToggle: onChecklistToggle,
          busy: checklistBusy,
        ),
      );
    } else if (message.type == 'story_reply' ||
        ChatStoryReplyPayload.tryParse(message.content) != null) {
      final storyReply = ChatStoryReplyPayload.tryParse(message.content);
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: storyReply == null
            ? Text('🖼 Ответ на сторис', style: TextStyle(color: fg))
            : ChatStoryReplyBubble(
                payload: storyReply,
                foregroundColor: fg,
                accentColor: scheme.primary,
                backgroundColor: quoteBg,
              ),
      );
    } else if (message.type == 'location' ||
        ChatLocationPayload.tryParse(message.content) != null) {
      final loc = ChatLocationPayload.tryParse(message.content);
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: loc == null
            ? Text('📍 Геопозиция', style: TextStyle(color: fg))
            : ChatLocationBubble(
                payload: loc,
                foregroundColor: fg,
                accentColor: scheme.primary,
                backgroundColor: quoteBg,
                isMine: mine,
                onStopLive: onStopLiveLocation,
              ),
      );
    } else if (ChatContactPayload.tryParse(message.content)
        case final contact?) {
      final contactUserId = contact.userId;
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: ChatContactBubble(
          payload: contact,
          foregroundColor: fg,
          accentColor: scheme.primary,
          cardColor: quoteBg,
          onOpenProfile: contactUserId == null || onOpenContactUser == null
              ? null
              : () => onOpenContactUser!(contactUserId),
          onMessageUser:
              contactUserId == null || onMessageContactUser == null
                  ? null
                  : () => onMessageContactUser!(contactUserId),
          onSaveToPhone: contact.phone == null || onSaveContactToPhone == null
              ? null
              : () => onSaveContactToPhone!(contact),
          onAddHanContact: contactUserId == null || onAddHanContact == null
              ? null
              : () => onAddHanContact!(contactUserId),
        ),
      );
    } else if (message.type == 'file' && message.mediaUrl != null) {
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: Material(
          color: quoteBg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onFileTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insert_drive_file_outlined, color: fg, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: HighlightedText(
                      text: message.content.trim().isEmpty
                          ? 'Файл'
                          : message.content.trim(),
                      query: highlightQuery,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else if (isImage) {
      final spoilerHidden = message.hasSpoiler && !spoilerRevealed;
      final image = GestureDetector(
        onTap: spoilerHidden ? onRevealSpoiler : onImageTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: Builder(
            builder: (context) {
              final resolved = ServerConfig.resolvePublisherAvatarUrl(
                ServerConfig.resolveMediaUrl(message.mediaUrl!),
              );
              final animated = _chatIsGifMediaUrl(resolved) ||
                  _chatIsGifMediaUrl(message.mediaUrl!);
              final raw = CachedNetworkImage(
                imageUrl: resolved,
                fit: BoxFit.cover,
                memCacheWidth: animated ? null : 720,
                memCacheHeight: animated ? null : 720,
                maxWidthDiskCache: animated ? null : 960,
                maxHeightDiskCache: animated ? null : 960,
                progressIndicatorBuilder: (_, __, progress) => SizedBox(
                  width: 180,
                  height: 180,
                  child: ColoredBox(
                    color: quoteBg,
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          value: progress.progress,
                          color: fg.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => SizedBox(
                  width: 180,
                  height: 120,
                  child: ColoredBox(
                    color: quoteBg,
                    child: Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: fg.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              );
              if (!spoilerHidden) return raw;
              return Stack(
                alignment: Alignment.center,
                children: [
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: raw,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.blur_on, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Спойлер',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

      if (hasCaption) {
        mainContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            image,
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: _withBottomMeta(
                fg: fg,
                mine: mine,
                inlineMeta: true,
                child: HighlightedText(
                  text: message.content,
                  query: highlightQuery,
                  style: TextStyle(color: fg, height: 1.25),
                  trailingReserveWidth: _metaReserveWidth(mine),
                  parseMarkup: true,
                  highlightMentions: true,
                  onMentionTap: onMentionTap,
                  mentionLabels: mentionLabels,
                ),
              ),
            ),
          ],
        );
      } else {
        mainContent = _withBottomMeta(
          fg: fg,
          mine: mine,
          onMedia: true,
          child: image,
        );
      }
    } else if (isSticker) {
      final sticker = ChatStickerTile(
        mediaUrl: message.mediaUrl!,
        animated: ChatStickerTile.looksAnimated(message.mediaUrl!),
        onTap: onImageTap,
      );
      // Telegram: sticker has no filled bubble; soft time/ticks under it.
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        onMedia: false,
        child: sticker,
      );
    } else if (isVideo) {
      final spoilerHidden = message.hasSpoiler && !spoilerRevealed;
      final video = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: spoilerHidden
            ? GestureDetector(
                onTap: onRevealSpoiler,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: InlineVideoPlayer(
                        videoUrl: message.mediaUrl!,
                        onTap: null,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.blur_on, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Спойлер',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : InlineVideoPlayer(
                videoUrl: message.mediaUrl!,
                onTap: onVideoTap,
              ),
      );

      if (hasCaption) {
        mainContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            video,
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: _withBottomMeta(
                fg: fg,
                mine: mine,
                inlineMeta: true,
                child: HighlightedText(
                  text: message.content,
                  query: highlightQuery,
                  style: TextStyle(color: fg, height: 1.25),
                  trailingReserveWidth: _metaReserveWidth(mine),
                  parseMarkup: true,
                  highlightMentions: true,
                  onMentionTap: onMentionTap,
                  mentionLabels: mentionLabels,
                ),
              ),
            ),
          ],
        );
      } else {
        mainContent = _withBottomMeta(
          fg: fg,
          mine: mine,
          onMedia: true,
          child: video,
        );
      }
    } else if (message.content.isNotEmpty && message.type != 'voice') {
      final previewUrl = message.disableWebpagePreview
          ? null
          : extractFirstHttpUrl(message.content);
      final hasLinkPreview = previewUrl != null;
      final textStyle = TextStyle(color: fg, height: 1.22, fontSize: 15.5);
      final translated = (translation ?? '').trim();
      final textChild = HighlightedText(
        text: message.content,
        query: highlightQuery,
        style: textStyle,
        trailingReserveWidth: hasLinkPreview || translated.isNotEmpty
            ? null
            : _metaReserveWidth(mine),
        highlightMentions: true,
        parseMarkup: true,
        onMentionTap: onMentionTap,
        mentionLabels: mentionLabels,
      );
      final textWithTranslation = translated.isEmpty
          ? textChild
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                textChild,
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: HighlightedText(
                    text: translated,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.78),
                      height: 1.22,
                      fontSize: 14.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            );
      if (hasLinkPreview) {
        mainContent = _withBottomMeta(
          fg: fg,
          mine: mine,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              textWithTranslation,
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ChatLinkPreview(
                  url: previewUrl,
                  foregroundColor: fg,
                  accentColor: scheme.primary,
                  backgroundColor: quoteBg,
                ),
              ),
            ],
          ),
        );
      } else {
        mainContent = _withBottomMeta(
          fg: fg,
          mine: mine,
          inlineMeta: translated.isEmpty,
          child: textWithTranslation,
        );
      }
    } else {
      mainContent = Align(
        alignment: Alignment.centerRight,
        child: _messageMeta(fg: fg, mine: mine),
      );
    }

    final nameColor = _senderNameColor();
    final bubbleCore = Container(
      margin: EdgeInsets.only(
        top: cluster.starts ? 2 : 0.5,
        bottom: hasReactions ? 0 : (cluster.ends ? 2 : 0.5),
      ),
      padding: isMedia
          ? contentPadding
          : const EdgeInsets.fromLTRB(8, 4, 7, 3),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(
        // Telegram ~78% of screen; bubble itself shrink-wraps short text.
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      decoration: BoxDecoration(
        color: bubbleNeedsBackground ? bg : Colors.transparent,
        borderRadius: bubbleRadius,
        // No outline/shadow on normal bubbles — Telegram is fill-only.
        border: isActiveSearchMatch
            ? Border.all(color: activeBorderColor, width: 1.4)
            : null,
        boxShadow: isActiveSearchMatch
            ? [
                BoxShadow(
                  color: activeShadowColor,
                  blurRadius: 10,
                  spreadRadius: 0.4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSenderName && (senderLabel?.isNotEmpty ?? false)) ...[
            Padding(
              padding: isMedia && !isSticker
                  ? const EdgeInsets.fromLTRB(8, 5, 8, 0)
                  : EdgeInsets.zero,
              child: onSenderTap != null
                  ? GestureDetector(
                      onTap: onSenderTap,
                      behavior: HitTestBehavior.opaque,
                      child: HighlightedText(
                        text: senderLabel!,
                        style: TextStyle(
                          color: nameColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : HighlightedText(
                      text: senderLabel!,
                      style: TextStyle(
                        color: nameColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            const SizedBox(height: 2),
          ],
          if (isForwarded)
            Padding(
              padding: isMedia && !isSticker
                  ? const EdgeInsets.fromLTRB(8, 5, 8, 0)
                  : EdgeInsets.zero,
              child: GestureDetector(
                onTap: onForwardFromTap,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'Переслано от ${message.forwardFromName?.trim().isNotEmpty == true ? previewTextWithCustomEmoji(message.forwardFromName!.trim()) : 'пользователя'}',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                    decoration: onForwardFromTap == null
                        ? null
                        : TextDecoration.underline,
                    decorationColor: scheme.primary.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          if (isForwarded) const SizedBox(height: 2),
          if (replyQuote != null)
            Padding(
              padding: isMedia && !isSticker
                  ? const EdgeInsets.fromLTRB(8, 5, 8, 0)
                  : EdgeInsets.zero,
              child: _buildReplyQuote(fg, quoteBg),
            ),
          mainContent,
          _buildInlineKeyboard(fg, quoteBg),
        ],
      ),
    );

    // Reactions float under the bubble like Telegram (not inside fill).
    final bubble = hasReactions
        ? Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              bubbleCore,
              Transform.translate(
                offset: const Offset(0, -4),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: mine ? 0 : 4,
                    right: mine ? 4 : 0,
                    bottom: cluster.ends ? 4 : 2,
                  ),
                  child: _buildReactions(fg, quoteBg),
                ),
              ),
            ],
          )
        : bubbleCore;

    if (!wrapWithAlign) return bubble;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }
}

class _ChatVideoPlayerPage extends StatefulWidget {
  const _ChatVideoPlayerPage({
    required this.videoUrl,
    this.caption,
    this.allowSaveShare = true,
  });

  final String videoUrl;
  final String? caption;
  final bool allowSaveShare;

  @override
  State<_ChatVideoPlayerPage> createState() => _ChatVideoPlayerPageState();
}

class _ChatVideoPlayerPageState extends State<_ChatVideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _isPaused = false;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initVideo());
  }

  Future<void> _initVideo() async {
    setState(() {
      _initialized = false;
      _hasError = false;
      _isPaused = false;
    });
    final old = _controller;
    _controller = null;
    unawaited(old?.dispose());
    try {
      final c = await VideoPlayerHelper.createPreparedController(
        widget.videoUrl,
        muted: false,
        autoPlay: true,
      );
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _initialized = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _initialized = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Видео'),
        actions: [
          if (widget.allowSaveShare) ...[
            IconButton(
              tooltip: 'Сохранить',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => unawaited(
                MediaDownloadHelper.saveMedia(
                  context,
                  rawUrl: widget.videoUrl,
                  caption: widget.caption,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Поделиться',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => unawaited(
                MediaDownloadHelper.shareMedia(
                  context,
                  rawUrl: widget.videoUrl,
                  caption: widget.caption,
                ),
              ),
            ),
          ],
        ],
      ),
      body: Center(
        child: _hasError
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 64, color: Colors.white70),
                  const SizedBox(height: 16),
                  const Text(
                    'Не удалось загрузить видео',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _initVideo,
                    child: const Text('Повторить'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Назад'),
                  ),
                ],
              )
            : !_initialized || _controller == null
                ? const CircularProgressIndicator(color: Colors.white)
                : AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: GestureDetector(
                      onTap: () async {
                        final paused = await VideoPlayerHelper.toggleOrStart(
                          _controller!,
                        );
                        if (!mounted) return;
                        setState(() => _isPaused = paused);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_controller!),
                          if (_isPaused)
                            const Icon(
                              Icons.play_circle_fill,
                              color: Colors.white70,
                              size: 64,
                            ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _ComposerFormatChip extends StatelessWidget {
  const _ComposerFormatChip({
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.italic = false,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                fontSize: 13,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
