import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/haptics/app_haptics.dart';
import '../../../core/network/feed_load_helper.dart';
import '../../../models/chat_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/api_reachability_service.dart';
import '../../../services/chat_cache_service.dart';
import '../../../services/chat_service.dart';
import '../../../services/chat_stream_service.dart';
import '../../../utils/chat_time_format.dart';
import '../../../utils/api_error_parser.dart';
import '../../../utils/session_snackbar.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/chat_link_preview.dart';
import '../../../widgets/fullscreen_image_viewer.dart';
import '../../../widgets/highlighted_text.dart';
import '../application/active_chat_session.dart';
import '../application/chat_realtime_signals.dart';
import '../application/chats_hub_refresh_provider.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/server_config.dart';
import '../../../services/chat_hub_ui_prefs.dart';
import '../../../utils/presence_format.dart';
import '../../../utils/video_player_helper.dart';
import '../../../widgets/inline_video_player.dart';
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
import 'chat_voice_bubble.dart';

/// Загружает чат с API, если не передан в [extra] (push / deep link).
class ChatThreadLoaderScreen extends ConsumerStatefulWidget {
  const ChatThreadLoaderScreen({
    super.key,
    required this.conversationId,
    this.initialConversation,
    this.initialPeer,
  });

  final int conversationId;
  final ChatConversation? initialConversation;
  final ChatUserBrief? initialPeer;

  @override
  ConsumerState<ChatThreadLoaderScreen> createState() =>
      _ChatThreadLoaderScreenState();
}

class _ChatThreadLoaderScreenState extends ConsumerState<ChatThreadLoaderScreen> {
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
      ),
    );
  }
}

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversation,
  });

  final ChatConversation conversation;

  int get conversationId => conversation.id;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _threadSearchController = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _loadError;
  bool _sending = false;
  double? _uploadProgress;
  String _sendingStatus = 'Отправка…';
  final Map<int, _PendingTextSend> _failedTextSends = {};
  _PendingMediaSend? _pendingMediaRetry;
  bool _showVoiceHint = false;
  bool _hasMore = false;
  int? _nextCursor;
  Timer? _pollTimer;
  Timer? _presenceTimer;
  Timer? _typingDebounce;
  Timer? _peerTypingClear;
  StreamSubscription<void>? _signalSub;
  VoidCallback? _apiReachabilityListener;
  ChatStreamService? _stream;
  ChatMessage? _replyTo;
  bool _appPaused = false;
  bool _sseConnected = false;
  bool _peerTyping = false;
  bool _pinned = false;
  bool _muted = false;
  bool _recording = false;
  bool _holdActive = false;
  bool _recordCancelled = false;
  bool _hasText = false;
  Duration _recordDuration = Duration.zero;
  int _messageLoadSeq = 0;
  Timer? _recordTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _markReadDebounce;
  Timer? _draftSaveDebounce;
  final List<double> _waveLevels = [];
  final _audioRecorder = AudioRecorder();
  late ChatConversation _conversation;
  Map<int, String> _senderNames = {};
  List<ChatUserBrief> _groupMembers = [];
  bool _threadSearchOpen = false;
  String _threadSearchQuery = '';
  int _searchMatchIndex = 0;
  ChatMessage? _pinnedMessage;
  ChatMessage? _editingMessage;
  bool _showJumpToBottom = false;
  int _newMessagesBelow = 0;
  bool _suppressMarkRead = false;
  bool _selectionMode = false;
  final _selectedMessageIds = <int>{};
  final _votingPollIds = <int>{};
  final _closingPollIds = <int>{};
  final _composerPanelKey = GlobalKey();

  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
  static const _overlayReactions = ['👍', '👌', '❤️', '🔥', '👎', '🥰', '👏'];

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _pinned = widget.conversation.pinned;
    _muted = widget.conversation.muted;
    ActiveChatSession.instance.setOpen(widget.conversationId);
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScrollChanged);
    _controller.addListener(_onInputChanged);
    unawaited(_loadCachedMessages());
    unawaited(_restoreDraft());
    unawaited(_restoreVoiceHint());
    _load(refresh: true);
    _startPolling();
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_appPaused) _refreshConversation();
    });
    _signalSub = ChatRealtimeSignals.instance.threadPoll.listen((_) {
      if (!_appPaused) _pollNew();
    });
    _apiReachabilityListener = () {
      if (!ApiReachabilityService.instance.isApiReachable.value || _appPaused) {
        return;
      }
      _stream?.resume();
      unawaited(_pollNew());
    };
    ApiReachabilityService.instance.isApiReachable
        .addListener(_apiReachabilityListener!);
    _stream = ChatStreamService(
      conversationId: widget.conversationId,
      onEvent: _onStreamEvent,
      onConnected: () {
        if (!mounted) return;
        setState(() => _sseConnected = true);
        _restartPolling();
      },
      onDisconnected: () {
        if (!mounted) return;
        setState(() => _sseConnected = false);
        _restartPolling();
      },
    )..connect();
    _refreshConversation();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval = _sseConnected
        ? const Duration(seconds: 60)
        : const Duration(seconds: 5);
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

  void _restartPolling() {
    if (!mounted) return;
    _startPolling();
  }

  void _onInputChanged() {
    if (!mounted) return;
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    _scheduleDraftSave();
    if (!has) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 800), () {
      ChatService.sendTyping(conversationId: widget.conversationId);
    });
  }

  void _onStreamEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type']?.toString();
    if (type == 'message.new') {
      final raw = event['message'];
      if (raw is! Map<String, dynamic>) return;
      try {
        final msg = ChatService.messageFromStreamPayload(raw);
        setState(() => _integrateMessage(msg));
        _scrollToBottom();
        _scheduleMarkRead();
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
      setState(() => _peerTyping = true);
      _peerTypingClear?.cancel();
      _peerTypingClear = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _peerTyping = false);
      });
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
      _applyReactions(messageId, ChatService.parseReactions(event['reactions']));
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
      _failedTextSends.remove(removeTempId);
    }
    _messages.removeWhere(
      (m) => m.id < 0 && m.isMine && !_failedTextSends.containsKey(m.id),
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
    final fraction = idx / _messages.length;
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
    final pending = _failedTextSends[tempId];
    if (pending == null || _sending) return;
    _failedTextSends.remove(tempId);
    _beginSending();
    try {
      final msg = await ChatService.sendText(
        conversationId: widget.conversationId,
        content: pending.text,
        replyToMessageId: pending.replyToMessageId,
      );
      if (!mounted) return;
      setState(() {
        _integrateMessage(msg, removeTempId: tempId);
      });
      _endSending();
      _scrollToBottom();
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
    } catch (e) {
      if (!mounted) return;
      setState(() => _failedTextSends[tempId] = pending);
      _endSending();
      showErrorSnackBar(context, e);
    }
  }

  void _discardFailedText(int tempId) {
    setState(() {
      _failedTextSends.remove(tempId);
      _messages.removeWhere((m) => m.id == tempId);
    });
    unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
  }

  void _discardPendingMedia() {
    setState(() => _pendingMediaRetry = null);
  }

  void _rememberFailedMedia(_PendingMediaSend pending) {
    setState(() => _pendingMediaRetry = pending);
  }

  Future<void> _retryPendingMedia() async {
    final pending = _pendingMediaRetry;
    if (pending == null || _sending) return;
    setState(() => _pendingMediaRetry = null);
    switch (pending.kind) {
      case _PendingMediaKind.image:
        await _sendPickedImage(pending.file, replyToId: pending.replyToMessageId);
      case _PendingMediaKind.video:
        await _sendPickedVideo(pending.file, replyToId: pending.replyToMessageId);
      case _PendingMediaKind.file:
        await _sendPickedFile(
          pending.file,
          fileName: pending.fileName ?? 'file',
          replyToId: pending.replyToMessageId,
        );
    }
  }

  Widget _pendingMediaRetryBanner(ColorScheme scheme) {
    final pending = _pendingMediaRetry;
    if (pending == null) return const SizedBox.shrink();
    final label = switch (pending.kind) {
      _PendingMediaKind.image => 'фото',
      _PendingMediaKind.video => 'видео',
      _PendingMediaKind.file => 'файл',
    };
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
                'Не удалось отправить $label',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
              ),
            ),
            TextButton(
              onPressed: _sending ? null : _retryPendingMedia,
              child: const Text('Повторить'),
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
      return;
    }
    if (!_showJumpToBottom) {
      setState(() => _showJumpToBottom = true);
    }
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
      final firstUnread = _firstUnreadMessageId();
      if (firstUnread != null) {
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
      }
    });
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

  void _startEdit(ChatMessage msg) {
    setState(() {
      _editingMessage = msg;
      _replyTo = null;
      _controller.text = msg.content;
      _controller.selection = TextSelection.collapsed(offset: msg.content.length);
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
                        child: Text(emoji, style: const TextStyle(fontSize: 28)),
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

  void _applyReadReceipt(int readUpToId) {
    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        if (m.isMine && m.id <= readUpToId && !m.isRead) {
          _messages[i] = m.copyWith(isRead: true);
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
    _peerTypingClear?.cancel();
    _markReadDebounce?.cancel();
    _draftSaveDebounce?.cancel();
    _signalSub?.cancel();
    if (_apiReachabilityListener != null) {
      ApiReachabilityService.instance.isApiReachable
          .removeListener(_apiReachabilityListener!);
    }
    _holdActive = false;
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    unawaited(_stopRecorderSilently());
    _audioRecorder.dispose();
    _stream?.disconnect();
    unawaited(
      ChatCacheService.saveDraft(widget.conversationId, _controller.text),
    );
    _controller.removeListener(_onInputChanged);
    _controller.dispose();
    _threadSearchController.dispose();
    _scroll.dispose();
    super.dispose();
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
    } catch (_) {}
  }

  Future<void> _forwardMessage(ChatMessage msg) async {
    try {
      final chats = await ChatService.listConversations();
      if (!mounted) return;
      final targets = chats
          .where((c) => c.id != widget.conversationId)
          .toList();
      if (targets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет других чатов для пересылки')),
        );
        return;
      }
      final picked = await showModalBottomSheet<ChatConversation>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Переслать в…')),
              ...targets.map(
                (c) => ListTile(
                  leading: Icon(
                    c.isSaved
                        ? Icons.bookmark_rounded
                        : c.isGroup
                            ? Icons.groups_rounded
                            : Icons.person_rounded,
                  ),
                  title: Text(c.displayTitle),
                  onTap: () => Navigator.pop(ctx, c),
                ),
              ),
            ],
          ),
        ),
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
    if (msg.type == 'image' &&
        mediaUrl != null &&
        mediaUrl.isNotEmpty) {
      await ChatService.sendImage(
        conversationId: target.id,
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        caption: msg.content.trim(),
      );
      return;
    }
    if (msg.type == 'voice' &&
        mediaUrl != null &&
        mediaUrl.isNotEmpty) {
      await ChatService.sendVoice(
        conversationId: target.id,
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        durationSec: msg.voiceDurationSec ?? 1,
      );
      return;
    }
    if (msg.type == 'file' &&
        mediaUrl != null &&
        mediaUrl.isNotEmpty) {
      await ChatService.sendFile(
        conversationId: target.id,
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        fileName: msg.content.trim().isEmpty ? 'Файл' : msg.content.trim(),
      );
      return;
    }
    if (msg.type == 'video' &&
        mediaUrl != null &&
        mediaUrl.isNotEmpty) {
      await ChatService.sendVideo(
        conversationId: target.id,
        mediaUrl: ServerConfig.resolveMediaUrl(mediaUrl),
        caption: msg.content.trim(),
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
            : msg.content.trim();
    await ChatService.sendText(
      conversationId: target.id,
      content: '↪ $label: ${body.isEmpty ? 'Сообщение' : body}',
    );
  }

  Future<void> _deleteChat() async {
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
    try {
      await ChatService.deleteConversation(conversationId: widget.conversationId);
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
    }
  }

  Future<void> _openFileUrl(String url) async {
    final resolved = ServerConfig.resolveMediaUrl(url);
    final uri = Uri.tryParse(resolved);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                  leading: _ThreadUserAvatar(user: member),
                  title: Text(member.displayName),
                  subtitle: Text(formatLastSeen(member.lastSeenAt)),
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
        _threadSearchQuery = '';
        _searchMatchIndex = 0;
        _threadSearchController.clear();
      }
    });
  }

  bool _messageMatchesSearch(ChatMessage msg, String q) {
    if (msg.content.toLowerCase().contains(q)) return true;
    final sender = msg.senderName ?? _senderNames[msg.senderId] ?? '';
    if (sender.toLowerCase().contains(q)) return true;
    if (msg.type == 'voice' && 'голосовое'.contains(q)) return true;
    if (msg.type == 'image' && 'фото'.contains(q)) return true;
    if (msg.type == 'video' && 'видео'.contains(q)) return true;
    if (msg.type == 'file') {
      final name = msg.content.trim().toLowerCase();
      if (name.contains(q) || 'файл'.contains(q)) return true;
    }
    return false;
  }

  List<int> get _searchMatchIds {
    final q = _threadSearchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final msg in _messages)
        if (_messageMatchesSearch(msg, q)) msg.id,
    ];
  }

  void _onThreadSearchChanged(String value) {
    setState(() {
      _threadSearchQuery = value;
      _searchMatchIndex = 0;
    });
    _scrollToCurrentSearchMatch();
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

  List<ChatMessage> get _visibleMessages {
    final q = _threadSearchQuery.trim().toLowerCase();
    if (q.isEmpty) return _messages;
    return _messages.where((msg) => _messageMatchesSearch(msg, q)).toList();
  }

  Future<void> _markUnread() async {
    _markReadDebounce?.cancel();
    try {
      await ChatService.markUnread(conversationId: widget.conversationId);
      if (!mounted) return;
      setState(() => _suppressMarkRead = true);
      try {
        final conv = await ChatService.getConversation(widget.conversationId);
        if (mounted) setState(() => _conversation = conv);
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
        content: const Text('Вы больше не будете получать сообщения в этом чате.'),
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
    try {
      await ChatService.leaveGroup(conversationId: widget.conversationId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appPaused = state != AppLifecycleState.resumed;
    if (_appPaused) {
      _stream?.pause();
      if (_recording || _holdActive) {
        _holdActive = false;
        unawaited(_cancelRecording());
      }
    } else {
      unawaited(ApiReachabilityService.instance.warmUp());
      _stream?.resume();
      _pollNew();
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
        _stopAndSendVoice();
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
    if (!_recording) return;
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (_) {}
    final durationSec = math.max(1, _recordDuration.inSeconds);
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordCancelled = false;
      _recordDuration = Duration.zero;
      _waveLevels.clear();
    });
    if (durationSec < 1) return;
    if (!kIsWeb && (path == null || path.isEmpty)) return;

    _beginSending(status: 'Загрузка голосового…');
    try {
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
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: file,
        fileType: 'audio',
        onProgress: (p) => _setUploadProgress(p, status: 'Загрузка голосового…'),
      );
      final url = uploaded.url;
      if (url == null || url.isEmpty) throw Exception('Нет URL файла');
      final resolved = ServerConfig.resolveVoiceMediaUrl(url);
      _setUploadProgress(1, status: 'Отправка…');
      final msg = await ChatService.sendVoice(
        conversationId: widget.conversationId,
        mediaUrl: resolved,
        durationSec: durationSec,
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
      showErrorSnackBar(context, e, fallback: 'Не удалось отправить голосовое');
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
              (m.type == 'image' || m.type == 'video' || m.type == 'file'),
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
      final picked = await showModalBottomSheet<ChatConversation>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Переслать в…')),
              ...targets.map(
                (c) => ListTile(
                  leading: Icon(
                    c.isSaved
                        ? Icons.bookmark_rounded
                        : c.isGroup
                            ? Icons.groups_rounded
                            : Icons.person_rounded,
                  ),
                  title: Text(c.displayTitle),
                  onTap: () => Navigator.pop(ctx, c),
                ),
              ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      for (final msg in selected) {
        await _sendForwardTo(picked, msg);
      }
      if (!mounted) return;
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Переслано ${selected.length} в «${picked.displayTitle}»',
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
      case 'copy':
        Clipboard.setData(ClipboardData(text: _copyableText(msg)));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скопировано')),
        );
      case 'edit':
        _startEdit(msg);
      case 'pin':
        _togglePinMessage(msg);
      case 'forward':
        _forwardMessage(msg);
      case 'delete':
        unawaited(_confirmDeleteMessage(msg));
      case 'select':
        _enterSelectionMode(msg);
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
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Icon(Icons.error_outline, size: 14, color: scheme.error),
          Text(
            'Не отправлено',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.error,
                ),
          ),
          TextButton(
            onPressed: _sending ? null : () => _retryFailedText(tempId),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Повторить'),
          ),
          TextButton(
            onPressed: _sending ? null : () => _discardFailedText(tempId),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Widget _messageBubbleWidget({
    required ChatMessage msg,
    required ColorScheme scheme,
    required bool searching,
    required bool isGroup,
    String? replyQuote,
    VoidCallback? onReplyTap,
    bool interactive = true,
    bool wrapWithAlign = true,
    ValueChanged<int>? onPollVote,
    bool pollVoting = false,
    VoidCallback? onPollClose,
    bool pollClosing = false,
  }) {
    return _Bubble(
      message: msg,
      scheme: scheme,
      highlightQuery: searching ? _threadSearchQuery : null,
      replyQuote: replyQuote,
      onReplyTap: onReplyTap,
      showSenderName: isGroup && !msg.isMine,
      senderLabel: msg.senderName ?? _senderNames[msg.senderId],
      isConversationPinned: _pinnedMessage?.id == msg.id,
      wrapWithAlign: wrapWithAlign,
      onPollVote: onPollVote,
      pollVoting: pollVoting,
      onPollClose: onPollClose,
      pollClosing: pollClosing,
      onImageTap: interactive && msg.type == 'image' && msg.mediaUrl != null
          ? () => _openImage(msg.mediaUrl!)
          : null,
      onVideoTap: interactive && msg.type == 'video' && msg.mediaUrl != null
          ? () => _openVideo(msg.mediaUrl!)
          : null,
      onReactionTap: interactive ? (emoji) => _toggleReaction(msg, emoji) : null,
      onFileTap: interactive && msg.type == 'file' && msg.mediaUrl != null
          ? () => _openFileUrl(msg.mediaUrl!)
          : null,
    );
  }

  double _overlayComposerReserve() {
    final panelBox =
        _composerPanelKey.currentContext?.findRenderObject() as RenderBox?;
    if (panelBox != null && panelBox.hasSize) {
      return panelBox.size.height + 8;
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    const composerRow = 56.0;
    const bannerRow = 52.0;
    var reserve = bottom + composerRow + 12;
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
    final clusterOverflow =
        preLayout.menuTop + menuH - (targetBottom - 8);
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

  Future<void> _load({required bool refresh}) async {
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
        _scrollAfterInitialLoad();
      }
      _scheduleMarkRead();
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
    if (_loading || _sending) return;
    if (_messages.isEmpty) return;
    try {
      final lastId = _messages.last.id;
      if (lastId <= 0) return;
      final fresh = await ChatService.listMessagesAfter(
        conversationId: widget.conversationId,
        afterId: lastId,
      );
      if (!mounted || fresh.isEmpty) return;
      var added = 0;
      setState(() {
        for (final msg in fresh) {
          if (_integrateMessage(msg)) added++;
        }
      });
      if (added == 0) return;
      if (_isNearBottom()) {
        _scrollToBottom();
        _scheduleMarkRead();
      } else {
        setState(() {
          _newMessagesBelow += added;
          _showJumpToBottom = true;
        });
      }
    } catch (_) {}
  }

  void _scheduleMarkRead() {
    if (_suppressMarkRead) return;
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_markLatestRead());
    });
  }

  Future<void> _markLatestRead() async {
    if (_messages.isEmpty) return;
    final last = _messages.last;
    await ChatService.markRead(
      conversationId: widget.conversationId,
      messageId: last.id,
    );
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    if (_suppressMarkRead) {
      setState(() => _suppressMarkRead = false);
      _scheduleMarkRead();
    }
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
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
    setState(() {
      _messages.add(optimistic);
      _replyTo = null;
    });
    _beginSending();
    _controller.clear();
    try {
      final msg = await ChatService.sendText(
        conversationId: widget.conversationId,
        content: text,
        replyToMessageId: replyId,
      );
      if (!mounted) return;
      setState(() {
        _integrateMessage(msg, removeTempId: tempId);
      });
      _endSending();
      _scrollToBottom();
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
      unawaited(ChatCacheService.clearDraft(widget.conversationId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failedTextSends[tempId] = _PendingTextSend(
          text: text,
          replyToMessageId: replyId,
        );
      });
      _endSending();
      showErrorSnackBar(context, e);
    }
  }

  void _openImage(String url) {
    final urls = _messages
        .where((m) => m.type == 'image' && (m.mediaUrl?.isNotEmpty ?? false))
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

  Future<void> _openVideo(String url) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ChatVideoPlayerPage(videoUrl: url),
      ),
    );
  }

  Future<void> _showAttachMenu() async {
    if (_sending || _recording) return;
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
        if (contact != null) await _sendContact(contact);
      case ChatAttachResult.resendFile:
        final url = selection.resendFileUrl;
        final name = selection.resendFileName;
        if (url != null && name != null) {
          await _resendStoredFile(name: name, mediaUrl: url);
        }
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
    final text = lines.join('\n');
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

  bool _looksLikeVideoFile(XFile file) {
    final name = file.name.toLowerCase();
    return name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.avi') ||
        name.endsWith('.mkv');
  }

  Future<void> _pickFromMediaLibrary() async {
    if (_sending || _recording) return;
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

  Future<void> _sendPickedImage(XFile file, {int? replyToId}) async {
    final reply = replyToId ?? _replyTo?.id;
    _beginSending(status: 'Загрузка фото…');
    try {
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: file,
        fileType: 'image',
        onProgress: (p) => _setUploadProgress(p, status: 'Загрузка фото…'),
      );
      final url = uploaded.url;
      if (url == null || url.isEmpty) throw Exception('Нет URL файла');
      final resolved = ServerConfig.resolveMediaUrl(url);
      _setUploadProgress(1, status: 'Отправка…');
      final msg = await ChatService.sendImage(
        conversationId: widget.conversationId,
        mediaUrl: resolved,
        replyToMessageId: reply,
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
      _rememberFailedMedia(_PendingMediaSend(
        kind: _PendingMediaKind.image,
        file: file,
        replyToMessageId: reply,
      ));
      showErrorSnackBar(context, e, fallback: 'Не удалось отправить фото');
    }
  }

  Future<void> _sendPickedVideo(XFile file, {int? replyToId}) async {
    final reply = replyToId ?? _replyTo?.id;
    _beginSending(status: 'Загрузка видео…');
    try {
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: file,
        fileType: 'video',
        waitForProcessing: false,
        onProgress: (p) => _setUploadProgress(p, status: 'Загрузка видео…'),
      );
      final url = uploaded.url;
      if (url == null || url.isEmpty) throw Exception('Нет URL файла');
      final resolved = ServerConfig.resolveMediaUrl(url);
      _setUploadProgress(1, status: 'Отправка…');
      final msg = await ChatService.sendVideo(
        conversationId: widget.conversationId,
        mediaUrl: resolved,
        replyToMessageId: reply,
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
      _rememberFailedMedia(_PendingMediaSend(
        kind: _PendingMediaKind.video,
        file: file,
        replyToMessageId: reply,
      ));
      showErrorSnackBar(context, e, fallback: 'Не удалось отправить видео');
    }
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
    final safeName = name.isEmpty ? 'video_${DateTime.now().millisecondsSinceEpoch}.$ext' : '$name.$ext';
    return XFile.fromData(bytes, name: safeName, mimeType: 'video/$ext');
  }

  Future<void> _pickFile() async {
    if (_sending || _recording) return;
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
  }) async {
    final reply = replyToId ?? _replyTo?.id;
    _beginSending(status: 'Загрузка файла…');
    try {
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: file,
        fileType: 'document',
        onProgress: (p) => _setUploadProgress(p, status: 'Загрузка файла…'),
      );
      final fileUrl = uploaded.url;
      if (fileUrl == null || fileUrl.isEmpty) {
        throw Exception('Не удалось загрузить файл');
      }
      _setUploadProgress(1, status: 'Отправка…');
      final msg = await ChatService.sendFile(
        conversationId: widget.conversationId,
        mediaUrl: ServerConfig.resolveMediaUrl(fileUrl),
        fileName: fileName,
        replyToMessageId: reply,
      );
      if (!mounted) return;
      setState(() {
        _integrateMessage(msg);
        _replyTo = null;
      });
      _endSending();
      _scrollToBottom();
      unawaited(ChatCacheService.saveThread(widget.conversationId, _messages));
      unawaited(_rememberRecentFile(
        name: fileName,
        file: file,
        mediaUrl: fileUrl,
      ));
    } catch (e) {
      if (!mounted) return;
      _endSending();
      _rememberFailedMedia(_PendingMediaSend(
        kind: _PendingMediaKind.file,
        file: file,
        fileName: fileName,
        replyToMessageId: reply,
      ));
      showErrorSnackBar(context, e, fallback: 'Не удалось отправить файл');
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

  Future<void> _pickImage({required ImageSource source}) async {
    if (_sending || _recording) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null) return;
    await _sendPickedImage(file);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isGroup = _conversation.isGroup;
    final isSaved = _conversation.isSaved;
    final peer = _conversation.peer;
    String subtitle = '';
    if (isSaved) {
      subtitle = 'Сохраняйте сообщения и заметки';
    } else if (isGroup) {
      subtitle = _peerTyping
          ? 'печатает…'
          : '${_conversation.memberCount} участников';
    } else if (_peerTyping) {
      subtitle = 'печатает…';
    } else if (peer != null) {
      subtitle = formatLastSeen(peer.lastSeenAt);
    }
    if (_muted && subtitle.isNotEmpty) {
      subtitle = '$subtitle · без звука';
    } else if (_muted) {
      subtitle = 'без звука';
    }
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: isSaved
              ? scheme.onSurfaceVariant
              : _peerTyping || (!isGroup && (peer?.isOnline ?? false))
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
        );
    final visibleMessages = _visibleMessages;
    final searching = _threadSearchQuery.trim().isNotEmpty;
    final mediaCount = _mediaMessageCount();

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _exitSelectionMode();
      },
      child: Scaffold(
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
        title: GestureDetector(
          onTap: isGroup ? _openGroupInfo : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_conversation.displayTitle),
              if (subtitle.isNotEmpty) Text(subtitle, style: subtitleStyle),
            ],
          ),
        ),
        bottom: _threadSearchOpen
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _threadSearchController,
                    autofocus: true,
                    onChanged: _onThreadSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Поиск в чате',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchMatchIds.isNotEmpty) ...[
                            Text(
                              '${_searchMatchIndex + 1}/${_searchMatchIds.length}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            IconButton(
                              tooltip: 'Предыдущее',
                              icon: const Icon(Icons.keyboard_arrow_up),
                              onPressed: () => _goToSearchMatch(false),
                            ),
                            IconButton(
                              tooltip: 'Следующее',
                              icon: const Icon(Icons.keyboard_arrow_down),
                              onPressed: () => _goToSearchMatch(true),
                            ),
                          ],
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
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            onSelected: (v) {
              if (v == 'search') _toggleThreadSearch();
              if (v == 'media') _openMediaGallery();
              if (v == 'mute') _toggleMute();
              if (v == 'pin') _togglePin();
              if (v == 'group') _openGroupInfo();
              if (v == 'block') _blockPeer();
              if (v == 'leave') _leaveGroup();
              if (v == 'unread') _markUnread();
              if (v == 'delete') _deleteChat();
              if (v == 'archive') _archiveChat();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'search',
                child: _threadMenuRow(
                  _threadSearchOpen ? Icons.search_off : Icons.search,
                  _threadSearchOpen ? 'Закрыть поиск' : 'Поиск в чате',
                ),
              ),
              if (mediaCount > 0) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'media',
                  child: _threadMenuRow(
                    Icons.photo_library_outlined,
                    'Медиа ($mediaCount)',
                  ),
                ),
              ],
              if (!isSaved) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'pin',
                  child: _threadMenuRow(
                    _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    _pinned ? 'Открепить' : 'Закрепить',
                  ),
                ),
                PopupMenuItem(
                  value: 'mute',
                  child: _threadMenuRow(
                    _muted
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_outlined,
                    _muted ? 'Включить уведомления' : 'Без звука',
                  ),
                ),
                if (isGroup)
                  PopupMenuItem(
                    value: 'group',
                    child: _threadMenuRow(
                      Icons.info_outline,
                      'О группе',
                    ),
                  ),
                if (!isGroup && peer != null)
                  PopupMenuItem(
                    value: 'block',
                    child: _threadMenuRow(
                      Icons.block_outlined,
                      'Заблокировать',
                    ),
                  ),
                if (isGroup)
                  PopupMenuItem(
                    value: 'leave',
                    child: _threadMenuRow(
                      Icons.logout,
                      'Выйти из группы',
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'unread',
                  child: _threadMenuRow(
                    Icons.mark_chat_unread_outlined,
                    'Пометить непрочитанным',
                  ),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: _threadMenuRow(
                    Icons.archive_outlined,
                    'В архив',
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: _threadMenuRow(
                    Icons.delete_outline,
                    'Удалить чат',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_pinnedMessage != null)
            Material(
              color: scheme.surfaceContainerHighest,
              child: InkWell(
                onTap: () => _scrollToMessage(_pinnedMessage!.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.push_pin, size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Закреплённое сообщение',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            Text(
                              _pinnedPreview(_pinnedMessage!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Открепить',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _togglePinMessage(_pinnedMessage!),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                    : _messages.isEmpty && !_loading
                        ? const Center(child: Text('Напишите первое сообщение'))
                        : searching && visibleMessages.isEmpty
                            ? const Center(child: Text('Ничего не найдено'))
                            : ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                itemCount: visibleMessages.length +
                                    (_hasMore && !searching ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (_hasMore && !searching && index == 0) {
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
                                  final msgIndex =
                                      index - (_hasMore && !searching ? 1 : 0);
                                  final msg = visibleMessages[msgIndex];
                                  final replyTarget = _replyTargetFor(msg);
                                  final replyQuote = replyTarget != null
                                      ? _messagePreview(replyTarget)
                                      : (msg.replyToMessageId != null
                                          ? 'Сообщение'
                                          : null);
                                  final selected = _selectedMessageIds.contains(msg.id);
                                  final failed = _failedTextSends.containsKey(msg.id);
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (_selectionMode)
                                        _selectionIndicator(selected, scheme),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: msg.isMine
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                            Align(
                                              alignment: msg.isMine
                                                  ? Alignment.centerRight
                                                  : Alignment.centerLeft,
                                              child: Builder(
                                                builder: (bubbleContext) =>
                                                    GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: _selectionMode
                                                      ? () =>
                                                          _toggleMessageSelection(
                                                            msg.id,
                                                          )
                                                      : null,
                                                  onLongPress: _selectionMode
                                                      ? null
                                                      : () {
                                                          final box =
                                                              bubbleContext
                                                                      .findRenderObject()
                                                                  as RenderBox?;
                                                          if (box != null &&
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
                                                    opacity: failed ? 0.55 : 1,
                                                    child: _messageBubbleWidget(
                                                      msg: msg,
                                                      scheme: scheme,
                                                      searching: searching,
                                                      isGroup: isGroup,
                                                      replyQuote: replyQuote,
                                                      interactive:
                                                          !_selectionMode,
                                                      wrapWithAlign: false,
                                                      onPollVote:
                                                          !_selectionMode
                                                              ? (idx) =>
                                                                  _votePoll(
                                                                    msg,
                                                                    idx,
                                                                  )
                                                              : null,
                                                      pollVoting: _votingPollIds
                                                          .contains(msg.id),
                                                      onPollClose: (!_selectionMode &&
                                                              msg.isMine &&
                                                              msg.type ==
                                                                  'poll' &&
                                                              msg.poll != null &&
                                                              !msg.poll!
                                                                  .isClosed)
                                                          ? () => _closePoll(msg)
                                                          : null,
                                                      pollClosing: _closingPollIds
                                                          .contains(msg.id),
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
                                            if (failed)
                                              _failedSendActions(msg.id, scheme),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                if (_showJumpToBottom && !_selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(20),
                      color: scheme.primary,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _jumpToBottomAndMarkRead,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            _newMessagesBelow > 0
                                ? _newMessagesChipLabel()
                                : '↓ Вниз',
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
          if (_sending)
            Material(
              color: scheme.secondaryContainer.withValues(alpha: 0.55),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (_uploadProgress == null)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onSecondaryContainer,
                            ),
                          )
                        else
                          Text(
                            '${(_uploadProgress! * 100).round()}%',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: scheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _sendingStatus,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: scheme.onSecondaryContainer,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (_uploadProgress != null) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: _uploadProgress,
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(2),
                        color: scheme.primary,
                        backgroundColor:
                            scheme.onSecondaryContainer.withValues(alpha: 0.2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_pendingMediaRetry != null) _pendingMediaRetryBanner(scheme),
          if (_showVoiceHint && !_recording && !_sending)
            Material(
              color: scheme.tertiaryContainer.withValues(alpha: 0.45),
              child: ListTile(
                dense: true,
                leading: Icon(
                  Icons.mic_none_rounded,
                  color: scheme.onTertiaryContainer,
                  size: 22,
                ),
                title: Text(
                  'Удерживайте кнопку микрофона для голосового',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                ),
                trailing: IconButton(
                  tooltip: 'Скрыть',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _dismissVoiceHint,
                ),
              ),
            ),
          if (_editingMessage != null)
            Material(
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.edit_outlined, size: 20),
                title: const Text('Редактирование'),
                subtitle: Text(
                  _editingMessage!.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: _cancelEdit,
                ),
              ),
            ),
          if (_replyTo != null)
            Material(
              color: scheme.surfaceContainerHighest,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.reply_rounded, size: 20),
                title: Text(
                  _replyTo!.isMine
                      ? 'Вы'
                      : (_replyTo!.senderName ??
                          _senderNames[_replyTo!.senderId] ??
                          _conversation.displayTitle),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                subtitle: Text(
                  _messagePreview(_replyTo!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => setState(() => _replyTo = null),
                ),
              ),
            ),
          if (_recording)
            Material(
              color: _recordCancelled
                  ? scheme.errorContainer.withValues(alpha: 0.5)
                  : scheme.primaryContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _recordCancelled
                          ? '← Отпустите для отмены'
                          : 'Отпустите для отправки',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sending || _recording ? null : _showAttachMenu,
                    icon: const Icon(Icons.attach_file_outlined),
                    tooltip: 'Вложение',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_recording,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _hasText ? _sendText() : null,
                      decoration: InputDecoration(
                        hintText: _recording
                            ? 'Удерживайте микрофон…'
                            : (_editingMessage != null
                                ? 'Изменить сообщение'
                                : (_hasText
                                    ? 'Сообщение'
                                    : 'Сообщение или удержите 🎤')),
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (_hasText && !_recording)
                    IconButton.filled(
                      onPressed: _sending || _recording ? null : _sendText,
                      icon: _sending
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : Icon(
                              _editingMessage != null
                                  ? Icons.check_rounded
                                  : Icons.send_rounded,
                            ),
                    )
                  else
                    ChatVoiceMicButton(
                      enabled: !_sending,
                      recording: _recording,
                      onHoldStart: _onHoldStart,
                      onHoldEnd: _onHoldEnd,
                      onHoldDragDx: _onHoldDrag,
                    ),
                ],
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
  }
}

enum _PendingMediaKind { image, video, file }

class _PendingMediaSend {
  const _PendingMediaSend({
    required this.kind,
    required this.file,
    this.fileName,
    this.replyToMessageId,
  });

  final _PendingMediaKind kind;
  final XFile file;
  final String? fileName;
  final int? replyToMessageId;
}

class _PendingTextSend {
  const _PendingTextSend({
    required this.text,
    this.replyToMessageId,
  });

  final String text;
  final int? replyToMessageId;
}

Widget _threadMenuRow(IconData icon, String label) {
  return Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.scheme,
    this.highlightQuery,
    this.replyQuote,
    this.onReplyTap,
    this.showSenderName = false,
    this.senderLabel,
    this.isConversationPinned = false,
    this.onImageTap,
    this.onVideoTap,
    this.onFileTap,
    this.onReactionTap,
    this.wrapWithAlign = true,
    this.onPollVote,
    this.pollVoting = false,
    this.onPollClose,
    this.pollClosing = false,
  });

  final ChatMessage message;
  final ColorScheme scheme;
  final String? highlightQuery;
  final String? replyQuote;
  final VoidCallback? onReplyTap;
  final bool showSenderName;
  final String? senderLabel;
  final bool isConversationPinned;
  final VoidCallback? onImageTap;
  final VoidCallback? onVideoTap;
  final VoidCallback? onFileTap;
  final ValueChanged<String>? onReactionTap;
  final bool wrapWithAlign;
  final ValueChanged<int>? onPollVote;
  final bool pollVoting;
  final VoidCallback? onPollClose;
  final bool pollClosing;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final bg = mine ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final fg = mine ? scheme.onPrimaryContainer : scheme.onSurface;
    final quoteBg = mine
        ? scheme.primary.withValues(alpha: 0.12)
        : scheme.onSurface.withValues(alpha: 0.06);

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            if (showSenderName &&
                (senderLabel?.isNotEmpty ?? false)) ...[
              Text(
                senderLabel!,
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (replyQuote != null) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onReplyTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: quoteBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: scheme.primary,
                          width: 3,
                        ),
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
              const SizedBox(height: 6),
            ],
            if (message.type == 'voice' && message.mediaUrl != null)
              ChatVoiceBubble(
                message: message,
                foregroundColor: fg,
                accentColor: scheme.primary,
                activeColor: mine ? scheme.primary : scheme.secondary,
              )
            else if (message.type == 'poll' && message.poll != null)
              ChatPollBubble(
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
              )
            else if (message.type == 'file' && message.mediaUrl != null)
              Material(
                color: quoteBg,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: onFileTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.insert_drive_file_outlined, color: fg),
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
              )
            else if (message.type == 'image' && message.mediaUrl != null)
              GestureDetector(
                onTap: onImageTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: ServerConfig.resolvePublisherAvatarUrl(
                      ServerConfig.resolveMediaUrl(message.mediaUrl!),
                    ),
                    fit: BoxFit.cover,
                    memCacheWidth: 720,
                    maxWidthDiskCache: 720,
                    errorWidget: (_, __, ___) => SizedBox(
                      height: 120,
                      child: ColoredBox(
                        color: quoteBg,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: fg.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else if (message.type == 'video' && message.mediaUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: InlineVideoPlayer(
                    videoUrl: message.mediaUrl!,
                    onTap: onVideoTap,
                  ),
                ),
              ),
              if (message.content.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                HighlightedText(
                  text: message.content,
                  query: highlightQuery,
                  style: TextStyle(color: fg),
                ),
              ],
            ]
            else if (message.content.isNotEmpty && message.type != 'voice') ...[
              HighlightedText(
                text: message.content,
                query: highlightQuery,
                style: TextStyle(color: fg),
              ),
              if (extractFirstHttpUrl(message.content) case final url?)
                ChatLinkPreview(
                  url: url,
                  foregroundColor: fg,
                  accentColor: scheme.primary,
                  backgroundColor: quoteBg,
                ),
            ],
            if (message.reactions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
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
                              style: TextStyle(
                                color: fg,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isConversationPinned) ...[
                  Icon(Icons.push_pin, size: 12, color: scheme.primary),
                  const SizedBox(width: 4),
                ],
                Text(
                  formatChatMessageTime(message.createdAt),
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.65),
                    fontSize: 11,
                  ),
                ),
                if (message.isEdited) ...[
                  const SizedBox(width: 4),
                  Text(
                    'изм.',
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.isRead ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message.isRead
                        ? scheme.primary
                        : fg.withValues(alpha: 0.55),
                  ),
                ],
              ],
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
    VideoPlayerHelper.createPreparedController(
      widget.videoUrl,
      muted: false,
      autoPlay: true,
    ).then((c) {
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _initialized = true;
      });
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _initialized = true;
        });
      }
    });
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
                  const Icon(Icons.error_outline, size: 64, color: Colors.white70),
                  const SizedBox(height: 16),
                  const Text(
                    'Не удалось загрузить видео',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
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

class _ThreadUserAvatar extends StatelessWidget {
  const _ThreadUserAvatar({required this.user});

  final ChatUserBrief user;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl;
    final resolved = url != null && url.isNotEmpty
        ? ServerConfig.resolvePublisherAvatarUrl(url)
        : null;
    final trimmed = user.displayName.trim();
    final letter = trimmed.isEmpty
        ? '?'
        : trimmed.characters.first.toUpperCase();
    return CircleAvatar(
      radius: 20,
      backgroundImage: resolved != null
          ? ResizeImage(CachedNetworkImageProvider(resolved), width: 80)
          : null,
      child: resolved == null
          ? Text(letter, style: const TextStyle(fontWeight: FontWeight.w600))
          : null,
    );
  }
}
