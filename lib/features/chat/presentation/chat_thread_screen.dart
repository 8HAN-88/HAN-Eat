import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../bots/data/bot_inline_service.dart';
import '../../bots/presentation/inline_suggestions.dart';
import '../../miniapps/data/miniapps_service.dart';
import '../../miniapps/presentation/miniapp_webview_screen.dart';
import '../../bots/data/bot_models.dart';
import '../../../services/api_service.dart';
import '../../calls/presentation/video_call_screen.dart';
import '../../calls/presentation/voice_room_screen.dart';

import '../../../app/app_router.dart';
import '../../../core/theme/color_schemes.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/network/feed_load_helper.dart';
import '../../../core/network/api_rate_limit_backoff.dart';
import '../../../core/network/haneat_http_client.dart';
import '../../../core/platform/web_page_visibility.dart';
import '../../../models/chat_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/api_reachability_service.dart';
import '../../../services/chat_cache_service.dart';
import '../../../services/chat_media_outbox_service.dart';
import '../../../services/feed_sync_service.dart';
import '../../../services/paid_features_service.dart';
import '../../../services/product_analytics.dart';
import '../../../services/chat_service.dart';
import '../../../services/chat_stream_service.dart';
import '../../../utils/chat_time_format.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/session_snackbar.dart';
import '../../../widgets/app_avatar.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/chat_link_preview.dart';
import '../../../widgets/fullscreen_image_viewer.dart';
import '../../../widgets/highlighted_text.dart';
import '../../../widgets/telegram_ui.dart';
import '../application/active_chat_session.dart';
import '../application/chat_realtime_signals.dart';
import '../application/chats_hub_refresh_provider.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/server_config.dart';
import '../../../services/chat_hub_ui_prefs.dart';
import '../../../services/chat_thread_ui_prefs.dart';
import '../../../utils/presence_format.dart';
import '../../../utils/video_player_helper.dart';
import '../../../widgets/inline_video_player.dart';
import '../../../widgets/chat_target_picker_sheet.dart';
import '../../../widgets/chat_sticker_tile.dart';
import 'widgets/chat_message_action_overlay.dart';
import 'widgets/chat_message_selection_toolbar.dart';
import '../application/chat_recent_files_store.dart';
import 'widgets/chat_attach_sheet.dart';
import 'widgets/chat_poll_bubble.dart';
import 'widgets/create_chat_poll_sheet.dart';
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
  });

  final int conversationId;
  final ChatConversation? initialConversation;
  final ChatUserBrief? initialPeer;
  final int? initialJumpMessageId;

  @override
  ConsumerState<ChatThreadLoaderScreen> createState() =>
      _ChatThreadLoaderScreenState();
}

class _ChatThreadLoaderScreenState
    extends ConsumerState<ChatThreadLoaderScreen> {
  ChatConversation? _conversation;
  bool _loading = false;
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
    if (_conversation == null) _resolveConversation();
  }

  Future<void> _resolveConversation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conv = await ChatService.getConversation(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _conversation = conv;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _refreshHub() {
    ref.read(chatsHubRefreshProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _conversation == null) {
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
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _refreshHub();
      },
      child: ChatThreadScreen(
        conversation: _conversation!,
        initialJumpMessageId: widget.initialJumpMessageId,
      ),
    );
  }
}

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversation,
    this.initialJumpMessageId,
  });

  final ChatConversation conversation;
  final int? initialJumpMessageId;

  int get conversationId => conversation.id;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
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
  final List<_PendingMediaSend> _mediaOutboundQueue = [];
  bool _mediaDrainActive = false;
  _PendingMediaSend? _pendingMediaRetry;
  final Set<String> _inFlightMediaClientIds = {};
  final Map<int, _PendingMediaSend> _pendingMediaByTempId = {};
  final Map<String, int> _pendingMediaTempIdByClientId = {};
  final Map<String, double> _pendingMediaProgressByClientId = {};
  final Set<String> _cancelledPendingMediaClientIds = {};
  bool _voiceSending = false;
  bool _showVoiceHint = false;
  bool _hasMore = false;
  int? _nextCursor;
  Timer? _pollTimer;
  bool _pollInFlight = false;
  Timer? _presenceTimer;
  Timer? _typingDebounce;
  Timer? _inlineDebounce;
  List<InlineResult> _inlineResults = [];
  OverlayEntry? _inlineOverlayEntry;
  List<BotListItem> _myBots = [];
  OverlayEntry? _botAutocompleteOverlayEntry;
  StreamSubscription<void>? _signalSub;
  VoidCallback? _apiReachabilityListener;
  VoidCallback? _apiConnectingListener;
  VoidCallback? _deviceOnlineListener;
  ValueListenable<bool>? _deviceOnlineListenable;
  ChatStreamService? _stream;
  ChatMessage? _replyTo;
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
  bool _holdActive = false;
  bool _recordCancelled = false;
  bool _hasText = false;
  Duration _recordDuration = Duration.zero;
  int _messageLoadSeq = 0;
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
  bool _threadSearchOpen = false;
  bool _showOnlyFailedMessages = false;
  String _threadSearchQuery = '';
  _ThreadSearchFilter _threadSearchFilter = _ThreadSearchFilter.all;
  int? _threadSearchSenderId;
  int _searchMatchIndex = 0;
  bool _searchAutoloading = false;
  int _searchBackfillLoads = 0;
  int _searchBackfillSeq = 0;
  bool _jumpingToDate = false;
  ChatMessage? _pinnedMessage;
  ChatMessage? _editingMessage;
  bool _showJumpToBottom = false;
  int _newMessagesBelow = 0;
  bool _suppressMarkRead = false;
  /// Telegram-style unread divider shown above this message id.
  int? _unreadDividerBeforeId;
  final Set<int> _typingUserIds = <int>{};
  final Map<int, Timer> _typingUserTimers = <int, Timer>{};
  bool _selectionMode = false;
  bool _chatExitActionRunning = false;
  final _selectedMessageIds = <int>{};
  final _votingPollIds = <int>{};
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
  Timer? _pendingMediaAutoRetryTimer;
  Timer? _manualReadyRetryTimer;
  DateTime? _slowModeLockUntil;
  DateTime? _floodLockUntil;
  DateTime? _pendingMediaAutoRetryUntil;
  DateTime? _manualReadyRetryUntil;
  int _manualReadyRetryDeferrals = 0;
  int _floodCooldownTotalSeconds = 0;
  int? _lastSlowModeTick;
  bool _slowModeCountdownHapticsEnabled = true;
  bool _autoRetryOnLimitsEnabled = true;
  String? _pendingMediaAutoRetryClientMessageId;
  String? _pendingMediaAutoRetryReason;

  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
  static const _overlayReactions = ['👍', '👌', '❤️', '🔥', '👎', '🥰', '👏'];
  static const _uiAnimDuration = Duration(milliseconds: 160);
  static const _composerIconSize = 20.0;
  static const _composerButtonSide = 40.0;
  static const _telegramAccent = AppColors.primary;
  static const _uploadAccent = AppColors.primary;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _pendingInitialJumpMessageId = widget.initialJumpMessageId;
    _pinned = widget.conversation.pinned;
    _muted = widget.conversation.muted;
    ActiveChatSession.instance.setOpen(widget.conversationId);
    WidgetsBinding.instance.addObserver(this);
    _inputFocusNode.addListener(_onComposerFocusChanged);
    _scroll.addListener(_onScrollChanged);
    _controller.addListener(_onInputChanged);
    unawaited(_loadCachedMessages().then((_) async {
      await _restoreFailedTextSends();
      await _restoreMediaOutbox();
    }));
    unawaited(_loadSlowModeUiPrefs());
    unawaited(_restoreDraft());
    unawaited(_restoreVoiceHint());
    unawaited(AuthService.getAccessTokenForApi());
    unawaited(_loadMyBots());
    unawaited(_refreshScheduledPendingCount());
    _load(refresh: true);
    _startPolling();
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_appPaused) _refreshConversation();
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
    _reconcileSlowModeCooldownWithConversation();
    if (kIsWeb) {
      registerWebPageVisibilityListener(
        _onWebTabVisible,
        onHidden: _onWebTabHidden,
      );
    }
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
      unawaited(_drainTextOutboundQueue());
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
      if (!mounted) return;
      setState(() {
        _slowModeCountdownHapticsEnabled = hapticsEnabled;
        _autoRetryOnLimitsEnabled = autoRetryEnabled;
      });
      if (!autoRetryEnabled) {
        _clearAllAutoRetrySchedules();
      }
    } catch (_) {}
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Автоповтор при лимитах включен'
              : 'Автоповтор при лимитах выключен',
        ),
      ),
    );
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
      _pendingMediaRetry != null || _failedTextSends.isNotEmpty;

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
        _ => '',
      },
      createdAt: DateTime.now(),
      isMine: true,
      isRead: false,
      replyToMessageId: pending.replyToMessageId,
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
          if (_sending) {
            _beginSending(
              status: 'Пауза ${_formatSlowModeCountdown(wait)}…',
            );
          }
          await Future<void>.delayed(Duration(seconds: wait));
          if (!mounted) return;
          continue;
        }
        final pending = _mediaOutboundQueue.first;
        if (!_sending) {
          _beginSending(status: _mediaStatusLabel(pending));
        }
        try {
          await _deliverMediaPending(pending);
          _removeMediaFromQueue(pending.clientMessageId);
          if (_pendingMediaRetry?.clientMessageId == pending.clientMessageId) {
            setState(() => _pendingMediaRetry = null);
          }
          if (_mediaOutboundQueue.isEmpty) {
            _endSending();
          } else if (mounted) {
            _beginSending(status: _mediaStatusLabel(_mediaOutboundQueue.first));
          }
          _scrollToBottom();
        } catch (e) {
          if (e is _CancelledPendingMediaException) {
            _removeMediaFromQueue(pending.clientMessageId);
            if (_mediaOutboundQueue.isEmpty) {
              _endSending();
            }
            continue;
          }
          if (e is TimeoutException &&
              pending.kind == _PendingMediaKind.voice) {
            _removeMediaFromQueue(pending.clientMessageId);
            _endSending();
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
            _endSending();
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
              if (!_autoRetryOnLimitsEnabled) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Автоповтор отключен — нажмите «Повторить» вручную',
                    ),
                  ),
                );
              }
              showErrorSnackBar(context, e);
            }
            continue;
          }
          if (err.contains('group_flood_limited')) {
            final retryAfter =
                e is ApiClientException ? e.retryAfterSeconds : null;
            pending.lastRetryAfterSeconds = (retryAfter ?? 60).clamp(1, 3600);
            pending.lastLimitedAt = DateTime.now().toUtc();
            _removeMediaFromQueue(pending.clientMessageId);
            _endSending();
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
              if (!_autoRetryOnLimitsEnabled) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Автоповтор отключен — нажмите «Повторить» вручную',
                    ),
                  ),
                );
              }
              showErrorSnackBar(context, e);
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
          _endSending();
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
            showErrorSnackBar(context, e, fallback: fallback);
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
            replyToMessageId: reply,
            clientMessageId: pending.clientMessageId,
          );
        case _PendingMediaKind.video:
          msg = await ChatService.sendVideo(
            conversationId: widget.conversationId,
            mediaUrl: mediaUrl,
            replyToMessageId: reply,
            clientMessageId: pending.clientMessageId,
          );
        case _PendingMediaKind.file:
          msg = await ChatService.sendFile(
            conversationId: widget.conversationId,
            mediaUrl: mediaUrl,
            fileName: pending.fileName ?? 'file',
            replyToMessageId: reply,
            clientMessageId: pending.clientMessageId,
          );
        case _PendingMediaKind.voice:
          msg = await ChatService.sendVoice(
            conversationId: widget.conversationId,
            mediaUrl: mediaUrl,
            durationSec: pending.voiceDurationSec ?? 1,
            replyToMessageId: reply,
            clientMessageId: pending.clientMessageId,
          );
      }
      if (_cancelledPendingMediaClientIds.contains(pending.clientMessageId)) {
        throw _CancelledPendingMediaException();
      }
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
        ? const Duration(seconds: 25)
        : const Duration(seconds: 4);
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
  }

  Future<void> _restoreFailedTextSends() async {
    final rows =
        await ChatCacheService.loadFailedTextSends(widget.conversationId);
    if (rows.isEmpty || !mounted) return;
    final uid = AuthService.instance.currentUser?.id ?? 0;
    final restored = <int, _PendingTextSend>{};
    final restoredMessages = <ChatMessage>[];
    for (final row in rows) {
      final text = row['text'] as String? ?? '';
      final clientMessageId = row['client_message_id'] as String? ?? '';
      final tempId = row['temp_id'] as int? ?? 0;
      if (text.trim().isEmpty || clientMessageId.isEmpty || tempId >= 0) {
        continue;
      }
      final replyRaw = row['reply_to_message_id'];
      final pending = _PendingTextSend(
        text: text,
        clientMessageId: clientMessageId,
        tempId: tempId,
        replyToMessageId: replyRaw is int ? replyRaw : null,
      );
      pending.attempts = row['attempts'] as int? ?? 0;
      pending.lastRetryAfterSeconds =
          (row['last_retry_after_seconds'] as int?)?.clamp(1, 3600);
      pending.lastLimitedAt = DateTime.tryParse(
        row['last_limited_at'] as String? ?? '',
      );
      restored[tempId] = pending;
      if (!_messages.any((m) => m.id == tempId)) {
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
          ),
        );
      }
    }
    if (restored.isEmpty) return;
    setState(() {
      _failedTextSends.addAll(restored);
      _messages.addAll(restoredMessages);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    _syncSlowModeCountdownTimer();
  }

  Future<void> _persistFailedTextSends() {
    return ChatCacheService.saveFailedTextSends(
      widget.conversationId,
      _failedTextSends.values
          .map(
            (p) => {
              'text': p.text,
              'client_message_id': p.clientMessageId,
              'temp_id': p.tempId,
              'reply_to_message_id': p.replyToMessageId,
              'attempts': p.attempts,
              'last_retry_after_seconds': p.lastRetryAfterSeconds,
              'last_limited_at': p.lastLimitedAt?.toUtc().toIso8601String(),
              'created_at': DateTime.now().toUtc().toIso8601String(),
            },
          )
          .toList(growable: false),
    );
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

    // === Live Inline Mode (@bot) ===
    _scheduleInlineSuggestions();

    // === Autocomplete @botname from my bots ===
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

  void _scheduleBotAutocomplete() {
    if (_myBots.isEmpty) return;

    final text = _controller.text;
    // Ищем @word в конце строки (или после пробела)
    final match = RegExp(r'(?:^|\s)@([a-zA-Z0-9_]*)$').firstMatch(text);
    if (match == null) {
      _hideBotAutocompleteOverlay();
      return;
    }

    final query = match.group(1)!.toLowerCase();

    // Фильтруем своих ботов
    final filtered = _myBots
        .where((b) => b.username.toLowerCase().contains(query))
        .take(8)
        .toList();

    if (filtered.isEmpty) {
      _hideBotAutocompleteOverlay();
      return;
    }

    _showBotAutocompleteOverlay(filtered, query);
  }

  void _showBotAutocompleteOverlay(List<BotListItem> bots, String query) {
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
              itemCount: bots.length,
              itemBuilder: (context, index) {
                final bot = bots[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: bot.avatarUrl != null
                        ? CachedNetworkImageProvider(bot.avatarUrl!)
                        : null,
                    child: bot.avatarUrl == null
                        ? const Icon(Icons.smart_toy_outlined)
                        : null,
                  ),
                  title: Text('@${bot.username}'),
                  subtitle: bot.name.isNotEmpty ? Text(bot.name) : null,
                  onTap: () {
                    _insertBotMention(bot.username);
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

  /// Вставляет @username в поле ввода, заменяя текущий @query
  void _insertBotMention(String username) {
    final text = _controller.text;
    final match = RegExp(r'(?:^|\s)@([a-zA-Z0-9_]*)$').firstMatch(text);
    if (match == null) return;

    final start = match.start + (text[match.start] == ' ' ? 1 : 0);
    final newText = '${text.substring(0, start)}@$username ';

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
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
    _controller.text = result.payload;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    // Можно сразу отправить или оставить для редактирования
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
          }
        });
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
        if (_pinnedMessage?.id == messageId) _pinnedMessage = null;
      });
      return;
    }
    if (type == 'typing') {
      final rawUid = event['user_id'];
      final uid = rawUid is int ? rawUid : int.tryParse('$rawUid');
      _onPeerTyping(uid);
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
      final readerId = event['user_id'];
      final myId = AuthService.instance.currentUser?.id;
      if (readerId == myId) return;
      final raw = event['last_read_message_id'];
      final readId = raw is int ? raw : int.tryParse('$raw');
      if (readId != null) _applyReadReceipt(readId);
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
    if (type == 'message.pinned') {
      final raw = event['message'];
      if (raw is Map<String, dynamic>) {
        try {
          setState(() {
            _pinnedMessage = ChatService.messageFromStreamPayload(raw);
          });
        } catch (_) {}
      }
      return;
    }
    if (type == 'message.unpinned') {
      setState(() => _pinnedMessage = null);
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
      if (_pinnedMessage?.id == updated.id) {
        _pinnedMessage = applyIncomingChatMessagePreservingLocalPoll(
          _pinnedMessage!,
          updated,
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
      if (_pinnedMessage?.id == messageId) {
        _pinnedMessage = _pinnedMessage!.copyWith(reactions: reactions);
      }
    });
  }

  String? _normalizedMediaUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    return ServerConfig.resolveMediaUrl(url.trim());
  }

  bool _isDuplicateMessage(ChatMessage a, ChatMessage b) {
    if (a.id > 0 && b.id > 0 && a.id == b.id) return true;
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

  /// Вставляет или обновляет сообщение, убирая оптимистичные и повторные копии.
  /// Возвращает true, если сообщение добавлено впервые.
  bool _integrateMessage(ChatMessage msg, {int? removeTempId}) {
    if (removeTempId != null) {
      _messages.removeWhere((m) => m.id == removeTempId);
      final removedFailedText = _failedTextSends.remove(removeTempId) != null;
      _removePendingMediaByTempId(removeTempId);
      if (removedFailedText) {
        unawaited(_persistFailedTextSends());
      }
    }
    _messages.removeWhere(
      (m) =>
          m.id < 0 &&
          m.isMine &&
          !_failedTextSends.containsKey(m.id) &&
          !_pendingMediaByTempId.containsKey(m.id),
    );
    final idx = _messages.indexWhere(
      (m) => (m.id > 0 && m.id == msg.id) || _isDuplicateMessage(m, msg),
    );
    if (idx >= 0) {
      _messages[idx] =
          applyIncomingChatMessagePreservingLocalPoll(_messages[idx], msg);
      return false;
    }
    _messages.add(msg);
    return true;
  }

  String _pinnedPreview(ChatMessage msg) {
    if (msg.type == 'voice') return '🎤 Голосовое';
    if (msg.type == 'image') return '📷 Фото';
    if (msg.type == 'video') return '🎬 Видео';
    if (msg.type == 'sticker') return '🧩 Стикер';
    if (msg.type == 'file') {
      final name = msg.content.trim();
      return name.isEmpty ? '📎 Файл' : '📎 $name';
    }
    final text = msg.content.trim();
    return text.isEmpty ? 'Сообщение' : text;
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

  Future<void> _restoreVoiceHint() async {
    final dismissed = await ChatHubUiPrefs.isVoiceHintDismissed();
    if (!mounted) return;
    if (!dismissed) setState(() => _showVoiceHint = true);
  }

  Future<void> _dismissVoiceHint() async {
    await ChatHubUiPrefs.dismissVoiceHint();
    if (mounted) setState(() => _showVoiceHint = false);
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
    unawaited(_drainTextOutboundQueue());
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Автоповтор для сообщения отменен')),
    );
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
    if (mediaCount == 0 && failedTextIds.isEmpty) return;
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
      _messages.removeWhere(
        (m) =>
            failedTextIds.contains(m.id) ||
            (failedMediaTempId != null && m.id == failedMediaTempId),
      );
      if (failedMediaTempId != null) {
        _removePendingMediaByTempId(failedMediaTempId);
      }
    });
    unawaited(_persistFailedTextSends());
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Автоповтор для медиа отменен')),
    );
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
      _endSending();
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
    final autoRetryDisabledHint = !_autoRetryOnLimitsEnabled && !autoRetrying
        ? ' • автоповтор отключен'
        : '';
    return Material(
      color: scheme.errorContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                autoRetrying
                    ? 'Не удалось отправить $label • автоповтор через '
                        '${_formatSlowModeCountdown(_pendingMediaAutoRetryRemainingSeconds)}'
                    : 'Не удалось отправить $label$autoRetryDisabledHint',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
              ),
            ),
            TextButton(
              onPressed: (_sending || autoRetrying) ? null : _retryPendingMedia,
              child:
                  Text(autoRetrying ? 'Отправим автоматически' : 'Повторить'),
            ),
            if (autoRetrying)
              TextButton(
                onPressed: _sending ? null : _cancelPendingMediaAutoRetry,
                child: const Text('Отменить автоповтор'),
              ),
            TextButton(
              onPressed: _sending ? null : _discardPendingMedia,
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreDraft() async {
    final draft = await ChatCacheService.loadDraft(widget.conversationId);
    if (!mounted || draft == null || draft.isEmpty) return;
    if (_controller.text.trim().isNotEmpty) return;
    _controller.text = draft;
    _controller.selection = TextSelection.collapsed(offset: draft.length);
  }

  void _scheduleDraftSave() {
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(
        ChatCacheService.saveDraft(widget.conversationId, _controller.text),
      );
    });
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
      if (_showJumpToBottom) {
        setState(() {
          _showJumpToBottom = false;
          _newMessagesBelow = 0;
        });
      }
      // Telegram: mark read when the user actually reaches the bottom.
      _scheduleMarkRead();
      return;
    }
    if (!_showJumpToBottom) {
      setState(() => _showJumpToBottom = true);
    }
  }

  void _clearTypingState() {
    for (final t in _typingUserTimers.values) {
      t.cancel();
    }
    _typingUserTimers.clear();
    _typingUserIds.clear();
    _peerTyping = false;
  }

  void _onPeerTyping(int? userId) {
    final myId = AuthService.instance.currentUser?.id;
    if (userId != null && userId == myId) return;
    final key = userId ?? 0;
    setState(() {
      _typingUserIds.add(key);
      _peerTyping = true;
    });
    _typingUserTimers[key]?.cancel();
    _typingUserTimers[key] = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _typingUserIds.remove(key);
        _peerTyping = _typingUserIds.isNotEmpty;
      });
      _typingUserTimers.remove(key);
    });
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

  String _typingSubtitleLabel({required bool isGroup}) {
    if (!_peerTyping) return '';
    if (!isGroup) return 'печатает…';
    final names = <String>[];
    for (final id in _typingUserIds) {
      if (id == 0) continue;
      final name = _displayNameForUserId(id);
      if (name == null || name.isEmpty) continue;
      names.add(name.split(' ').first);
    }
    if (names.isEmpty) return 'печатает…';
    if (names.length == 1) return '${names.first} печатает…';
    if (names.length == 2) {
      return '${names[0]} и ${names[1]} печатают…';
    }
    return '${names.length} печатают…';
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

  void _scrollAfterInitialLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_pendingInitialJumpMessageId != null) {
        unawaited(_jumpToInitialMessageIfNeeded());
        return;
      }
      final firstUnread = _firstUnreadMessageId();
      if (firstUnread != null) {
        setState(() => _unreadDividerBeforeId = firstUnread);
        _scrollToMessage(firstUnread);
        final idx = _messages.indexWhere((m) => m.id == firstUnread);
        final below = idx >= 0 ? _messages.length - idx - 1 : 0;
        if (below > 0) {
          setState(() {
            _newMessagesBelow = below;
            _showJumpToBottom = true;
          });
        }
      } else {
        _scrollToBottom();
        _scheduleMarkRead();
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
      _newMessagesBelow = 0;
      _suppressMarkRead = false;
    });
    _scheduleMarkRead();
  }

  String _newMessagesChipLabel() {
    final n = _newMessagesBelow;
    if (n <= 0) return '↓ Новые';
    if (n == 1) return '↓ 1 новое';
    if (n >= 10) return '↓ $n новых';
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return '↓ $n новое';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '↓ $n новых';
    }
    return '↓ $n новых';
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
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.35)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.92),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _chatDateSeparatorLabel(date),
          style: TextStyle(
            color: isDark ? Colors.white : scheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
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
    final existing = msg.reactions.where((r) => r.reactedByMe);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _togglePinMessage(ChatMessage msg) async {
    final isPinned = _pinnedMessage?.id == msg.id;
    try {
      await ChatService.pinMessage(
        conversationId: widget.conversationId,
        messageId: msg.id,
        pinned: !isPinned,
      );
      if (!mounted) return;
      setState(() => _pinnedMessage = isPinned ? null : msg);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  void _showReactionPicker(ChatMessage msg) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: _quickReactions
                .map(
                  (emoji) => Material(
                    color: msg.reactions.any(
                      (r) => r.reactedByMe && r.emoji == emoji,
                    )
                        ? Theme.of(ctx).colorScheme.primaryContainer
                        : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleReaction(msg, emoji);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child:
                            Text(emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
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
            icon: Icons.videocam_outlined,
            title: 'Видео-звонок',
            onTap: _startVideoCall,
          ),
          TelegramActionSheetAction(
            icon: Icons.mic_outlined,
            title: 'Голосовая комната',
            onTap: _startVoiceRoom,
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
          if (!isGroup && peer != null)
            TelegramActionSheetAction(
              icon: Icons.block_outlined,
              title: 'Заблокировать',
              destructive: true,
              onTap: _blockPeer,
            ),
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

  void _applyReadReceipt(int readUpToId) {
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
    ActiveChatSession.instance.clearIfOpen(widget.conversationId);
    _scroll.removeListener(_onScrollChanged);
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _presenceTimer?.cancel();
    _typingDebounce?.cancel();
    for (final t in _typingUserTimers.values) {
      t.cancel();
    }
    _typingUserTimers.clear();
    _typingUserIds.clear();
    _inlineDebounce?.cancel();
    _hideInlineOverlay();
    _markReadDebounce?.cancel();
    _markDeliveredDebounce?.cancel();
    _draftSaveDebounce?.cancel();
    _signalSub?.cancel();
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
    for (final t in _failedTextAutoRetryTimers.values) {
      t.cancel();
    }
    _failedTextAutoRetryTimers.clear();
    unawaited(
      ChatCacheService.saveDraft(widget.conversationId, _controller.text),
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

  void _openPeerProfile() {
    final peer = _conversation.peer;
    if (peer != null) _openUserProfile(peer.id);
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

  Widget _incomingMessageAvatar(ChatMessage msg) {
    final user = _userBriefForSender(msg);
    return AppUserAvatar(
      radius: 15,
      imageUrl: user?.avatarUrl,
      displayName: user?.displayName ?? '?',
      onTap: () => _openUserProfile(msg.senderId),
    );
  }

  Future<void> _refreshConversation() async {
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
      setState(() {
        _conversation = conv;
        _pinned = conv.pinned;
        _muted = conv.muted;
        _senderNames = names;
        _groupMembers = members;
      });
      _reconcileSlowModeCooldownWithConversation();
    } catch (_) {}
  }

  Future<void> _forwardMessage(ChatMessage msg) async {
    try {
      final chats = await ChatService.listConversations();
      if (!mounted) return;
      final targets =
          chats.where((c) => c.id != widget.conversationId).toList();
      if (targets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет других чатов для пересылки')),
        );
        return;
      }
      final picked = await showChatTargetPicker(
        context,
        title: 'Переслать в...',
        chats: targets,
      );
      if (picked == null || !mounted) return;
      await _sendForwardTo(picked, msg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Переслано в «${picked.displayTitle}»')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _sendForwardTo(ChatConversation target, ChatMessage msg) async {
    final mediaUrl = msg.mediaUrl?.trim();
    if (msg.type == 'image' && mediaUrl != null && mediaUrl.isNotEmpty) {
      await ChatService.sendImage(
        conversationId: target.id,
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        caption: msg.content.trim(),
      );
      return;
    }
    if (msg.type == 'voice' && mediaUrl != null && mediaUrl.isNotEmpty) {
      await ChatService.sendVoice(
        conversationId: target.id,
        mediaUrl: ServerConfig.resolveVoiceMediaUrl(mediaUrl),
        durationSec: msg.voiceDurationSec ?? 1,
      );
      return;
    }
    if (msg.type == 'file' && mediaUrl != null && mediaUrl.isNotEmpty) {
      await ChatService.sendFile(
        conversationId: target.id,
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        fileName: msg.content.trim().isEmpty ? 'Файл' : msg.content.trim(),
      );
      return;
    }
    if (msg.type == 'video' && mediaUrl != null && mediaUrl.isNotEmpty) {
      await ChatService.sendVideo(
        conversationId: target.id,
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        caption: msg.content.trim(),
      );
      return;
    }
    if (msg.type == 'sticker' && mediaUrl != null && mediaUrl.isNotEmpty) {
      await ChatService.sendSticker(
        conversationId: target.id,
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        emoji: msg.content.trim(),
      );
      return;
    }
    final label = msg.isMine
        ? 'Вы'
        : (msg.senderName ?? _senderNames[msg.senderId] ?? 'Сообщение');
    final body = msg.type == 'voice'
        ? '🎤 Голосовое'
        : msg.type == 'image'
            ? '📷 Фото'
            : msg.type == 'sticker'
                ? '🧩 Стикер'
                : msg.content.trim();
    await ChatService.sendText(
      conversationId: target.id,
      content: '↪ $label: ${body.isEmpty ? 'Сообщение' : body}',
    );
  }

  Future<void> _deleteChat() async {
    if (_conversation.isGroup) {
      await _leaveGroup();
      return;
    }
    if (_chatExitActionRunning) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить чат?'),
        content: Text(
          _conversation.isGroup
              ? 'Вы выйдете из «${_conversation.displayTitle}».'
              : 'Чат исчезнет из списка. При новом сообщении диалог можно начать снова.',
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
    setState(() => _chatExitActionRunning = true);
    try {
      await ChatService.deleteConversation(
          conversationId: widget.conversationId);
      unawaited(ChatCacheService.clearDraft(widget.conversationId));
      try {
        ProviderScope.containerOf(context)
            .read(chatsHubRefreshProvider.notifier)
            .state++;
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _chatExitActionRunning = false);
    }
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

  Future<void> _archiveChat() async {
    try {
      await ChatService.setArchived(
        conversationId: widget.conversationId,
        archived: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
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
                  title: Text(member.displayName),
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

  void _openMediaGallery() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatMediaGalleryScreen(messages: _messages),
      ),
    );
  }

  void _toggleThreadSearch() {
    setState(() {
      _threadSearchOpen = !_threadSearchOpen;
      if (!_threadSearchOpen) {
        _searchBackfillSeq++;
        _searchAutoloading = false;
        _searchBackfillLoads = 0;
        _threadSearchQuery = '';
        _threadSearchFilter = _ThreadSearchFilter.all;
        _threadSearchSenderId = null;
        _searchMatchIndex = 0;
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
    if (msg.type == 'sticker' && 'стикер'.contains(q)) return true;
    if (msg.type == 'file') {
      final name = msg.content.trim().toLowerCase();
      if (name.contains(q) || 'файл'.contains(q)) return true;
    }
    return false;
  }

  bool get _threadSearchHasCriteria {
    return _threadSearchQuery.trim().isNotEmpty ||
        _threadSearchFilter != _ThreadSearchFilter.all ||
        _threadSearchSenderId != null;
  }

  List<int> get _searchMatchIds {
    final sourceMessages = _visibleMessages;
    final q = _threadSearchQuery.trim().toLowerCase();
    if (!_threadSearchHasCriteria) return const [];
    return [
      for (final msg in sourceMessages)
        if (_messageMatchesSearch(msg, q)) msg.id,
    ];
  }

  void _onThreadSearchChanged(String value) {
    final normalized = value.trim().toLowerCase();
    final hasCriteria = normalized.isNotEmpty ||
        _threadSearchFilter != _ThreadSearchFilter.all ||
        _threadSearchSenderId != null;
    setState(() {
      _searchBackfillSeq++;
      _threadSearchQuery = value;
      _searchMatchIndex = 0;
      _searchBackfillLoads = 0;
      if (!hasCriteria) _searchAutoloading = false;
    });
    _scrollToCurrentSearchMatch();
    if (hasCriteria) {
      unawaited(
        _backfillSearchFromHistory(
          normalized,
          _threadSearchFilter,
          _threadSearchSenderId,
        ),
      );
    }
  }

  void _onThreadSearchFilterChanged(_ThreadSearchFilter value) {
    if (_threadSearchFilter == value) return;
    final normalized = _threadSearchQuery.trim().toLowerCase();
    final hasCriteria = normalized.isNotEmpty ||
        value != _ThreadSearchFilter.all ||
        _threadSearchSenderId != null;
    setState(() {
      _searchBackfillSeq++;
      _threadSearchFilter = value;
      _searchMatchIndex = 0;
      _searchBackfillLoads = 0;
      if (!hasCriteria) _searchAutoloading = false;
    });
    _scrollToCurrentSearchMatch();
    if (hasCriteria) {
      unawaited(
        _backfillSearchFromHistory(
          normalized,
          value,
          _threadSearchSenderId,
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
                  title: Text(option.label),
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
        senderId != null;
    setState(() {
      _searchBackfillSeq++;
      _threadSearchSenderId = senderId;
      _searchMatchIndex = 0;
      _searchBackfillLoads = 0;
      if (!hasCriteria) _searchAutoloading = false;
    });
    _scrollToCurrentSearchMatch();
    if (hasCriteria) {
      unawaited(
        _backfillSearchFromHistory(
          normalized,
          _threadSearchFilter,
          senderId,
        ),
      );
    }
  }

  void _scrollToCurrentSearchMatch() {
    final ids = _searchMatchIds;
    if (ids.isEmpty) return;
    final idx = _searchMatchIndex.clamp(0, ids.length - 1);
    _scrollToMessage(ids[idx]);
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
    _scrollToMessage(ids[_searchMatchIndex]);
  }

  void _jumpToFirstSearchMatch() {
    final ids = _searchMatchIds;
    if (ids.isEmpty) return;
    setState(() => _searchMatchIndex = 0);
    _scrollToMessage(ids.first);
  }

  Future<void> _backfillSearchFromHistory(
    String normalizedQuery,
    _ThreadSearchFilter filter,
    int? senderId,
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

  List<ChatMessage> get _visibleMessages {
    if (_showOnlyFailedMessages) {
      final failedMediaTempId = _pendingMediaRetry?.tempId;
      return _messages
          .where((m) =>
              _failedTextSends.containsKey(m.id) ||
              (failedMediaTempId != null && m.id == failedMediaTempId))
          .toList(growable: false);
    }
    return _messages;
  }

  int get _failedPendingItemsCount =>
      _failedTextSends.length + (_pendingMediaRetry != null ? 1 : 0);

  bool _canClusterMessages(ChatMessage a, ChatMessage b) {
    if (a.senderId != b.senderId || a.isMine != b.isMine) return false;
    if (!_isSameChatDay(a.createdAt, b.createdAt)) return false;
    if (a.type == 'poll' || b.type == 'poll') return false;
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

  Future<void> _markUnread() async {
    _markReadDebounce?.cancel();
    try {
      await ChatService.markUnread(conversationId: widget.conversationId);
      if (!mounted) return;
      setState(() => _suppressMarkRead = true);
      try {
        final conv = await ChatService.getConversation(widget.conversationId);
        if (mounted) {
          setState(() => _conversation = conv);
          _reconcileSlowModeCooldownWithConversation();
        }
      } catch (_) {}
      try {
        ProviderScope.containerOf(context)
            .read(chatsHubRefreshProvider.notifier)
            .state++;
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Чат помечен непрочитанным')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    try {
      await ChatService.setPinned(
        conversationId: widget.conversationId,
        pinned: next,
      );
      if (!mounted) return;
      setState(() => _pinned = next);
      try {
        ProviderScope.containerOf(context)
            .read(chatsHubRefreshProvider.notifier)
            .state++;
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    try {
      await ChatService.setMuted(
        conversationId: widget.conversationId,
        muted: next,
      );
      if (!mounted) return;
      setState(() {
        _muted = next;
        _conversation = _conversation.copyWith(muted: next);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _tipPeerWithStars() async {
    final peer = _conversation.peer;
    if (peer == null) return;
    final amountController = TextEditingController(text: '50');
    final messageController = TextEditingController();
    final payload = await showDialog<({int amount, String? message})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Отправить звёзды ${peer.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Количество звёзд',
                hintText: 'например, 50',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: messageController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Сообщение (опционально)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final amount = int.tryParse(amountController.text.trim()) ?? 0;
              if (amount <= 0) return;
              Navigator.pop(
                ctx,
                (
                  amount: amount,
                  message: messageController.text.trim().isEmpty
                      ? null
                      : messageController.text.trim(),
                ),
              );
            },
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    amountController.dispose();
    messageController.dispose();
    if (payload == null) return;
    try {
      final balance = await PaidFeaturesService.donate(
        recipientId: peer.id,
        amountStars: payload.amount,
        message: payload.message,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Отправлено ${payload.amount} звёзд. Баланс: $balance',
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

  void _startVideoCall() {
    final peer = _conversation.peer;
    if (peer == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(contactName: peer.displayName),
      ),
    );
  }

  void _startVoiceRoom() {
    final peer = _conversation.peer;
    if (peer == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceRoomScreen(
          roomName: 'Комната ${peer.displayName}',
          roomId: 'room_${widget.conversationId}',
          isCreator: true,
        ),
      ),
    );
  }

  void _showQuickCallMenu() {
    showTelegramActionSheet<void>(
      context: context,
      title: 'Связь',
      actions: [
        TelegramActionSheetAction(
          icon: Icons.videocam_outlined,
          title: 'Видео-звонок',
          onTap: _startVideoCall,
        ),
        TelegramActionSheetAction(
          icon: Icons.mic_outlined,
          title: 'Голосовая комната',
          onTap: _startVoiceRoom,
        ),
      ],
    );
  }

  Future<void> _blockPeer() async {
    final peer = _conversation.peer;
    if (peer == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Заблокировать?'),
        content: Text(
          '${peer.displayName} не сможет писать вам и видеть ваш профиль в чатах.',
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
    );
    if (ok != true || !mounted) return;
    try {
      await ChatService.blockUser(peer.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
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
            setState(() {
              _conversation = conv;
              _muted = conv.muted;
            });
            _reconcileSlowModeCooldownWithConversation();
          },
          onLeftGroup: () {
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _leaveGroup() async {
    if (_chatExitActionRunning) return;
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
    setState(() => _chatExitActionRunning = true);
    try {
      await ChatService.leaveGroup(conversationId: widget.conversationId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _chatExitActionRunning = false);
    }
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
    if (msg.type == 'voice') return '🎤 Голосовое';
    if (msg.type == 'image') return '📷 Фото';
    if (msg.type == 'video') return '🎬 Видео';
    if (msg.type == 'sticker') return '🧩 Стикер';
    if (msg.type == 'poll') {
      final poll = msg.poll;
      if (poll != null) return chatPollPreviewText(poll);
      return '📊 Опрос';
    }
    if (msg.type == 'file') {
      final name = msg.content.trim();
      return name.isEmpty ? '📎 Файл' : '📎 $name';
    }
    final t = msg.content.trim();
    return t.isEmpty ? 'Сообщение' : t;
  }

  String _formatRecordDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onHoldStart() {
    _holdActive = true;
    unawaited(_startRecording());
  }

  void _onHoldDrag(double dx) {
    if (!_recording || !mounted) return;
    final cancel = dx < -72;
    if (cancel != _recordCancelled) {
      setState(() => _recordCancelled = cancel);
    }
  }

  void _onHoldEnd() {
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
    if (_showVoiceHint) unawaited(_dismissVoiceHint());
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
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordCancelled = false;
      _recordDuration = Duration.zero;
      _waveLevels.clear();
    });
  }

  Future<void> _stopAndSendVoice() async {
    if (!_recording || _voiceSending) return;
    _voiceSending = true;
    _recording = false;
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
      ));
    } finally {
      _voiceSending = false;
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
    final mine = selected.where((m) => m.isMine).toList();
    final skipped = selected.length - mine.length;

    if (mine.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Можно удалить только свои сообщения')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          mine.length == 1
              ? 'Удалить сообщение?'
              : 'Удалить ${mine.length} сообщения?',
        ),
        content: skipped > 0
            ? Text(
                'Чужие сообщения ($skipped) останутся — удаляются только ваши.',
              )
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Удалить',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    for (final msg in mine) {
      await _deleteMessage(msg);
    }
    if (!mounted) return;
    _exitSelectionMode();
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Удалено ${mine.length}, пропущено $skipped')),
      );
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
        .map(_copyableText)
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    if (texts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нечего отправить')),
      );
      return;
    }
    await Share.share(texts);
  }

  Future<void> _forwardSelectedMessages() async {
    final selected = _selectedMessages;
    if (selected.isEmpty) return;
    try {
      final chats = await ChatService.listConversations();
      if (!mounted) return;
      final targets =
          chats.where((c) => c.id != widget.conversationId).toList();
      if (targets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет других чатов для пересылки')),
        );
        return;
      }
      final picked = await showChatTargetPicker(
        context,
        title: 'Переслать в...',
        chats: targets,
      );
      if (picked == null || !mounted) return;
      var sent = 0;
      for (final msg in selected) {
        try {
          await _sendForwardTo(picked, msg);
          sent += 1;
        } catch (_) {}
      }
      if (!mounted) return;
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent == selected.length
                ? 'Переслано $sent в «${picked.displayTitle}»'
                : 'Переслано $sent из ${selected.length} в «${picked.displayTitle}»',
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

  void _handleMessageAction(ChatMessage msg, String action) {
    switch (action) {
      case 'reply':
        setState(() {
          _replyTo = msg;
          _editingMessage = null;
          _controller.clear();
        });
        break;
      case 'copy':
        Clipboard.setData(ClipboardData(text: _copyableText(msg)));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скопировано')),
        );
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
      case 'delete':
        unawaited(_confirmDeleteMessage(msg));
        break;
      case 'select':
        _enterSelectionMode(msg);
        break;
    }
  }

  Future<void> _confirmDeleteMessage(ChatMessage msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Удалить',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _deleteMessage(msg);
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
    VoidCallback? onReplyTap,
    bool interactive = true,
    bool wrapWithAlign = true,
    ValueChanged<int>? onPollVote,
    bool pollVoting = false,
    VoidCallback? onPollClose,
    bool pollClosing = false,
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
          var captionSeen = msg.content.trim().isNotEmpty;
          var i = currentIndex + 1;
          while (i < visible.length &&
              _canMergePhotoAlbum(album.last, visible[i])) {
            final next = visible[i];
            final nextHasCaption = next.content.trim().isNotEmpty;
            if (nextHasCaption && captionSeen) break;
            album.add(next);
            if (nextHasCaption) {
              captionSeen = true;
              break;
            }
            if (album.length >= 8) break;
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
            (_pendingMediaRetry?.tempId == msg.id));
    // Temp ids (< 0) that are not failed = still sending (Telegram clock).
    final isPending = msg.isMine && msg.id < 0 && !isFailed;
    return _Bubble(
      message: msg,
      scheme: scheme,
      isPending: isPending,
      isFailed: isFailed,
      highlightQuery: searching ? _threadSearchQuery : null,
      isActiveSearchMatch: isActiveSearchMatch,
      replyQuote: replyQuote,
      onReplyTap: onReplyTap,
      showSenderName: isGroup && !msg.isMine && cluster.starts,
      senderLabel: msg.senderName ?? _senderNames[msg.senderId],
      onSenderTap:
          isGroup && !msg.isMine ? () => _openUserProfile(msg.senderId) : null,
      isConversationPinned: _pinnedMessage?.id == msg.id,
      cluster: cluster,
      wrapWithAlign: wrapWithAlign,
      onPollVote: onPollVote,
      pollVoting: pollVoting,
      onPollClose: onPollClose,
      pollClosing: pollClosing,
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
      onFileTap: interactive && msg.type == 'file' && msg.mediaUrl != null
          ? () => _openFileUrl(msg.mediaUrl!)
          : null,
    );
  }

  bool _isPhotoAlbumEligible(ChatMessage msg) {
    if (msg.id <= 0) return false;
    if (msg.type != 'image') return false;
    if (msg.replyToMessageId != null) return false;
    final media = msg.mediaUrl?.trim();
    return media != null && media.isNotEmpty;
  }

  bool _canMergePhotoAlbum(ChatMessage left, ChatMessage right) {
    if (!_isPhotoAlbumEligible(left) || !_isPhotoAlbumEligible(right)) {
      return false;
    }
    if (left.content.trim().isNotEmpty) return false;
    if (left.senderId != right.senderId || left.isMine != right.isMine) {
      return false;
    }
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
    final urls = messages
        .map((m) => m.mediaUrl?.trim() ?? '')
        .where((u) => u.isNotEmpty)
        .toList(growable: false);
    if (urls.length < 2) return const SizedBox.shrink();
    final fg = mine && Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : scheme.onSurface;
    final isPending = mine && anchor.id < 0;
    final isFailed = mine &&
        (_failedTextSends.containsKey(anchor.id) ||
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
            imageUrls: urls,
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
                  Text(
                    caption,
                    style: TextStyle(
                      color: fg,
                      height: 1.24,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
    required List<String> imageUrls,
    required BorderRadius borderRadius,
    Widget? footerOverlay,
  }) {
    final spacing = 1.0;
    final displayUrls = imageUrls.take(9).toList(growable: false);
    final count = displayUrls.length;
    if (count < 2) return const SizedBox.shrink();

    Widget tile(String url, {required int index, int? remaining}) {
      return GestureDetector(
        onTap: () => _openImage(url),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _chatAlbumImage(url),
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
            Expanded(child: tile(displayUrls[0], index: 0)),
            SizedBox(width: spacing),
            Expanded(child: tile(displayUrls[1], index: 1)),
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
              child: tile(displayUrls[0], index: 0),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: tile(displayUrls[1], index: 1)),
                  SizedBox(height: spacing),
                  Expanded(child: tile(displayUrls[2], index: 2)),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      final remaining = imageUrls.length - 4;
      body = SizedBox(
        height: 244,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: tile(displayUrls[0], index: 0)),
                  SizedBox(width: spacing),
                  Expanded(child: tile(displayUrls[1], index: 1)),
                ],
              ),
            ),
            SizedBox(height: spacing),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: tile(displayUrls[2], index: 2)),
                  SizedBox(width: spacing),
                  Expanded(
                    child: tile(
                      displayUrls[3],
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
    return CachedNetworkImage(
      imageUrl: resolved,
      fit: BoxFit.cover,
      memCacheWidth: 720,
      memCacheHeight: 720,
      maxWidthDiskCache: 960,
      maxHeightDiskCache: 960,
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
    final bubbleBg = isDark
        ? AppColors.telegramOutgoingDark
        : AppColors.telegramOutgoingLight;
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
    if (_replyTo != null) reserve += bannerRow;
    if (_editingMessage != null) reserve += bannerRow;
    if (_recording) reserve += 96;
    if (_sending) reserve += 40;
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
    final menuItemCount = 4 +
        (msg.isMine && msg.type == 'text' ? 1 : 0) +
        (_copyableText(msg).isNotEmpty ? 1 : 0) +
        (msg.isMine ? 1 : 0) +
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
    final isPinned = _pinnedMessage?.id == msg.id;
    final scheme = Theme.of(context).colorScheme;
    final searching = _threadSearchQuery.trim().isNotEmpty;
    final isGroup = _conversation.isGroup;
    final replyTarget = _replyTargetFor(msg);
    final replyQuote = replyTarget != null
        ? _messagePreview(replyTarget)
        : (msg.replyToMessageId != null ? 'Сообщение' : null);

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
          onReplyTap: null,
          wrapWithAlign: false,
        ),
      ),
      quickReactions: _overlayReactions,
      canEdit: msg.isMine && msg.type == 'text',
      isPinned: isPinned,
      canDelete: msg.isMine,
      hasCopyableText: _copyableText(msg).isNotEmpty,
      onReaction: (emoji) => _toggleReaction(msg, emoji),
      onExpandReactions: () => _showReactionPicker(msg),
      onAction: (action) => _handleMessageAction(msg, action),
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

  Future<void> _deleteMessage(ChatMessage msg) async {
    try {
      await ChatService.deleteMessage(
        conversationId: widget.conversationId,
        messageId: msg.id,
      );
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == msg.id);
        if (_pinnedMessage?.id == msg.id) _pinnedMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
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
    if (!refresh && (_loading || _loadingMore || !_hasMore)) return;
    final seq = ++_messageLoadSeq;
    if (refresh) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final result = await ChatService.listMessages(
        conversationId: widget.conversationId,
        cursor: refresh ? null : _nextCursor,
      );
      if (!mounted || seq != _messageLoadSeq) return;
      setState(() {
        if (refresh) {
          final closedPolls = <int, ChatMessage>{
            for (final m in _messages)
              if (m.type == 'poll' && (m.poll?.isClosed ?? false)) m.id: m,
          };
          _messages
            ..clear()
            ..addAll(
              result.items.map((incoming) {
                final local = closedPolls[incoming.id];
                if (local == null) return incoming;
                return applyIncomingChatMessagePreservingLocalPoll(
                  local,
                  incoming,
                );
              }),
            );
          _pinnedMessage = result.pinnedMessage;
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
    if (_loading || _appPaused || _pollInFlight) return;
    final lastId = _lastServerMessageId();
    if (lastId == null) return;
    _pollInFlight = true;
    try {
      final fresh = await ChatService.listMessagesAfter(
        conversationId: widget.conversationId,
        afterId: lastId,
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
    if (_unreadDividerBeforeId != null || _conversation.unreadCount > 0) {
      setState(() {
        _unreadDividerBeforeId = null;
        _conversation = _conversation.copyWith(unreadCount: 0);
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
        try {
          final msg = await ChatService.sendText(
            conversationId: widget.conversationId,
            content: pending.text,
            replyToMessageId: pending.replyToMessageId,
            clientMessageId: pending.clientMessageId,
          );
          if (!mounted) return;
          _textOutboundQueue.removeAt(0);
          setState(() {
            _clearFailedTextAutoRetry(pending.tempId);
            _integrateMessage(msg, removeTempId: pending.tempId);
            _activateSlowModeCooldownFromNow();
          });
          _scrollToBottom();
          unawaited(
            ChatCacheService.saveThread(widget.conversationId, _messages),
          );
          unawaited(ChatCacheService.clearDraft(widget.conversationId));
        } catch (e) {
          if (!mounted) return;
          final err = e.toString().toLowerCase();
          if (err.contains('group_slow_mode')) {
            _textOutboundQueue.removeAt(0);
            final retryAfter =
                e is ApiClientException ? e.retryAfterSeconds : null;
            pending.lastRetryAfterSeconds =
                (retryAfter ?? _conversation.slowModeSeconds).clamp(1, 3600);
            pending.lastLimitedAt = DateTime.now().toUtc();
            setState(() {
              _failedTextSends[pending.tempId] = pending;
              _activateSlowModeCooldownForSeconds(retryAfter ?? 0);
            });
            _scheduleFailedTextAutoRetry(
              pending,
              retryAfterSeconds: retryAfter ?? _conversation.slowModeSeconds,
              reason: 'slow',
            );
            unawaited(_persistFailedTextSends());
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
            continue;
          }
          if (err.contains('group_flood_limited')) {
            _textOutboundQueue.removeAt(0);
            final retryAfter =
                e is ApiClientException ? e.retryAfterSeconds : null;
            pending.lastRetryAfterSeconds = (retryAfter ?? 60).clamp(1, 3600);
            pending.lastLimitedAt = DateTime.now().toUtc();
            final wait = (retryAfter != null && retryAfter > 0)
                ? ' Подождите ${_formatSlowModeCountdown(retryAfter)}.'
                : '';
            setState(() {
              _failedTextSends[pending.tempId] = pending;
              _activateFloodCooldownForSeconds(retryAfter ?? 0);
            });
            _scheduleFailedTextAutoRetry(
              pending,
              retryAfterSeconds: retryAfter ?? 60,
              reason: 'flood',
            );
            unawaited(_persistFailedTextSends());
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
            continue;
          }
          pending.attempts++;
          // Quick retries only (Telegram-like). Long sleeps made sends feel delayed.
          if (_isRetryableSendError(e) && pending.attempts < 3) {
            final waitMs = pending.attempts == 1 ? 200 : 500;
            await Future<void>.delayed(Duration(milliseconds: waitMs));
            continue;
          }
          _textOutboundQueue.removeAt(0);
          pending.lastRetryAfterSeconds = null;
          pending.lastLimitedAt = null;
          setState(() {
            _failedTextSends[pending.tempId] = pending;
          });
          unawaited(_persistFailedTextSends());
          showErrorSnackBar(context, e);
        }
      }
    } finally {
      _textDrainActive = false;
      if (mounted && _textOutboundQueue.isNotEmpty) {
        unawaited(_drainTextOutboundQueue());
      }
    }
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _recording) return;
    if (_conversation.isGroup &&
        _conversation.amISendRestricted &&
        !_conversation.amIGroupAdmin) {
      final until = _conversation.amISendRestrictedUntil;
      final reason = (_conversation.amISendRestrictionReason ?? '').trim();
      final untilText = until == null
          ? 'без срока'
          : DateFormat('dd.MM.yyyy HH:mm').format(until.toLocal());
      final details = reason.isEmpty ? untilText : '$untilText • $reason';
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
    if (_messages.any(
      (m) => m.isMine && m.id < 0 && m.content == text,
    )) {
      return;
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
    if (_failedTextSends.values.any((p) => p.text == text)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сообщение не отправлено — нажмите «Повторить» ниже'),
          ),
        );
      }
      return;
    }
    final editing = _editingMessage;
    if (editing != null) {
      setState(() => _sending = true);
      _controller.clear();
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
          if (_pinnedMessage?.id == msg.id) _pinnedMessage = msg;
          _editingMessage = null;
          _sending = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _sending = false);
        _controller.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
      return;
    }
    final replyId = _replyTo?.id;
    final uid = AuthService.instance.currentUser?.id ?? 0;
    final clientMessageId = const Uuid().v4();
    _controller.clear();
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final optimistic = ChatMessage(
      id: tempId,
      conversationId: widget.conversationId,
      senderId: uid,
      type: 'text',
      content: text,
      createdAt: DateTime.now(),
      isMine: true,
      replyToMessageId: replyId,
    );
    final pending = _PendingTextSend(
      text: text,
      replyToMessageId: replyId,
      clientMessageId: clientMessageId,
      tempId: tempId,
    );
    setState(() {
      _messages.add(optimistic);
      _replyTo = null;
      _textOutboundQueue.add(pending);
    });
    _scrollToBottom();
    unawaited(_drainTextOutboundQueue());
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

  Future<void> _scheduleCurrentTextMessage() async {
    if (_recording || _editingMessage != null) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;

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
      if (mode == null || !mounted) return;
      if (mode == 'online') {
        sendWhenOnline = true;
        sendAt = DateTime.now().add(const Duration(minutes: 1));
      }
    }
    if (!sendWhenOnline) {
      sendAt = await _pickScheduleDateTime();
      if (sendAt == null || !mounted) return;
      if (!sendAt.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Выберите время минимум на 30 секунд позже'),
          ),
        );
        return;
      }
    }

    try {
      final item = await ChatService.scheduleText(
        conversationId: widget.conversationId,
        content: text,
        sendAt: sendAt!,
        sendWhenOnline: sendWhenOnline,
        replyToMessageId: _replyTo?.id,
        clientMessageId: const Uuid().v4(),
      );
      if (!mounted) return;
      setState(() {
        _controller.clear();
        _replyTo = null;
      });
      final when = DateFormat('dd.MM HH:mm').format(item.sendAt);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item.sendWhenOnline
                ? 'Сообщение будет отправлено, когда собеседник онлайн'
                : 'Сообщение запланировано на $when',
          ),
        ),
      );
      unawaited(_refreshScheduledPendingCount());
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e,
          fallback: 'Не удалось запланировать сообщение');
    }
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
              final pending = items.where((e) => e.status == 'pending').toList()
                ..sort((a, b) => a.sendAt.compareTo(b.sendAt));
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
                            final preview = item.content.trim().isEmpty
                                ? item.type.toUpperCase()
                                : item.content.trim();
                            return ListTile(
                              title: Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                item.sendWhenOnline
                                    ? 'Отправка: когда пользователь онлайн'
                                    : 'Отправка: ${DateFormat('dd.MM.yyyy HH:mm').format(item.sendAt)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                                    tooltip: 'Отменить',
                                    onPressed: () async {
                                      try {
                                        await ChatService
                                            .cancelScheduledMessage(
                                          conversationId: widget.conversationId,
                                          scheduledMessageId: item.id,
                                        );
                                        setModalState(
                                          () => items.removeWhere(
                                              (e) => e.id == item.id),
                                        );
                                      } catch (e) {
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
      setState(() => _scheduledPendingCount = items.length);
    } catch (_) {
      // Silent: this is a decorative badge.
    }
  }

  void _openImage(String url) {
    final urls = _messages
        .where(
          (m) =>
              (m.type == 'image' || _canOpenStickerInImageViewer(m)) &&
              (m.mediaUrl?.isNotEmpty ?? false),
        )
        .map((m) => m.mediaUrl!)
        .toList(growable: false);
    final index = urls.indexOf(url);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FullscreenImageViewer(
          imageUrls: urls.isEmpty ? [url] : urls,
          initialIndex: index >= 0 ? index : 0,
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ChatVideoPlayerPage(videoUrl: url),
      ),
    );
  }

  Future<void> _showAttachMenu() async {
    if (_recording) return;
    final selection = await showChatAttachSheet(context);
    if (!mounted || selection == null) return;
    switch (selection.kind) {
      case ChatAttachResult.galleryFiles:
        await _sendGallerySelection(selection.galleryFiles);
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
    }
  }

  Future<void> _sendStickerByUrl(String mediaUrl, {String? emoji}) async {
    try {
      await ChatService.sendSticker(
        conversationId: widget.conversationId,
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        emoji: (emoji ?? '').trim(),
        replyToMessageId: _replyTo?.id,
      );
      _controller.clear();
      setState(() => _replyTo = null);
      AppHaptics.selection();
      await _pollNew();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _sendGallerySelection(List<XFile> files) async {
    if (files.isEmpty) return;
    for (final file in files) {
      if (!mounted) return;
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
        await _sendPickedVideo(await _normalizeVideoFileForUpload(file));
      } else {
        await _sendPickedImage(file);
      }
    }
  }

  Future<void> _sendContact(ChatContact contact) async {
    if (_sending || _recording) return;
    final user = contact.user;
    final lines = <String>['👤 Контакт', user.displayName];
    final username = user.username?.trim();
    if (username != null && username.isNotEmpty) {
      lines.add(username.startsWith('@') ? username : '@$username');
    }
    await _sendContactText(lines.join('\n'));
  }

  Future<void> _sendPhoneContact({
    required String displayName,
    required String phoneE164,
  }) async {
    if (_sending || _recording) return;
    final lines = <String>['👤 Контакт', displayName.trim(), phoneE164.trim()];
    await _sendContactText(lines.join('\n'));
  }

  Future<void> _sendContactText(String text) async {
    _beginSending(status: 'Отправка контакта…');
    try {
      final msg = await ChatService.sendText(
        conversationId: widget.conversationId,
        content: text,
        replyToMessageId: _replyTo?.id,
      );
      if (!mounted) return;
      setState(() {
        _integrateMessage(msg);
        _replyTo = null;
      });
      _endSending();
      _scrollToBottom();
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    } catch (e) {
      if (!mounted) return;
      _endSending();
      showErrorSnackBar(context, e, fallback: 'Не удалось отправить контакт');
    }
  }

  Future<void> _createAndSendPoll() async {
    if (_sending || _recording) return;
    final draft = await CreateChatPollSheet.show(context);
    if (!mounted || draft == null) return;
    await _sendPollDraft(draft);
  }

  Future<void> _sendPollDraft(ChatPollDraft draft) async {
    if (_sending || _recording) return;
    _beginSending(status: 'Отправка опроса…');
    try {
      final msg = await ChatService.sendPoll(
        conversationId: widget.conversationId,
        question: draft.question,
        description: draft.description,
        options: draft.options,
        settings: draft.settings.toJson(),
        replyToMessageId: _replyTo?.id,
      );
      if (!mounted) return;
      setState(() {
        _integrateMessage(msg);
        _replyTo = null;
      });
      _endSending();
      _scrollToBottom();
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    } catch (e) {
      if (!mounted) return;
      _endSending();
      showErrorSnackBar(context, e, fallback: 'Не удалось отправить опрос');
    }
  }

  Future<void> _resendStoredFile({
    required String name,
    required String mediaUrl,
  }) async {
    if (_sending || _recording) return;
    _beginSending(status: 'Отправка…');
    try {
      final msg = await ChatService.sendFile(
        conversationId: widget.conversationId,
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        fileName: name,
        replyToMessageId: _replyTo?.id,
      );
      if (!mounted) return;
      setState(() {
        _integrateMessage(msg);
        _replyTo = null;
      });
      _endSending();
      _scrollToBottom();
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    } catch (e) {
      if (!mounted) return;
      _endSending();
      showErrorSnackBar(context, e, fallback: 'Не удалось отправить файл');
    }
  }

  Future<void> _votePoll(ChatMessage msg, int optionIndex) async {
    if (_votingPollIds.contains(msg.id)) return;
    setState(() => _votingPollIds.add(msg.id));
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
    setState(() => _closingPollIds.add(msg.id));
    try {
      final updated = await ChatService.closePoll(
        conversationId: widget.conversationId,
        messageId: msg.id,
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i >= 0) _messages[i] = updated;
        if (_pinnedMessage?.id == msg.id) _pinnedMessage = updated;
      });
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e, fallback: 'Не удалось закрыть опрос');
      }
    } finally {
      if (mounted) setState(() => _closingPollIds.remove(msg.id));
    }
  }

  Future<void> _tapInlineButton(
    ChatMessage msg,
    ChatInlineKeyboardButton button,
  ) async {
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
      totalBytes: totalBytes,
      previewBytes: previewBytes,
      payloadBytes: previewBytes,
    ));
  }

  Future<void> _sendPickedVideo(
    XFile file, {
    int? replyToId,
    String? clientMessageId,
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
      totalBytes: totalBytes,
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
    ));
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
      subtitle = formatLastSeen(peer.lastSeenAt);
    }
    if (_muted &&
        subtitle.isNotEmpty &&
        !subtitle.startsWith('соединение') &&
        !subtitle.startsWith('обновление') &&
        !subtitle.startsWith('Ожидание')) {
      subtitle = '$subtitle · без звука';
    } else if (_muted && subtitle.isEmpty) {
      subtitle = 'без звука';
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
    final canSendInGroup = !(_conversation.isGroup &&
            _conversation.onlyAdminsCanPost &&
            !_conversation.amIGroupAdmin) &&
        !isRestrictedByModeration;
    String formatSlowMode(int seconds) {
      if (seconds <= 0) return 'выкл';
      if (seconds < 60) return '$seconds сек';
      if (seconds % 60 == 0) return '${seconds ~/ 60} мин';
      return '${seconds ~/ 60}м ${seconds % 60}с';
    }

    final showPostingLimitsHint = _conversation.isGroup &&
        canSendInGroup &&
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
    final canSendNow = canSendInGroup && activeCooldownSeconds <= 0;
    final nextManualRetryRemainingSeconds = _nextManualRetryRemainingSeconds;
    final manualReadyRetryRemainingSeconds = _manualReadyRetryRemainingSeconds;
    final showRetryAllReadyHint = !_retryAllBulkBusy &&
        nextManualRetryRemainingSeconds != null &&
        nextManualRetryRemainingSeconds > 8;
    final hasReadyManualRetryItems = !_retryAllBulkBusy &&
        (nextManualRetryRemainingSeconds == null ||
            nextManualRetryRemainingSeconds <= 0);
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
                leading: TextButton(
                  onPressed: _exitSelectionMode,
                  child: const Text('Отмена'),
                ),
                title: Text(
                  _selectedMessageIds.length == 1
                      ? 'Выбрано 1'
                      : 'Выбрано ${_selectedMessageIds.length}',
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
                          : _openPeerProfile,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      if (!isSaved && !isGroup && peer != null) ...[
                        AppUserAvatar(
                          radius: 18,
                          imageUrl: peer.avatarUrl,
                          displayName: peer.displayName,
                          onTap: _openPeerProfile,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _conversation.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.1,
                                  ),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: subtitleStyle?.copyWith(fontSize: 12),
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
                                              label: Text(_searchSenderLabel()),
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
                    tooltip: 'Отложенные',
                    icon: const Icon(Icons.schedule_outlined),
                    onPressed: _openScheduledMessagesManager,
                  ),
                  if (!isGroup && peer != null) ...[
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
        body: AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: keyboardInset),
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
                            ? const Color(0xB3202630)
                            : scheme.surfaceContainerHighest,
                        child: InkWell(
                          onTap: () => _scrollToMessage(_pinnedMessage!.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Row(
                              children: [
                                Icon(Icons.push_pin,
                                    size: 16, color: scheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Закреплённое сообщение',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                          .brightness ==
                                                      Brightness.dark
                                                  ? Colors.white70
                                                  : scheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      Text(
                                        _pinnedPreview(_pinnedMessage!),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Открепить',
                                  icon: const Icon(Icons.close, size: 18),
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
                                    return TextButton(
                                      onPressed: _loadingMore
                                          ? null
                                          : () => _load(refresh: false),
                                      child: _loadingMore
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Загрузить раньше'),
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
                                  final selected =
                                      _selectedMessageIds.contains(msg.id);
                                  final failed =
                                      _failedTextSends.containsKey(msg.id) ||
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
                                            Row(
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
                                                            onHorizontalDragEnd:
                                                                _selectionMode
                                                                    ? null
                                                                    : (details) {
                                                                        final v =
                                                                            details.primaryVelocity;
                                                                        if (v ==
                                                                                null ||
                                                                            v.abs() <
                                                                                320) {
                                                                          return;
                                                                        }
                                                                        setState(
                                                                          () {
                                                                            _replyTo =
                                                                                msg;
                                                                            _editingMessage =
                                                                                null;
                                                                            _controller.clear();
                                                                          },
                                                                        );
                                                                        _inputFocusNode
                                                                            .requestFocus();
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
                                                            child: Opacity(
                                                              opacity: failed
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
                                                                            .isClosed)
                                                                    ? () =>
                                                                        _closePoll(
                                                                            msg)
                                                                    : null,
                                                                pollClosing:
                                                                    _closingPollIds
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
                    if (_showJumpToBottom && !_selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            begin: 0.96,
                            end: _newMessagesBelow > 0 ? 1.0 : 0.985,
                          ),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          child: Material(
                            elevation: 2,
                            borderRadius: BorderRadius.circular(20),
                            color: _telegramAccent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _jumpToBottomAndMarkRead,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.25),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                                  child: Text(
                                    _newMessagesBelow > 0
                                        ? _newMessagesChipLabel()
                                        : '↓ Вниз',
                                    key: ValueKey<int>(_newMessagesBelow),
                                    style: TextStyle(
                                      color: scheme.onPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          builder: (context, value, child) => Transform.scale(
                            scale: value,
                            child: child,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_selectionMode)
                ChatMessageSelectionToolbar(
                  enabled: _selectedMessageIds.isNotEmpty,
                  onDelete: _deleteSelectedMessages,
                  onCopy: _copySelectedMessages,
                  onShare: _shareSelectedMessages,
                  onForward: _forwardSelectedMessages,
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
                        if (_isAutoRetryActive && !_sending)
                          _composerInfoBanner(
                            backgroundColor: scheme.secondaryContainer
                                .withValues(alpha: 0.42),
                            foregroundColor: scheme.onSecondaryContainer,
                            icon: _autoRetryReasonIcon,
                            title: _autoRetryPendingCount > 1
                                ? 'Автоповтор активен для $_autoRetryPendingCount сообщений'
                                : 'Автоповтор активен',
                            subtitle:
                                'Причина: $_autoRetryReasonLabel • следующая попытка через '
                                '${_formatSlowModeCountdown(_autoRetryRemainingSeconds)}',
                            trailing: Wrap(
                              spacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer
                                        .withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Режим: авто',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => unawaited(
                                    _toggleAutoRetryOnLimitsInThread(false),
                                  ),
                                  child: const Text('Отключить'),
                                ),
                              ],
                            ),
                          ),
                        if (!_autoRetryOnLimitsEnabled &&
                            _hasFailedPendingItems &&
                            !_sending)
                          _composerInfoBanner(
                            backgroundColor:
                                scheme.tertiaryContainer.withValues(alpha: 0.4),
                            foregroundColor: scheme.onTertiaryContainer,
                            icon: Icons.pause_circle_outline,
                            title: 'Автоповтор выключен',
                            subtitle:
                                'Неотправленные элементы ожидают ручного повтора'
                                '\nТекст: ${_failedTextSends.length} • Медиа: ${_pendingMediaRetry != null ? 1 : 0}'
                                '${retryBulkProgressLabel != null ? '\nПакетный повтор: $retryBulkProgressLabel' : ''}'
                                '${_retryAllBulkCancelRequested ? '\nОстановка после текущего элемента…' : ''}'
                                '${_clearAllAfterBulkStopRequested ? '\nПосле остановки откроется очистка…' : ''}'
                                '${manualReadyRetryRemainingSeconds > 0 ? '\nАвтозапуск готовых через ${_formatSlowModeCountdown(manualReadyRetryRemainingSeconds)}' : ''}'
                                '${nextManualRetryRemainingSeconds != null ? '\nБлижайшая готовность: через ${_formatSlowModeCountdown(nextManualRetryRemainingSeconds)}' : ''}',
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                TextButton(
                                  onPressed: (_sending || _retryAllBulkBusy)
                                      ? null
                                      : _retryAllFailedPendingWithGuard,
                                  style: showRetryAllReadyHint
                                      ? TextButton.styleFrom(
                                          foregroundColor: scheme.primary,
                                        )
                                      : null,
                                  child: Text(
                                    _retryAllBulkBusy
                                        ? 'Повтор: ${retryBulkProgressLabel ?? '…'}'
                                        : showRetryAllReadyHint
                                            ? 'Повторить через ${_formatSlowModeCountdown(nextManualRetryRemainingSeconds)}'
                                            : 'Повторить все',
                                  ),
                                ),
                                if (_retryAllBulkBusy)
                                  TextButton(
                                    onPressed: _cancelRetryAllBulk,
                                    child: Text(
                                      _retryAllBulkCancelRequested
                                          ? 'Останавливаем...'
                                          : 'Остановить',
                                    ),
                                  ),
                                TextButton(
                                  onPressed: (_sending || _retryAllBulkBusy)
                                      ? null
                                      : _retryReadyFailedPending,
                                  style: hasReadyManualRetryItems
                                      ? TextButton.styleFrom(
                                          foregroundColor: scheme.primary,
                                        )
                                      : null,
                                  child: const Text('Повторить готовые'),
                                ),
                                if (manualReadyRetryRemainingSeconds > 0)
                                  TextButton(
                                    onPressed: (_sending || _retryAllBulkBusy)
                                        ? null
                                        : _cancelManualReadyRetrySchedule,
                                    child: const Text('Отменить автозапуск'),
                                  ),
                                TextButton(
                                  onPressed: (_sending || _retryAllBulkBusy)
                                      ? null
                                      : _clearAllFailedPending,
                                  child: const Text('Очистить'),
                                ),
                                TextButton(
                                  onPressed: (_sending || _retryAllBulkBusy)
                                      ? null
                                      : () => _setShowOnlyFailedMessages(
                                            !_showOnlyFailedMessages,
                                          ),
                                  child: Text(
                                    _showOnlyFailedMessages
                                        ? 'Показать все'
                                        : 'Показать в чате',
                                  ),
                                ),
                                TextButton(
                                  onPressed: (_sending || _retryAllBulkBusy)
                                      ? null
                                      : () => unawaited(
                                            _toggleAutoRetryOnLimitsInThread(
                                                true),
                                          ),
                                  child: const Text('Включить'),
                                ),
                              ],
                            ),
                          ),
                        if (_sending && _uploadProgress != null)
                          _uploadTickerBar(scheme),
                        if (_pendingMediaRetry != null &&
                            !_pendingMediaByTempId
                                .containsKey(_pendingMediaRetry!.tempId))
                          _pendingMediaRetryBanner(scheme),
                        _animatedVisibility(
                          visible: _showVoiceHint && !_recording && !_sending,
                          keyName: 'voice-hint',
                          child: _composerInfoBanner(
                            backgroundColor: scheme.tertiaryContainer
                                .withValues(alpha: 0.45),
                            foregroundColor: scheme.onTertiaryContainer,
                            icon: Icons.mic_none_rounded,
                            title:
                                'Удерживайте кнопку микрофона для голосового',
                            trailing: IconButton(
                              tooltip: 'Скрыть',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: _dismissVoiceHint,
                            ),
                          ),
                        ),
                        _animatedVisibility(
                          visible: _editingMessage != null,
                          keyName: 'edit-banner',
                          child: _editingMessage == null
                              ? const SizedBox.shrink()
                              : _composerInfoBanner(
                                  backgroundColor: scheme.primaryContainer
                                      .withValues(alpha: 0.35),
                                  foregroundColor: scheme.onPrimaryContainer,
                                  icon: Icons.edit_outlined,
                                  title: 'Редактирование',
                                  subtitle: _editingMessage!.content,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: _cancelEdit,
                                  ),
                                ),
                        ),
                        _animatedVisibility(
                          visible: _replyTo != null,
                          keyName: 'reply-banner',
                          child: _replyTo == null
                              ? const SizedBox.shrink()
                              : _composerInfoBanner(
                                  backgroundColor:
                                      scheme.surfaceContainerHighest,
                                  icon: Icons.reply_rounded,
                                  title: _replyTo!.isMine
                                      ? 'Вы'
                                      : (_replyTo!.senderName ??
                                          _senderNames[_replyTo!.senderId] ??
                                          _conversation.displayTitle),
                                  subtitle: _messagePreview(_replyTo!),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () =>
                                        setState(() => _replyTo = null),
                                  ),
                                ),
                        ),
                        _animatedVisibility(
                          visible: _recording,
                          keyName: 'record-banner',
                          child: Material(
                            color: _recordCancelled
                                ? scheme.errorContainer.withValues(alpha: 0.5)
                                : scheme.primaryContainer
                                    .withValues(alpha: 0.35),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _recordCancelled
                                        ? '← Отпустите для отмены'
                                        : 'Отпустите для отправки',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: _recordCancelled
                                              ? scheme.error
                                              : scheme.onSurface,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  ChatVoiceWaveform(
                                    levels: List<double>.from(_waveLevels),
                                    color: scheme.onSurfaceVariant,
                                    activeColor: scheme.primary,
                                    barCount: 32,
                                    height: 32,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _formatRecordDuration(_recordDuration),
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            ),
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
                          visible: showPostingLimitsHint,
                          keyName: 'group-posting-limits-banner',
                          child: _composerInfoBanner(
                            backgroundColor:
                                scheme.tertiaryContainer.withValues(alpha: 0.4),
                            foregroundColor: scheme.onTertiaryContainer,
                            icon: activeCooldownIcon,
                            title: postingLimitsHint,
                            onTap: () => _showPostingLimitsInfo(
                              floodCooldownActive: floodCooldownActive,
                              activeCooldownSeconds: activeCooldownSeconds,
                            ),
                          ),
                        ),
                        _animatedVisibility(
                          visible: !canSendNow && canSendInGroup,
                          keyName: 'group-active-cooldown-banner',
                          child: _composerInfoBanner(
                            backgroundColor:
                                scheme.tertiaryContainer.withValues(alpha: 0.6),
                            foregroundColor: scheme.onTertiaryContainer,
                            icon: activeCooldownIcon,
                            title:
                                '$activeCooldownLabel: временная пауза перед отправкой',
                            subtitle:
                                'Можно отправить через ${_formatSlowModeCountdown(activeCooldownSeconds)}',
                            onTap: () => _showPostingLimitsInfo(
                              floodCooldownActive: floodCooldownActive,
                              activeCooldownSeconds: activeCooldownSeconds,
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: AnimatedContainer(
                            duration: _uiAnimDuration,
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const Color(0xCC1A2632)
                                  : scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: (_recording || !canSendNow)
                                      ? null
                                      : _showAttachMenu,
                                  icon: const Icon(Icons.attach_file_outlined),
                                  tooltip: 'Вложение',
                                  color: scheme.onSurfaceVariant,
                                  iconSize: _composerIconSize,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: _composerButtonSide,
                                    height: _composerButtonSide,
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _inputFocusNode,
                                    enabled: !_recording && canSendInGroup,
                                    minLines: 1,
                                    maxLines: 5,
                                    textInputAction: TextInputAction.send,
                                    scrollPadding:
                                        const EdgeInsets.only(bottom: 96),
                                    onSubmitted: (_) =>
                                        _hasText ? _sendText() : null,
                                    decoration: InputDecoration(
                                      hintText: _recording
                                          ? 'Удерживайте микрофон…'
                                          : (!canSendInGroup
                                              ? (isRestrictedByModeration
                                                  ? 'Ваши сообщения временно ограничены'
                                                  : 'В этой группе писать могут только админы')
                                              : (activeCooldownSeconds > 0
                                                  ? '$activeCooldownLabel: подождите ${_formatSlowModeCountdown(activeCooldownSeconds)}'
                                                  : (_editingMessage != null
                                                      ? 'Изменить сообщение'
                                                      : (_hasText
                                                          ? 'Сообщение'
                                                          : 'Сообщение или голосовое')))),
                                      filled: true,
                                      fillColor: Colors.transparent,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                    ),
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
                                  child: (_hasText && !_recording)
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
                                            icon: _sending
                                                ? SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : (activeCooldownSeconds > 0
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
                                                      )),
                                          ),
                                        )
                                      : ChatVoiceMicButton(
                                          key: const ValueKey('mic-btn'),
                                          enabled: !_sending && canSendNow,
                                          recording: _recording,
                                          onHoldStart: _onHoldStart,
                                          onHoldEnd: _onHoldEnd,
                                          onHoldDragDx: _onHoldDrag,
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
    );
  }
}

enum _PendingMediaKind { image, video, file, voice }

class _CancelledPendingMediaException implements Exception {}

class _PendingMediaSend {
  _PendingMediaSend({
    required this.tempId,
    required this.kind,
    required this.file,
    required this.clientMessageId,
    this.fileName,
    this.replyToMessageId,
    this.voiceDurationSec,
    this.totalBytes,
    this.previewBytes,
    this.payloadBytes,
  });

  final int tempId;
  final _PendingMediaKind kind;
  final XFile file;
  final String clientMessageId;
  final String? fileName;
  final int? replyToMessageId;
  final int? voiceDurationSec;
  final int? totalBytes;
  final Uint8List? previewBytes;
  /// Full bytes for Hive outbox / reload retry (web-safe).
  Uint8List? payloadBytes;
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
  });

  final String text;
  final String clientMessageId;
  final int tempId;
  final int? replyToMessageId;
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
    this.highlightQuery,
    this.isActiveSearchMatch = false,
    this.replyQuote,
    this.onReplyTap,
    this.showSenderName = false,
    this.senderLabel,
    this.onSenderTap,
    this.isConversationPinned = false,
    this.onImageTap,
    this.onVideoTap,
    this.onFileTap,
    this.onReactionTap,
    this.wrapWithAlign = true,
    this.cluster = const _MessageCluster.single(),
    this.onPollVote,
    this.pollVoting = false,
    this.onPollClose,
    this.pollClosing = false,
    this.onInlineButtonTap,
    this.callbackLoadingData = const <String>{},
  });

  final ChatMessage message;
  final ColorScheme scheme;
  /// Still sending to server (Telegram clock icon).
  final bool isPending;
  /// Send failed (tap to retry).
  final bool isFailed;
  final String? highlightQuery;
  final bool isActiveSearchMatch;
  final String? replyQuote;
  final VoidCallback? onReplyTap;
  final bool showSenderName;
  final String? senderLabel;
  final VoidCallback? onSenderTap;
  final bool isConversationPinned;
  final VoidCallback? onImageTap;
  final VoidCallback? onVideoTap;
  final VoidCallback? onFileTap;
  final ValueChanged<String>? onReactionTap;
  final bool wrapWithAlign;
  final _MessageCluster cluster;
  final ValueChanged<int>? onPollVote;
  final bool pollVoting;
  final VoidCallback? onPollClose;
  final bool pollClosing;
  final ValueChanged<ChatInlineKeyboardButton>? onInlineButtonTap;
  final Set<String> callbackLoadingData;

  double _metaReserveWidth(bool mine) {
    var width = 42.0; // time
    if (message.isEdited) width += 28;
    if (isConversationPinned) width += 16;
    if (mine) width += 16; // single/double check mark area
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
        Text(
          formatChatMessageTime(message.createdAt),
          style: TextStyle(color: timeColor, fontSize: 10.5, height: 1.08),
        ),
        if (message.isEdited) ...[
          const SizedBox(width: 3),
          Text(
            'изм.',
            style: TextStyle(
              color: editedColor,
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
              height: 1.08,
            ),
          ),
        ],
        if (mine) ...[
          const SizedBox(width: 3),
          Icon(
            statusIcon,
            size: 12.5,
            color: statusColor,
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
  }) {
    if (!onMedia) {
      // IntrinsicWidth keeps short texts tight (Telegram). A plain Align
      // inside Column expands to the parent's max width → huge empty bubbles.
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
                child: _messageMeta(fg: fg, mine: mine, onMedia: false),
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
          child: _messageMeta(fg: fg, mine: mine, onMedia: onMedia),
        ),
      ],
    );
  }

  Widget _buildReactions(Color fg, Color quoteBg) {
    if (message.reactions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: message.reactions
            .where((r) => r.emoji.isNotEmpty && r.count > 0)
            .map(
              (r) => Material(
                color: r.reactedByMe
                    ? scheme.primary.withValues(alpha: 0.18)
                    : quoteBg,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onReactionTap == null
                      ? null
                      : () => onReactionTap!(r.emoji),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      '${r.emoji} ${r.count}',
                      style: TextStyle(color: fg, fontSize: 12),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildReplyQuote(Color fg, Color quoteBg) {
    if (replyQuote == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onReplyTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: quoteBg,
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(color: scheme.primary, width: 3),
              ),
            ),
            child: HighlightedText(
              text: replyQuote!,
              query: highlightQuery,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg.withValues(alpha: 0.85),
                fontSize: 13,
              ),
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
                              ((btn.callbackData == null ||
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
                          Text(btn.text),
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
        ? (isDark
            ? AppColors.telegramOutgoingDark
            : AppColors.telegramOutgoingLight)
        : (isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest);
    final fg = mine && isDark ? Colors.white : scheme.onSurface;
    final quoteBg = mine
        ? scheme.primary.withValues(alpha: 0.12)
        : scheme.onSurface.withValues(alpha: 0.06);

    final isImage = message.type == 'image' && message.mediaUrl != null;
    final isVideo = message.type == 'video' && message.mediaUrl != null;
    final isSticker = message.type == 'sticker' && message.mediaUrl != null;
    final isMedia = isImage || isVideo || isSticker;
    final hasCaption = message.content.trim().isNotEmpty;
    final isFullBleedMedia = (isImage || isVideo) && !hasCaption;
    final bubbleRadius = _bubbleRadius(mine);
    final contentPadding =
        isMedia ? EdgeInsets.zero : const EdgeInsets.fromLTRB(8, 4, 8, 3);
    final bubbleNeedsBackground = !isFullBleedMedia ||
        replyQuote != null ||
        (showSenderName && (senderLabel?.isNotEmpty ?? false)) ||
        message.reactions.isNotEmpty;
    final activeBorderColor = scheme.primary.withValues(alpha: 0.75);
    final activeShadowColor = scheme.primary.withValues(alpha: 0.28);

    Widget mainContent;
    if (message.type == 'voice' && message.mediaUrl != null) {
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: ChatVoiceBubble(
          message: message,
          foregroundColor: fg,
          accentColor: scheme.primary,
          activeColor: mine ? scheme.primary : scheme.secondary,
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
      final image = GestureDetector(
        onTap: onImageTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: CachedNetworkImage(
            imageUrl: ServerConfig.resolvePublisherAvatarUrl(
              ServerConfig.resolveMediaUrl(message.mediaUrl!),
            ),
            fit: BoxFit.cover,
            memCacheWidth: 720,
            memCacheHeight: 720,
            maxWidthDiskCache: 960,
            maxHeightDiskCache: 960,
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
                child: HighlightedText(
                  text: message.content,
                  query: highlightQuery,
                  style: TextStyle(color: fg, height: 1.25),
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
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        onMedia: true,
        child: sticker,
      );
    } else if (isVideo) {
      final video = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: InlineVideoPlayer(
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
                child: HighlightedText(
                  text: message.content,
                  query: highlightQuery,
                  style: TextStyle(color: fg, height: 1.25),
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
      mainContent = _withBottomMeta(
        fg: fg,
        mine: mine,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            HighlightedText(
              text: message.content,
              query: highlightQuery,
              style: TextStyle(color: fg, height: 1.22, fontSize: 15.5),
            ),
            if (extractFirstHttpUrl(message.content) case final url?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ChatLinkPreview(
                  url: url,
                  foregroundColor: fg,
                  accentColor: scheme.primary,
                  backgroundColor: quoteBg,
                ),
              ),
          ],
        ),
      );
    } else {
      mainContent = Align(
        alignment: Alignment.centerRight,
        child: _messageMeta(fg: fg, mine: mine),
      );
    }

    final bubble = Container(
      margin: EdgeInsets.only(
        top: cluster.starts ? 2 : 0.5,
        bottom: cluster.ends ? 2 : 0.5,
      ),
      padding:
          isMedia ? contentPadding : const EdgeInsets.fromLTRB(8, 4, 7, 3),
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
              padding: isMedia
                  ? const EdgeInsets.fromLTRB(8, 5, 8, 0)
                  : EdgeInsets.zero,
              child: onSenderTap != null
                  ? GestureDetector(
                      onTap: onSenderTap,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        senderLabel!,
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : Text(
                      senderLabel!,
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            SizedBox(height: isMedia ? 4 : 4),
          ],
          if (replyQuote != null)
            Padding(
              padding: isMedia
                  ? const EdgeInsets.fromLTRB(8, 5, 8, 0)
                  : EdgeInsets.zero,
              child: _buildReplyQuote(fg, quoteBg),
            ),
          mainContent,
          _buildInlineKeyboard(fg, quoteBg),
          Padding(
            padding: isMedia
                ? const EdgeInsets.fromLTRB(8, 0, 8, 4)
                : EdgeInsets.zero,
            child: _buildReactions(fg, quoteBg),
          ),
        ],
      ),
    );

    if (!wrapWithAlign) return bubble;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }
}

class _ChatVideoPlayerPage extends StatefulWidget {
  const _ChatVideoPlayerPage({required this.videoUrl});

  final String videoUrl;

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
