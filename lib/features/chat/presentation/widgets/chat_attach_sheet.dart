import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../miniapps/presentation/miniapps_catalog_screen.dart';

import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/platform/device_location.dart';
import '../../../../core/theme/color_schemes.dart';
import '../../../../models/chat_models.dart';
import '../../../../models/gif_models.dart';
import '../../../../models/sticker_models.dart';
import '../../../../services/api_reachability_service.dart';
import '../../../../services/chat_service.dart';
import '../../../../services/gif_search_service.dart';
import '../../../../services/media_upload_service.dart';
import '../../../../services/phone_contacts_service.dart';
import '../../../../services/server_config.dart';
import '../../../../services/sticker_service.dart';
import '../../application/chat_recent_files_store.dart';
import '../../application/chat_recent_gifs_store.dart';
import '../../application/chat_sticker_pinned_packs_store.dart';
import '../../application/chat_recent_stickers_store.dart';
import '../../../../widgets/chat_sticker_tile.dart';
import '../../../../services/auth_service.dart';
import '../sticker_pack_manage_screen.dart';
import '../sticker_pack_preview_screen.dart';
import 'chat_location_bubble.dart';
import 'chat_poll_form_panel.dart';
import 'chats_hub_tiles.dart';
import 'create_chat_poll_sheet.dart';

enum ChatAttachTab {
  gallery,
  gif,
  file,
  poll,
  contact,
  location,
  videoNote,
  sticker,
}

enum ChatAttachResult {
  galleryFiles,
  file,
  pickedFile,
  poll,
  contact,
  location,
  videoNote,
  resendFile,
  sticker,
  gifResend,
}

class ChatAttachSelection {
  const ChatAttachSelection._({
    required this.kind,
    this.galleryFiles = const [],
    this.contact,
    this.contactPhoneName,
    this.contactPhoneE164,
    this.pollDraft,
    this.resendFileName,
    this.resendFileUrl,
    this.pickedFile,
    this.pickedFileName,
    this.stickerMediaUrl,
    this.stickerEmoji,
    this.latitude,
    this.longitude,
    this.livePeriodSeconds,
  });

  final ChatAttachResult kind;
  final List<XFile> galleryFiles;
  final ChatContact? contact;
  final String? contactPhoneName;
  final String? contactPhoneE164;
  final ChatPollDraft? pollDraft;
  final String? resendFileName;
  final String? resendFileUrl;
  final XFile? pickedFile;
  final String? pickedFileName;
  final String? stickerMediaUrl;
  final String? stickerEmoji;
  final double? latitude;
  final double? longitude;
  final int? livePeriodSeconds;

  factory ChatAttachSelection.gallery(List<XFile> files) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.galleryFiles,
        galleryFiles: files,
      );

  factory ChatAttachSelection.contact(ChatContact contact) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.contact,
        contact: contact,
      );

  factory ChatAttachSelection.phoneContact({
    required String displayName,
    required String phoneE164,
  }) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.contact,
        contactPhoneName: displayName,
        contactPhoneE164: phoneE164,
      );

  factory ChatAttachSelection.simple(ChatAttachResult kind) =>
      ChatAttachSelection._(kind: kind);

  factory ChatAttachSelection.pollDraft(ChatPollDraft draft) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.poll,
        pollDraft: draft,
      );

  factory ChatAttachSelection.resendFile({
    required String name,
    required String mediaUrl,
  }) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.resendFile,
        resendFileName: name,
        resendFileUrl: mediaUrl,
      );

  factory ChatAttachSelection.pickedFile({
    required XFile file,
    required String name,
  }) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.pickedFile,
        pickedFile: file,
        pickedFileName: name,
      );

  factory ChatAttachSelection.sticker({
    required String mediaUrl,
    String? emoji,
  }) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.sticker,
        stickerMediaUrl: mediaUrl,
        stickerEmoji: emoji,
      );

  factory ChatAttachSelection.location({
    double? latitude,
    double? longitude,
    int? livePeriodSeconds,
  }) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.location,
        latitude: latitude,
        longitude: longitude,
        livePeriodSeconds: livePeriodSeconds,
      );

  factory ChatAttachSelection.videoNote() =>
      ChatAttachSelection._(kind: ChatAttachResult.videoNote);

  factory ChatAttachSelection.gifResend(String mediaUrl) =>
      ChatAttachSelection._(
        kind: ChatAttachResult.gifResend,
        resendFileUrl: mediaUrl,
      );
}

Future<ChatAttachSelection?> showChatAttachSheet(
  BuildContext context, {
  ChatAttachTab initialTab = ChatAttachTab.gallery,
  int? conversationId,
}) {
  return showModalBottomSheet<ChatAttachSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ChatAttachSheet(
      initialTab: initialTab,
      conversationId: conversationId,
    ),
  );
}

class _ChatAttachSheet extends StatefulWidget {
  const _ChatAttachSheet({
    this.initialTab = ChatAttachTab.gallery,
    this.conversationId,
  });

  final ChatAttachTab initialTab;
  final int? conversationId;

  @override
  State<_ChatAttachSheet> createState() => _ChatAttachSheetState();
}

class _AttachSheetContact {
  const _AttachSheetContact._({this.hanEat, this.phone})
      : assert(hanEat != null || phone != null);

  final ChatContact? hanEat;
  final PhoneBookContact? phone;

  factory _AttachSheetContact.fromSaved(ChatContact contact) =>
      _AttachSheetContact._(hanEat: contact);

  factory _AttachSheetContact.fromPhone(PhoneBookContact contact) =>
      _AttachSheetContact._(phone: contact);

  String get displayName {
    if (hanEat != null) return hanEat!.user.displayName;
    return phone!.displayName;
  }

  String get subtitle {
    if (hanEat != null) {
      final username = hanEat!.user.username;
      return username != null ? '@$username' : 'в списке контактов';
    }
    final matched = phone!.matchedUser;
    if (matched != null) {
      final label = matched.username ?? matched.name;
      if (label == null || label.isEmpty) return 'в HanWe';
      return label.startsWith('@') ? label : '@$label';
    }
    return phone!.phoneE164;
  }

  ChatUserBrief? get avatarUser {
    if (hanEat != null) return hanEat!.user;
    return phone!.matchedUser?.brief;
  }

  ChatAttachSelection toSelection() {
    if (hanEat != null) {
      return ChatAttachSelection.contact(hanEat!);
    }
    final entry = phone!;
    final matched = entry.matchedUser;
    if (matched != null) {
      final bookName = entry.displayName.trim();
      return ChatAttachSelection.contact(
        ChatContact(
          id: 0,
          user: ChatUserBrief(
            id: matched.id,
            name: bookName.isNotEmpty ? bookName : matched.name,
            username: matched.username,
            avatarUrl: matched.avatarUrl,
          ),
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
    return ChatAttachSelection.phoneContact(
      displayName: entry.displayName,
      phoneE164: entry.phoneE164,
    );
  }
}

class _ChatAttachSheetState extends State<_ChatAttachSheet> {
  ChatAttachTab _tab = ChatAttachTab.gallery;
  final _picker = ImagePicker();
  final _pollFormKey = GlobalKey<ChatPollFormPanelState>();
  final _searchController = TextEditingController();

  final List<XFile> _gallerySelection = [];
  List<_AttachSheetContact> _contacts = [];
  List<ChatRecentFileEntry> _recentFiles = [];
  List<StickerPack> _stickerPacks = [];
  List<ChatRecentStickerEntry> _recentStickers = [];
  List<ChatRecentStickerEntry> _favoriteStickers = [];
  bool _contactsLoading = false;
  bool _recentLoading = true;
  bool _stickerLoading = true;
  bool _stickerBusy = false;
  String? _contactsError;
  String? _stickerError;
  int? _currentUserId;
  List<int> _pinnedPackIds = [];
  String _stickerView = 'packs';
  int? _selectedStickerPackId;
  bool _pollCanSend = false;
  bool _searchVisible = false;
  String _searchQuery = '';
  VoidCallback? _reconnectedListener;

  static const _sheetBgDark = Color(0xFF1C1C1E);
  static const _groupBgDark = Color(0xFF2C2C2E);
  static const _telegramBlue = AppColors.primary;
  static const _brandAccent = AppColors.primary;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _loadContacts();
    _loadRecentFiles();
    _loadStickerHistory();
    unawaited(() async {
      await _loadPinnedPacks();
      if (!mounted) return;
      await _loadStickerPacks();
    }());
    _currentUserId = AuthService.instance.currentUser?.id;
    _reconnectedListener = () {
      if (!mounted) return;
      unawaited(_loadContacts());
    };
    ApiReachabilityService.addReconnectedListener(_reconnectedListener!);
    _searchController.addListener(() {
      final next = _searchController.text.trim().toLowerCase();
      if (_searchQuery == next) return;
      setState(() => _searchQuery = next);
      if (_tab == ChatAttachTab.sticker) {
        unawaited(_loadStickerPacks());
      }
    });
  }

  @override
  void dispose() {
    if (_reconnectedListener != null) {
      ApiReachabilityService.removeReconnectedListener(_reconnectedListener!);
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _contactsLoading = true;
      _contactsError = null;
    });

    List<ChatContact> saved = [];
    Object? savedError;
    List<PhoneBookContact> phoneBook = [];

    try {
      saved = await ChatService.listContacts();
    } catch (e) {
      savedError = e;
    }

    try {
      final result = await PhoneContactsService.syncFromDevice();
      phoneBook = result.phoneBook;
    } on PhoneContactsPermissionDenied {
      // Телефонная книга недоступна — показываем только сохранённые контакты.
    } catch (_) {
      // Ошибка сопоставления с сервером не блокирует локальный список.
    }

    if (!mounted) return;

    final merged = _buildAttachContacts(saved: saved, phoneBook: phoneBook);
    setState(() {
      _contacts = merged;
      _contactsLoading = false;
      _contactsError = merged.isEmpty && savedError != null
          ? 'Не удалось загрузить контакты'
          : null;
    });
  }

  static List<_AttachSheetContact> _buildAttachContacts({
    required List<ChatContact> saved,
    required List<PhoneBookContact> phoneBook,
  }) {
    final out = <_AttachSheetContact>[];
    final seenUserIds = <int>{};
    final seenPhones = <String>{};

    for (final contact in saved) {
      seenUserIds.add(contact.user.id);
      out.add(_AttachSheetContact.fromSaved(contact));
    }

    for (final entry in phoneBook) {
      if (seenPhones.contains(entry.phoneE164)) continue;
      seenPhones.add(entry.phoneE164);

      final matched = entry.matchedUser;
      if (matched != null && seenUserIds.contains(matched.id)) continue;
      if (matched != null) seenUserIds.add(matched.id);

      out.add(_AttachSheetContact.fromPhone(entry));
    }

    out.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return out;
  }

  Future<void> _loadRecentFiles() async {
    final items = await ChatRecentFilesStore.load();
    if (!mounted) return;
    setState(() {
      _recentFiles = items;
      _recentLoading = false;
    });
  }

  Future<void> _loadStickerPacks() async {
    setState(() {
      _stickerLoading = true;
      _stickerError = null;
    });
    try {
      final myPacks = await StickerService.listMyPacks();
      final catalog = await StickerService.listCatalog(
        query: _tab == ChatAttachTab.sticker ? _searchQuery : '',
      );
      final merged = <StickerPack>[];
      final seen = <int>{};
      for (final p in [...myPacks, ...catalog]) {
        if (seen.add(p.id)) merged.add(p);
      }
      merged.sort((a, b) {
        final ai = _pinnedPackIds.indexOf(a.id);
        final bi = _pinnedPackIds.indexOf(b.id);
        final aPinned = ai >= 0;
        final bPinned = bi >= 0;
        if (aPinned && bPinned) return ai.compareTo(bi);
        if (aPinned) return -1;
        if (bPinned) return 1;
        return 0;
      });
      if (!mounted) return;
      setState(() {
        _stickerPacks = merged;
        if (_selectedStickerPackId != null &&
            !_stickerPacks.any((p) => p.id == _selectedStickerPackId)) {
          _selectedStickerPackId = null;
        }
        _stickerLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stickerLoading = false;
        _stickerError = 'Не удалось загрузить стикеры';
      });
    }
  }

  Future<void> _loadStickerHistory() async {
    final recent = await ChatRecentStickersStore.loadRecent();
    final favorites = await ChatRecentStickersStore.loadFavorites();
    if (!mounted) return;
    setState(() {
      _recentStickers = recent;
      _favoriteStickers = favorites;
    });
  }

  Future<void> _loadPinnedPacks() async {
    final ids = await ChatStickerPinnedPacksStore.load();
    if (!mounted) return;
    setState(() {
      _pinnedPackIds = ids;
      if (_stickerPacks.isEmpty) return;
      final sorted = [..._stickerPacks];
      sorted.sort((a, b) {
        final ai = ids.indexOf(a.id);
        final bi = ids.indexOf(b.id);
        final aPinned = ai >= 0;
        final bPinned = bi >= 0;
        if (aPinned && bPinned) return ai.compareTo(bi);
        if (aPinned) return -1;
        if (bPinned) return 1;
        return 0;
      });
      _stickerPacks = sorted;
    });
  }

  void _close([ChatAttachSelection? result]) => Navigator.pop(context, result);

  void _setTab(ChatAttachTab tab) {
    if (_tab == tab) return;
    AppHaptics.selection();
    setState(() {
      _tab = tab;
      _searchVisible = false;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  Future<void> _openMiniAppsCatalog() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MiniAppsCatalogScreen(),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchController.clear();
        _searchQuery = '';
      } else if (_tab == ChatAttachTab.sticker) {
        unawaited(_loadStickerPacks());
      }
    });
  }

  String get _headerTitle {
    switch (_tab) {
      case ChatAttachTab.gallery:
        return 'Фото и видео';
      case ChatAttachTab.gif:
        return 'GIF';
      case ChatAttachTab.file:
        return 'Файл';
      case ChatAttachTab.poll:
        return 'Новый опрос';
      case ChatAttachTab.contact:
        return 'Контакты';
      case ChatAttachTab.location:
        return 'Геопозиция';
      case ChatAttachTab.videoNote:
        return 'Кружок';
      case ChatAttachTab.sticker:
        return 'Стикеры';
    }
  }

  String get _headerSubtitle {
    switch (_tab) {
      case ChatAttachTab.gallery:
        return kIsWeb
            ? 'Нажмите на значок галереи, чтобы выбрать фото'
            : 'Выберите фото или снимите на камеру';
      case ChatAttachTab.gif:
        return 'Выберите GIF или анимированный WebP с устройства';
      case ChatAttachTab.file:
        return 'Документы и недавние';
      case ChatAttachTab.poll:
        return 'Создайте новый опрос';
      case ChatAttachTab.contact:
        return 'Контакты и телефонная книга';
      case ChatAttachTab.location:
        return 'Отправьте текущее местоположение';
      case ChatAttachTab.videoNote:
        return 'Короткое круглое видеосообщение (до 60 сек)';
      case ChatAttachTab.sticker:
        return 'Паки, избранные и недавние';
    }
  }

  bool get _showSearch =>
      _tab == ChatAttachTab.file ||
      _tab == ChatAttachTab.contact ||
      _tab == ChatAttachTab.sticker;

  bool get _showGallerySend =>
      _tab == ChatAttachTab.gallery && _gallerySelection.isNotEmpty;

  bool get _showPollSend => _tab == ChatAttachTab.poll;

  Future<void> _addFromGallery() async {
    final files = await _picker.pickMultipleMedia(
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (files.isEmpty || !mounted) return;
    setState(() {
      for (final f in files) {
        if (!_gallerySelection.any((s) => s.path == f.path)) {
          _gallerySelection.add(f);
        }
      }
    });
  }

  Future<void> _pickGifFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gif', 'webp'],
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final picked = <XFile>[];
    for (final f in result.files) {
      final path = f.path;
      if (path != null && path.isNotEmpty) {
        picked.add(XFile(path, name: f.name));
      } else if (f.bytes != null) {
        picked.add(XFile.fromData(f.bytes!, name: f.name));
      }
    }
    if (picked.isEmpty) return;
    _close(ChatAttachSelection.gallery(picked));
  }

  Future<void> _capturePhoto() async {
    if (kIsWeb) return;
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    setState(() => _gallerySelection.add(file));
  }

  Future<void> _pickDocument({bool scan = false}) async {
    if (scan && !kIsWeb) {
      final scanned = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (scanned != null && mounted) {
        _close(ChatAttachSelection.gallery([scanned]));
      }
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'txt',
        'doc',
        'docx',
        'zip',
        'jpg',
        'jpeg',
        'png',
        'heic',
      ],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
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
    _close(
      ChatAttachSelection.pickedFile(file: file, name: picked.name),
    );
  }

  void _sendPoll() {
    final draft = _pollFormKey.currentState?.buildDraft();
    if (draft == null) return;
    _close(ChatAttachSelection.pollDraft(draft));
  }

  Future<void> _createStickerPack() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый стикерпак'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            hintText: 'Название пака',
          ),
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
    if (!mounted || title == null || title.trim().length < 2) return;
    setState(() => _stickerBusy = true);
    try {
      await StickerService.createPack(title: title.trim());
      await _loadStickerPacks();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось создать стикерпак')),
      );
    } finally {
      if (mounted) setState(() => _stickerBusy = false);
    }
  }

  void _setPackInstalledLocal(int packId, bool installed) {
    setState(() {
      _stickerPacks = [
        for (final p in _stickerPacks)
          if (p.id == packId)
            StickerPack(
              id: p.id,
              title: p.title,
              slug: p.slug,
              ownerUserId: p.ownerUserId,
              isPublic: p.isPublic,
              isInstalled: installed,
              stickers: p.stickers,
              stickersCount: p.stickersCount,
              shareLink: p.shareLink,
            )
          else
            p,
      ];
    });
  }

  Future<void> _toggleInstallStickerPack({
    required int packId,
    required bool isInstalled,
  }) async {
    setState(() => _stickerBusy = true);
    try {
      if (isInstalled) {
        await StickerService.uninstallPack(packId);
        _setPackInstalledLocal(packId, false);
      } else {
        await StickerService.installPack(packId);
        _setPackInstalledLocal(packId, true);
      }
      AppHaptics.selection();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isInstalled
                ? 'Не удалось удалить стикерпак'
                : 'Не удалось установить стикерпак',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _stickerBusy = false);
    }
  }

  Future<void> _addStickerToPack(int packId) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 768,
    );
    if (!mounted || picked == null) return;
    setState(() => _stickerBusy = true);
    try {
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: picked,
        fileType: 'image',
      );
      final url = uploaded.url?.trim();
      if (url == null || url.isEmpty) {
        throw StateError('upload_missing_url');
      }
      await StickerService.addStickerToPack(
        packId: packId,
        mediaUrl: url,
        stickerType: 'static',
      );
      await _loadStickerPacks();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось добавить стикер')),
      );
    } finally {
      if (mounted) setState(() => _stickerBusy = false);
    }
  }

  Future<void> _addAnimatedStickerToPack(int packId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const [
        'gif',
        'webp',
        'webm',
        'mp4',
        'mov',
        'json',
        'lottie',
      ],
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final xFile = kIsWeb
        ? (picked.bytes == null
            ? null
            : XFile.fromData(
                picked.bytes!,
                name: picked.name,
              ))
        : (picked.path == null ? null : XFile(picked.path!));
    if (xFile == null) return;
    final lower = picked.name.toLowerCase();
    final fileType = lower.endsWith('.webm') ||
            lower.endsWith('.mp4') ||
            lower.endsWith('.mov')
        ? 'video'
        : lower.endsWith('.json') || lower.endsWith('.lottie')
            ? 'document'
            : 'image';
    setState(() => _stickerBusy = true);
    try {
      final uploaded = await MediaUploadService.uploadMediaFile(
        file: xFile,
        fileType: fileType,
      );
      final url = uploaded.url?.trim();
      if (url == null || url.isEmpty) {
        throw StateError('upload_missing_url');
      }
      await StickerService.addStickerToPack(
        packId: packId,
        mediaUrl: url,
        stickerType: 'animated',
      );
      await _loadStickerPacks();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Не удалось добавить анимированный стикер')),
      );
    } finally {
      if (mounted) setState(() => _stickerBusy = false);
    }
  }

  Future<void> _pickSticker(StickerItem sticker) async {
    final mediaUrl = sticker.mediaUrl.trim();
    if (mediaUrl.isEmpty) return;
    await ChatRecentStickersStore.remember(
      mediaUrl: mediaUrl,
      emoji: sticker.emoji,
      stickerType: sticker.stickerType,
      stickerId: sticker.id > 0 ? sticker.id : null,
    );
    if (mounted) {
      await _loadStickerHistory();
      _close(
        ChatAttachSelection.sticker(
          mediaUrl: mediaUrl,
          emoji: sticker.emoji,
        ),
      );
    }
  }

  Future<void> _toggleStickerFavorite(
    String mediaUrl, {
    String? emoji,
    String? stickerType,
    int? stickerId,
  }) async {
    await ChatRecentStickersStore.toggleFavorite(
      mediaUrl: mediaUrl,
      emoji: emoji,
      stickerType: stickerType,
      stickerId: stickerId,
    );
    if (!mounted) return;
    await _loadStickerHistory();
  }

  Future<void> _openPackManager(int packId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StickerPackManageScreen(packId: packId),
      ),
    );
    if (!mounted) return;
    await _loadStickerPacks();
  }

  Future<void> _togglePinnedPack(int packId) async {
    await ChatStickerPinnedPacksStore.toggle(packId);
    await _loadPinnedPacks();
    await _loadStickerPacks();
  }

  Future<void> _importPackByLink() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Импорт пака'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Вставьте ссылку или slug',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Импорт'),
          ),
        ],
      ),
    );
    if (!mounted || input == null || input.trim().isEmpty) return;
    final slug = _extractStickerSlug(input.trim());
    if (slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось распознать ссылку на пак')),
      );
      return;
    }
    final installed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StickerPackPreviewScreen(slug: slug),
      ),
    );
    if (installed == true && mounted) {
      await _loadStickerPacks();
    }
  }

  String _extractStickerSlug(String raw) {
    final text = raw.trim();
    if (!text.contains('/')) return text.toLowerCase();
    final uri = Uri.tryParse(text);
    if (uri == null) return '';
    if (uri.pathSegments.isEmpty) return '';
    final idx = uri.pathSegments.indexOf('stickers');
    if (idx >= 0 && idx + 1 < uri.pathSegments.length) {
      return uri.pathSegments[idx + 1].toLowerCase();
    }
    return uri.pathSegments.last.toLowerCase();
  }

  void _selectStickerView(String view) {
    if (_stickerView == view) return;
    setState(() => _stickerView = view);
  }

  void _selectStickerPack(int? packId) {
    if (_selectedStickerPackId == packId) return;
    AppHaptics.selection();
    setState(() {
      _stickerView = 'packs';
      _selectedStickerPackId = packId;
    });
  }

  Future<void> _openPackQuickPreview(int packId) async {
    StickerPack? pack;
    for (final p in _stickerPacks) {
      if (p.id == packId) {
        pack = p;
        break;
      }
    }
    if (pack == null || !mounted) return;
    AppHaptics.medium();
    final currentPack = pack;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _StickerPackQuickPreviewSheet(
        pack: currentPack,
        busy: _stickerBusy,
        onToggleInstall: () async {
          await _toggleInstallStickerPack(
            packId: currentPack.id,
            isInstalled: currentPack.isInstalled,
          );
          if (!ctx.mounted) return;
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  List<_AttachSheetContact> get _filteredContacts {
    if (_searchQuery.isEmpty) return _contacts;
    return _contacts.where((c) {
      final name = c.displayName.toLowerCase();
      final subtitle = c.subtitle.toLowerCase();
      return name.contains(_searchQuery) || subtitle.contains(_searchQuery);
    }).toList();
  }

  List<ChatRecentFileEntry> get _filteredRecentFiles {
    if (_searchQuery.isEmpty) return _recentFiles;
    return _recentFiles
        .where((f) => f.name.toLowerCase().contains(_searchQuery))
        .toList();
  }

  List<StickerPack> get _filteredStickerPacks {
    if (_searchQuery.isEmpty) return _stickerPacks;
    return _stickerPacks
        .where((p) => p.title.toLowerCase().contains(_searchQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inactiveColor = theme.colorScheme.onSurface.withValues(
      alpha: isDark ? 0.72 : 0.68,
    );
    final activeColor = _ChatAttachSheetState._brandAccent.withValues(
      alpha: isDark ? 0.96 : 0.9,
    );
    final sheetBg = isDark ? _sheetBgDark : theme.colorScheme.surface;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              _TelegramHeader(
                title: _headerTitle,
                subtitle: _searchVisible ? null : _headerSubtitle,
                showSearch: _showSearch,
                showSend: _showGallerySend || _showPollSend,
                sendEnabled: _showPollSend ? _pollCanSend : true,
                onClose: () => _close(),
                onSearch: _toggleSearch,
                onSend: () {
                  if (_showPollSend) {
                    _sendPoll();
                  } else {
                    _close(
                      ChatAttachSelection.gallery(
                        List<XFile>.from(_gallerySelection),
                      ),
                    );
                  }
                },
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                ),
                child: _searchVisible && _showSearch
                    ? Padding(
                        key: const ValueKey('attach-search-visible'),
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Поиск',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            filled: true,
                            fillColor: isDark
                                ? _groupBgDark.withValues(alpha: 0.92)
                                : theme.colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 10,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('attach-search-hidden'),
                      ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.02, 0.0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<ChatAttachTab>(_tab),
                    child: _buildBody(scrollController, isDark),
                  ),
                ),
              ),
              _TelegramAttachDock(
                selected: _tab,
                onSelect: _setTab,
                onOpenMiniApps: () => unawaited(_openMiniAppsCatalog()),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ScrollController scrollController, bool isDark) {
    switch (_tab) {
      case ChatAttachTab.gallery:
        return _GalleryPanel(
          scrollController: scrollController,
          selection: _gallerySelection,
          onAdd: _addFromGallery,
          onCamera: kIsWeb ? null : _capturePhoto,
          onRemove: (i) => setState(() => _gallerySelection.removeAt(i)),
          isDark: isDark,
        );
      case ChatAttachTab.gif:
        return _GifPickPanel(
          scrollController: scrollController,
          conversationId: widget.conversationId,
          onPickDevice: () => unawaited(_pickGifFiles()),
          onPickRecent: (url) => _close(ChatAttachSelection.gifResend(url)),
          isDark: isDark,
        );
      case ChatAttachTab.location:
        return _LocationPickPanel(
          scrollController: scrollController,
          onSend: (lat, lng, {int? livePeriodSeconds}) => _close(
            ChatAttachSelection.location(
              latitude: lat,
              longitude: lng,
              livePeriodSeconds: livePeriodSeconds,
            ),
          ),
          isDark: isDark,
        );
      case ChatAttachTab.videoNote:
        return _VideoNotePickPanel(
          scrollController: scrollController,
          onRecord: () => _close(ChatAttachSelection.videoNote()),
          isDark: isDark,
        );
      case ChatAttachTab.file:
        return _FilePanel(
          scrollController: scrollController,
          recentFiles: _filteredRecentFiles,
          loading: _recentLoading,
          isDark: isDark,
          onPickGallery: () => _setTab(ChatAttachTab.gallery),
          onPickFiles: () => _pickDocument(),
          onScanDocument: () => _pickDocument(scan: true),
          onRecentTap: (entry) {
            final url = entry.mediaUrl;
            if (url != null && url.isNotEmpty) {
              _close(
                ChatAttachSelection.resendFile(
                  name: entry.name,
                  mediaUrl: url,
                ),
              );
            } else {
              _pickDocument();
            }
          },
        );
      case ChatAttachTab.poll:
        return ChatPollFormPanel(
          key: _pollFormKey,
          scrollController: scrollController,
          onValidityChanged: (v) {
            if (_pollCanSend != v) setState(() => _pollCanSend = v);
          },
        );
      case ChatAttachTab.contact:
        return _ContactsPanel(
          scrollController: scrollController,
          contacts: _filteredContacts,
          loading: _contactsLoading,
          error: _contactsError,
          onRetry: _loadContacts,
          onSelect: (c) => _close(c.toSelection()),
          isDark: isDark,
        );
      case ChatAttachTab.sticker:
        return _StickerPanel(
          scrollController: scrollController,
          packs: _filteredStickerPacks,
          recentStickers: _recentStickers,
          favoriteStickers: _favoriteStickers,
          loading: _stickerLoading,
          busy: _stickerBusy,
          error: _stickerError,
          onRetry: _loadStickerPacks,
          onCreatePack: _createStickerPack,
          onToggleInstallPack: _toggleInstallStickerPack,
          onAddSticker: _addStickerToPack,
          onAddAnimatedSticker: _addAnimatedStickerToPack,
          currentUserId: _currentUserId,
          onOpenPackManager: _openPackManager,
          pinnedPackIds: _pinnedPackIds,
          onTogglePinnedPack: _togglePinnedPack,
          onImportByLink: _importPackByLink,
          stickerView: _stickerView,
          selectedPackId: _selectedStickerPackId,
          onSelectView: _selectStickerView,
          onSelectPack: _selectStickerPack,
          onPreviewPack: _openPackQuickPreview,
          onPickSticker: _pickSticker,
          onToggleFavorite: _toggleStickerFavorite,
          isDark: isDark,
        );
    }
  }
}

class _GifPickPanel extends StatefulWidget {
  const _GifPickPanel({
    required this.scrollController,
    required this.onPickDevice,
    required this.onPickRecent,
    required this.isDark,
    this.conversationId,
  });

  final ScrollController scrollController;
  final VoidCallback onPickDevice;
  final ValueChanged<String> onPickRecent;
  final bool isDark;
  final int? conversationId;

  @override
  State<_GifPickPanel> createState() => _GifPickPanelState();
}

class _GifPickPanelState extends State<_GifPickPanel> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<String> _recentUrls = const [];
  List<GifCatalogItem> _catalogItems = const [];
  String? _catalogNext;
  bool _recentLoading = true;
  bool _catalogLoading = false;
  bool _catalogLoadingMore = false;
  bool _catalogConfigured = true;
  String? _catalogError;
  String _activeQuery = '';

  bool _isGifUrl(String url) {
    final path = url.split('?').first.toLowerCase();
    return path.endsWith('.gif') || path.endsWith('.webp');
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecent());
    unawaited(_loadCatalog());
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final q = _searchController.text.trim();
      if (q == _activeQuery) return;
      unawaited(_loadCatalog(query: q));
    });
  }

  Future<void> _loadRecent() async {
    final local = await ChatRecentGifsStore.load();
    final urls = <String>[
      for (final e in local)
        if (_isGifUrl(e.mediaUrl)) e.mediaUrl,
    ];
    final cid = widget.conversationId;
    if (cid != null) {
      try {
        final page = await ChatService.listChatMedia(
          conversationId: cid,
          kind: 'photos',
          limit: 40,
        );
        for (final msg in page.items) {
          final url = msg.mediaUrl?.trim();
          if (url == null || url.isEmpty || !_isGifUrl(url)) continue;
          if (!urls.contains(url)) urls.add(url);
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _recentUrls = urls.take(36).toList();
      _recentLoading = false;
    });
  }

  Future<void> _loadCatalog({String? query, bool more = false}) async {
    final q = (query ?? _activeQuery).trim();
    if (more) {
      final next = _catalogNext;
      if (next == null || next.isEmpty || _catalogLoadingMore) return;
      setState(() => _catalogLoadingMore = true);
    } else {
      setState(() {
        _activeQuery = q;
        _catalogLoading = true;
        _catalogError = null;
        _catalogItems = const [];
        _catalogNext = null;
      });
    }
    try {
      final page = more
          ? (q.isEmpty
              ? await GifSearchService.featured(pos: _catalogNext)
              : await GifSearchService.search(query: q, pos: _catalogNext))
          : (q.isEmpty
              ? await GifSearchService.featured()
              : await GifSearchService.search(query: q));
      if (!mounted) return;
      setState(() {
        _catalogConfigured = page.configured;
        _catalogItems = more
            ? [..._catalogItems, ...page.items]
            : page.items;
        _catalogNext = page.next;
        _catalogLoading = false;
        _catalogLoadingMore = false;
        _catalogError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _catalogLoading = false;
        _catalogLoadingMore = false;
        if (!more) {
          _catalogItems = const [];
          _catalogNext = null;
        }
        _catalogError = 'Не удалось загрузить каталог GIF';
      });
    }
  }

  Widget _gifTile(
    BuildContext context, {
    required String sendUrl,
    String? previewUrl,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final display = (previewUrl != null && previewUrl.isNotEmpty)
        ? previewUrl
        : sendUrl;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onPickRecent(sendUrl),
        child: ChatStickerTile(
          mediaUrl: ServerConfig.resolveMediaUrl(display),
          animated: true,
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _gifUrlGrid(BuildContext context, List<String> urls) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: urls.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) =>
          _gifTile(context, sendUrl: urls[index]),
    );
  }

  Widget _gifCatalogGrid(BuildContext context, List<GifCatalogItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return _gifTile(
          context,
          sendUrl: item.url,
          previewUrl: item.previewUrl,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final searching = _activeQuery.isNotEmpty;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Поиск GIF',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Очистить',
                    onPressed: () {
                      _searchController.clear();
                      unawaited(_loadCatalog(query: ''));
                    },
                    icon: const Icon(Icons.close),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: widget.onPickDevice,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Выбрать GIF с устройства'),
        ),
        const SizedBox(height: 16),
        _sectionTitle(
          context,
          searching ? 'Результаты' : 'Популярные',
        ),
        const SizedBox(height: 8),
        if (_catalogLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_catalogError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text(
                  _catalogError!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                TextButton(
                  onPressed: () => unawaited(_loadCatalog()),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          )
        else if (!_catalogConfigured)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Каталог GIF пока недоступен. Можно выбрать файл с устройства '
              'или недавние GIF ниже.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          )
        else if (_catalogItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              searching
                  ? 'Ничего не найдено. Попробуйте другой запрос.'
                  : 'Пока нет популярных GIF.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          )
        else ...[
          _gifCatalogGrid(context, _catalogItems),
          if (_catalogNext != null && _catalogNext!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _catalogLoadingMore
                    ? null
                    : () => unawaited(_loadCatalog(more: true)),
                child: _catalogLoadingMore
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Ещё'),
              ),
            ),
          ],
        ],
        if (!searching) ...[
          const SizedBox(height: 20),
          _sectionTitle(context, 'Недавние GIF'),
          const SizedBox(height: 8),
          if (_recentLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_recentUrls.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Icon(
                    Icons.gif_box_outlined,
                    size: 40,
                    color: scheme.primary.withValues(alpha: 0.85),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Пока нет GIF из истории чата.\n'
                    'Отправьте .gif / .webp — они появятся здесь.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            )
          else
            _gifUrlGrid(context, _recentUrls),
        ],
      ],
    );
  }
}

class _LocationPickPanel extends StatefulWidget {
  const _LocationPickPanel({
    required this.scrollController,
    required this.onSend,
    required this.isDark,
  });

  final ScrollController scrollController;
  final void Function(
    double latitude,
    double longitude, {
    int? livePeriodSeconds,
  }) onSend;
  final bool isDark;

  @override
  State<_LocationPickPanel> createState() => _LocationPickPanelState();
}

class _LocationPickPanelState extends State<_LocationPickPanel> {
  static const _livePeriods = <(int, String)>[
    (900, '15 мин'),
    (3600, '1 час'),
    (28800, '8 часов'),
  ];

  bool _loading = true;
  String? _error;
  DeviceLatLng? _position;
  int _livePeriodSeconds = 900;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocation());
  }

  Future<void> _loadLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pos = await getDeviceLocation();
      if (!mounted) return;
      if (pos == null) {
        setState(() {
          _loading = false;
          _error = kIsWeb
              ? 'Не удалось получить геолокацию. Разрешите доступ в браузере.'
              : 'Не удалось получить геолокацию. Включите GPS и разрешите доступ.';
          _position = null;
        });
        return;
      }
      setState(() {
        _loading = false;
        _position = pos;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось получить геолокацию';
        _position = null;
      });
    }
  }

  Future<void> _copyCoords() async {
    final pos = _position;
    if (pos == null) return;
    final text =
        '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Координаты скопированы')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pos = _position;
    final payload = pos == null
        ? null
        : ChatLocationPayload(
            latitude: pos.latitude,
            longitude: pos.longitude,
          );

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          'Моя геопозиция',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (payload != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 2,
              child: Image.network(
                payload.staticMapUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.map_outlined,
                    size: 40,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${payload.latitude.toStringAsFixed(5)}, ${payload.longitude.toStringAsFixed(5)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_loadLocation()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Обновить'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_copyCoords()),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Копировать'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => widget.onSend(pos!.latitude, pos.longitude),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Отправить'),
          ),
          const SizedBox(height: 20),
          Text(
            'Транслировать геопозицию',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _livePeriods)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: _livePeriodSeconds == entry.$1,
                  onSelected: (_) =>
                      setState(() => _livePeriodSeconds = entry.$1),
                ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => widget.onSend(
              pos!.latitude,
              pos.longitude,
              livePeriodSeconds: _livePeriodSeconds,
            ),
            icon: const Icon(Icons.my_location_outlined),
            label: const Text('Начать трансляцию'),
          ),
        ] else ...[
          Icon(
            Icons.location_off_outlined,
            size: 48,
            color: scheme.error.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Геолокация недоступна',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => unawaited(_loadLocation()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Повторить'),
          ),
        ],
      ],
    );
  }
}

class _VideoNotePickPanel extends StatelessWidget {
  const _VideoNotePickPanel({
    required this.scrollController,
    required this.onRecord,
    required this.isDark,
  });

  final ScrollController scrollController;
  final VoidCallback onRecord;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const SizedBox(height: 24),
        Icon(
          Icons.videocam_outlined,
          size: 56,
          color: scheme.primary.withValues(alpha: 0.9),
        ),
        const SizedBox(height: 16),
        Text(
          'Видеосообщение',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Запишите короткое видео — оно отправится кружком, как в Telegram.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: onRecord,
          icon: const Icon(Icons.fiber_manual_record),
          label: const Text('Записать кружок'),
        ),
      ],
    );
  }
}

class _TelegramHeader extends StatelessWidget {
  const _TelegramHeader({
    required this.title,
    this.subtitle,
    required this.showSearch,
    required this.showSend,
    required this.sendEnabled,
    required this.onClose,
    required this.onSearch,
    required this.onSend,
  });

  final String title;
  final String? subtitle;
  final bool showSearch;
  final bool showSend;
  final bool sendEnabled;
  final VoidCallback onClose;
  final VoidCallback onSearch;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerChipBg = isDark
        ? _ChatAttachSheetState._groupBgDark.withValues(alpha: 0.86)
        : theme.colorScheme.surfaceContainerHighest;
    final actionBg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : theme.colorScheme.surfaceContainerHigh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          _HeaderRoundAction(
            icon: Icons.close,
            onTap: onClose,
            backgroundColor: actionBg,
            tooltip: 'Закрыть',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: subtitle == null ? 44 : 50,
              decoration: BoxDecoration(
                color: headerChipBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10.5,
                          height: 1.1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (showSend)
            FilledButton(
              onPressed: sendEnabled ? onSend : null,
              style: FilledButton.styleFrom(
                backgroundColor:
                    sendEnabled ? _ChatAttachSheetState._brandAccent : actionBg,
                foregroundColor: sendEnabled
                    ? Colors.white
                    : theme.colorScheme.onSurfaceVariant,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(21),
                ),
              ),
              child: const Text(
                'Отправить',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          else if (showSearch)
            _HeaderRoundAction(
              icon: Icons.search,
              onTap: onSearch,
              backgroundColor: actionBg,
              tooltip: 'Поиск',
            )
          else
            const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _HeaderRoundAction extends StatelessWidget {
  const _HeaderRoundAction({
    required this.icon,
    required this.onTap,
    required this.backgroundColor,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color backgroundColor;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(21),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(21),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 21),
          ),
        ),
      ),
    );
  }
}

class _FilePanel extends StatelessWidget {
  const _FilePanel({
    required this.scrollController,
    required this.recentFiles,
    required this.loading,
    required this.isDark,
    required this.onPickGallery,
    required this.onPickFiles,
    required this.onScanDocument,
    required this.onRecentTap,
  });

  final ScrollController scrollController;
  final List<ChatRecentFileEntry> recentFiles;
  final bool loading;
  final bool isDark;
  final VoidCallback onPickGallery;
  final VoidCallback onPickFiles;
  final VoidCallback onScanDocument;
  final ValueChanged<ChatRecentFileEntry> onRecentTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupBg = isDark
        ? _ChatAttachSheetState._groupBgDark
        : theme.colorScheme.surfaceContainerHighest;
    final dateFmt = DateFormat('d MMM yyyy, HH:mm');

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      children: [
        _GroupedSurface(
          color: groupBg,
          children: [
            _FileActionTile(
              icon: Icons.photo_outlined,
              label: 'Выбрать из Галереи',
              onTap: onPickGallery,
            ),
            _divider(theme),
            _FileActionTile(
              icon: Icons.cloud_outlined,
              label: 'Выбрать из файлов',
              onTap: onPickFiles,
            ),
            if (!kIsWeb) ...[
              _divider(theme),
              _FileActionTile(
                icon: Icons.document_scanner_outlined,
                label: 'Сканировать документ',
                onTap: onScanDocument,
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'НЕДАВНО ОТПРАВЛЕННЫЕ',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (recentFiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Здесь появятся недавно отправленные файлы',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          _GroupedSurface(
            color: groupBg,
            children: [
              for (var i = 0; i < recentFiles.length; i++) ...[
                if (i > 0) _divider(theme),
                _RecentFileTile(
                  entry: recentFiles[i],
                  dateLabel: dateFmt.format(recentFiles[i].sentAt),
                  onTap: () => onRecentTap(recentFiles[i]),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _divider(ThemeData theme) {
    return Divider(
      height: 1,
      indent: 52,
      color: theme.dividerColor.withValues(alpha: 0.2),
    );
  }
}

class _FileActionTile extends StatelessWidget {
  const _FileActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      leading: Icon(icon, color: _ChatAttachSheetState._brandAccent, size: 24),
      title: Text(
        label,
        style: const TextStyle(
          color: _ChatAttachSheetState._brandAccent,
          fontSize: 17,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _RecentFileTile extends StatelessWidget {
  const _RecentFileTile({
    required this.entry,
    required this.dateLabel,
    required this.onTap,
  });

  final ChatRecentFileEntry entry;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext = entry.name.contains('.')
        ? entry.name.split('.').last.toUpperCase()
        : 'FILE';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _fileThumbColor(ext),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          ext.length <= 4 ? ext : 'DOC',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${formatChatFileSize(entry.sizeBytes)} · $dateLabel',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }

  Color _fileThumbColor(String ext) {
    switch (ext) {
      case 'ZIP':
      case 'RAR':
        return const Color(0xFFFF9500);
      case 'PDF':
        return const Color(0xFFFF3B30);
      case 'PNG':
      case 'JPG':
      case 'JPEG':
      case 'HEIC':
        return const Color(0xFF34C759);
      default:
        return _ChatAttachSheetState._telegramBlue;
    }
  }
}

class _GroupedSurface extends StatelessWidget {
  const _GroupedSurface({required this.color, required this.children});

  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _GalleryPanel extends StatelessWidget {
  const _GalleryPanel({
    required this.scrollController,
    required this.selection,
    required this.onAdd,
    this.onCamera,
    required this.onRemove,
    required this.isDark,
  });

  final ScrollController scrollController;
  final List<XFile> selection;
  final VoidCallback onAdd;
  final VoidCallback? onCamera;
  final ValueChanged<int> onRemove;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    if (onCamera != null) {
      cells.add(_GalleryAddTile(
        icon: Icons.photo_camera_outlined,
        onTap: onCamera!,
        isDark: isDark,
      ));
    }
    cells.add(_GalleryAddTile(
      icon: Icons.photo_library_outlined,
      onTap: onAdd,
      isDark: isDark,
    ));
    for (var i = 0; i < selection.length; i++) {
      cells.add(_GalleryThumb(
        file: selection[i],
        onTap: () => onRemove(i),
        isDark: isDark,
      ));
    }

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(1, 0, 1, 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      ),
      itemCount: cells.length,
      itemBuilder: (_, i) => cells[i],
    );
  }
}

class _GalleryAddTile extends StatelessWidget {
  const _GalleryAddTile({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark
          ? _ChatAttachSheetState._groupBgDark
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Icon(
            icon,
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({
    required this.file,
    required this.onTap,
    required this.isDark,
  });

  final XFile file;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (kIsWeb)
          Container(color: const Color(0xFF3A3A3C))
        else
          Image.file(File(file.path), fit: BoxFit.cover),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.check, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _StickerPanel extends StatelessWidget {
  const _StickerPanel({
    required this.scrollController,
    required this.packs,
    required this.recentStickers,
    required this.favoriteStickers,
    required this.loading,
    required this.busy,
    required this.error,
    required this.onRetry,
    required this.onCreatePack,
    required this.onToggleInstallPack,
    required this.onAddSticker,
    required this.onAddAnimatedSticker,
    required this.currentUserId,
    required this.onOpenPackManager,
    required this.pinnedPackIds,
    required this.onTogglePinnedPack,
    required this.onImportByLink,
    required this.stickerView,
    required this.selectedPackId,
    required this.onSelectView,
    required this.onSelectPack,
    required this.onPreviewPack,
    required this.onPickSticker,
    required this.onToggleFavorite,
    required this.isDark,
  });

  final ScrollController scrollController;
  final List<StickerPack> packs;
  final List<ChatRecentStickerEntry> recentStickers;
  final List<ChatRecentStickerEntry> favoriteStickers;
  final bool loading;
  final bool busy;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onCreatePack;
  final Future<void> Function({
    required int packId,
    required bool isInstalled,
  }) onToggleInstallPack;
  final ValueChanged<int> onAddSticker;
  final ValueChanged<int> onAddAnimatedSticker;
  final int? currentUserId;
  final ValueChanged<int> onOpenPackManager;
  final List<int> pinnedPackIds;
  final ValueChanged<int> onTogglePinnedPack;
  final VoidCallback onImportByLink;
  final String stickerView;
  final int? selectedPackId;
  final ValueChanged<String> onSelectView;
  final ValueChanged<int?> onSelectPack;
  final ValueChanged<int> onPreviewPack;
  final ValueChanged<StickerItem> onPickSticker;
  final Future<void> Function(
    String mediaUrl, {
    String? emoji,
    String? stickerType,
    int? stickerId,
  }) onToggleFavorite;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupBg = isDark
        ? _ChatAttachSheetState._groupBgDark
        : theme.colorScheme.surfaceContainerHighest;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      );
    }
    final favoriteUrls = favoriteStickers
        .map((e) => e.mediaUrl.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final editablePacks = currentUserId == null
        ? const <StickerPack>[]
        : packs.where((p) => p.ownerUserId == currentUserId).toList();
    StickerPack? targetEditablePack;
    if (editablePacks.isNotEmpty) {
      for (final p in editablePacks) {
        if (p.id == selectedPackId) {
          targetEditablePack = p;
          break;
        }
      }
      targetEditablePack ??= editablePacks.first;
    }
    final visiblePacks = selectedPackId == null
        ? packs
        : packs.where((p) => p.id == selectedPackId).toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: groupBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _stickerSwitchChip(
                      theme: theme,
                      label: 'Паки',
                      selected: stickerView == 'packs',
                      onTap: () => onSelectView('packs'),
                    ),
                    const SizedBox(width: 6),
                    _stickerSwitchChip(
                      theme: theme,
                      label: 'Избранные',
                      selected: stickerView == 'favorites',
                      onTap: () => onSelectView('favorites'),
                    ),
                    const SizedBox(width: 6),
                    _stickerSwitchChip(
                      theme: theme,
                      label: 'Недавние',
                      selected: stickerView == 'recent',
                      onTap: () => onSelectView('recent'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (stickerView == 'packs' && packs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'У вас пока нет установленных стикерпаков',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (stickerView == 'packs')
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _StickerPacksContent(
                    key: ValueKey<int?>(selectedPackId),
                    packs: visiblePacks,
                    busy: busy,
                    currentUserId: currentUserId,
                    pinnedPackIds: pinnedPackIds,
                    groupBg: groupBg,
                    theme: theme,
                    favoriteUrls: favoriteUrls,
                    onToggleInstallPack: onToggleInstallPack,
                    onOpenPackManager: onOpenPackManager,
                    onTogglePinnedPack: onTogglePinnedPack,
                    onPickSticker: onPickSticker,
                    onToggleFavorite: onToggleFavorite,
                  ),
                ),
              if (stickerView == 'favorites' &&
                  favoriteStickers.isNotEmpty) ...[
                const SizedBox(height: 6),
                _StickerSectionGrid(
                  title: 'Избранные',
                  items: favoriteStickers.take(24).toList(),
                  groupBg: groupBg,
                  theme: theme,
                  favoriteUrls: favoriteUrls,
                  onTap: (entry) => onPickSticker(
                    StickerItem(
                      id: entry.stickerId ?? 0,
                      mediaUrl: entry.mediaUrl,
                      emoji: entry.emoji,
                      stickerType: entry.stickerType ?? 'static',
                    ),
                  ),
                  onLongPress: (entry) => onToggleFavorite(
                    entry.mediaUrl,
                    emoji: entry.emoji,
                    stickerType: entry.stickerType,
                    stickerId: entry.stickerId,
                  ),
                ),
              ],
              if (stickerView == 'recent' && recentStickers.isNotEmpty) ...[
                const SizedBox(height: 6),
                _StickerSectionGrid(
                  title: 'Недавние',
                  items: recentStickers.take(24).toList(),
                  groupBg: groupBg,
                  theme: theme,
                  favoriteUrls: favoriteUrls,
                  onTap: (entry) => onPickSticker(
                    StickerItem(
                      id: entry.stickerId ?? 0,
                      mediaUrl: entry.mediaUrl,
                      emoji: entry.emoji,
                      stickerType: entry.stickerType ?? 'static',
                    ),
                  ),
                  onLongPress: (entry) => onToggleFavorite(
                    entry.mediaUrl,
                    emoji: entry.emoji,
                    stickerType: entry.stickerType,
                    stickerId: entry.stickerId,
                  ),
                ),
              ],
              if (stickerView == 'favorites' && favoriteStickers.isEmpty)
                _emptyHint(theme, 'Избранных стикеров пока нет'),
              if (stickerView == 'recent' && recentStickers.isEmpty)
                _emptyHint(theme, 'Недавних стикеров пока нет'),
            ],
          ),
        ),
        if (stickerView == 'packs' && packs.isNotEmpty)
          _StickerPacksBottomBar(
            packs: packs,
            selectedPackId: selectedPackId,
            onSelectPack: onSelectPack,
            onPreviewPack: onPreviewPack,
            isDark: isDark,
          ),
      ],
    );
  }

  Widget _emptyHint(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _stickerSwitchChip({
    required ThemeData theme,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerPacksContent extends StatelessWidget {
  const _StickerPacksContent({
    super.key,
    required this.packs,
    required this.busy,
    required this.currentUserId,
    required this.pinnedPackIds,
    required this.groupBg,
    required this.theme,
    required this.favoriteUrls,
    required this.onToggleInstallPack,
    required this.onOpenPackManager,
    required this.onTogglePinnedPack,
    required this.onPickSticker,
    required this.onToggleFavorite,
  });

  final List<StickerPack> packs;
  final bool busy;
  final int? currentUserId;
  final List<int> pinnedPackIds;
  final Color groupBg;
  final ThemeData theme;
  final Set<String> favoriteUrls;
  final Future<void> Function({
    required int packId,
    required bool isInstalled,
  }) onToggleInstallPack;
  final ValueChanged<int> onOpenPackManager;
  final ValueChanged<int> onTogglePinnedPack;
  final ValueChanged<StickerItem> onPickSticker;
  final Future<void> Function(
    String mediaUrl, {
    String? emoji,
    String? stickerType,
    int? stickerId,
  }) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      children: [
        for (final pack in packs) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    pack.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => onToggleInstallPack(
                            packId: pack.id,
                            isInstalled: pack.isInstalled,
                          ),
                  child: Text(pack.isInstalled ? 'Удалить' : 'Установить'),
                ),
                if (pack.ownerUserId == currentUserId)
                  IconButton(
                    onPressed: busy ? null : () => onOpenPackManager(pack.id),
                    tooltip: 'Управление паком',
                    icon: const Icon(Icons.tune),
                  ),
                IconButton(
                  onPressed: busy ? null : () => onTogglePinnedPack(pack.id),
                  tooltip: pinnedPackIds.contains(pack.id)
                      ? 'Открепить'
                      : 'Закрепить',
                  icon: Icon(
                    pinnedPackIds.contains(pack.id)
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                  ),
                ),
              ],
            ),
          ),
          if (pack.stickers.isNotEmpty)
            _StickerSectionGrid(
              title: null,
              items: [
                for (final s in pack.stickers)
                  ChatRecentStickerEntry(
                    mediaUrl: s.mediaUrl,
                    emoji: s.emoji,
                    stickerType: s.stickerType,
                    stickerId: s.id,
                  ),
              ],
              groupBg: groupBg,
              theme: theme,
              favoriteUrls: favoriteUrls,
              onTap: (entry) => onPickSticker(
                StickerItem(
                  id: entry.stickerId ?? 0,
                  mediaUrl: entry.mediaUrl,
                  emoji: entry.emoji,
                  stickerType: entry.stickerType ?? 'static',
                ),
              ),
              onLongPress: (entry) => onToggleFavorite(
                entry.mediaUrl,
                emoji: entry.emoji,
                stickerType: entry.stickerType,
                stickerId: entry.stickerId,
              ),
            ),
          if (pack.stickers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Пока без стикеров',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _StickerQuickActions extends StatelessWidget {
  const _StickerQuickActions({
    required this.busy,
    required this.editablePackId,
    required this.editablePackTitle,
    required this.onCreatePack,
    required this.onImportByLink,
    required this.onAddSticker,
    required this.onAddAnimatedSticker,
    required this.onOpenPackManager,
  });

  final bool busy;
  final int? editablePackId;
  final String? editablePackTitle;
  final VoidCallback onCreatePack;
  final VoidCallback onImportByLink;
  final ValueChanged<int> onAddSticker;
  final ValueChanged<int> onAddAnimatedSticker;
  final ValueChanged<int> onOpenPackManager;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: busy ? null : onImportByLink,
              icon: const Icon(Icons.download_for_offline_outlined, size: 18),
              label: const Text('Импорт'),
            ),
          ),
          const SizedBox(width: 8),
          if (editablePackId != null)
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : () => onAddSticker(editablePackId!),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Добавить'),
              ),
            ),
          if (editablePackId != null) const SizedBox(width: 8),
          PopupMenuButton<_StickerQuickAction>(
            tooltip: 'Ещё действия',
            enabled: !busy,
            onSelected: (value) {
              switch (value) {
                case _StickerQuickAction.createPack:
                  onCreatePack();
                  break;
                case _StickerQuickAction.addAnimated:
                  if (editablePackId != null) {
                    onAddAnimatedSticker(editablePackId!);
                  }
                  break;
                case _StickerQuickAction.managePack:
                  if (editablePackId != null) {
                    onOpenPackManager(editablePackId!);
                  }
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _StickerQuickAction.createPack,
                child: Text('Создать стикерпак'),
              ),
              if (editablePackId != null)
                PopupMenuItem(
                  value: _StickerQuickAction.addAnimated,
                  child: Text(
                      'Добавить анимированный в "${editablePackTitle ?? ''}"'),
                ),
              if (editablePackId != null)
                const PopupMenuItem(
                  value: _StickerQuickAction.managePack,
                  child: Text('Управление паком'),
                ),
            ],
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.more_horiz_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StickerQuickAction { createPack, addAnimated, managePack }

class _StickerPackQuickPreviewSheet extends StatefulWidget {
  const _StickerPackQuickPreviewSheet({
    required this.pack,
    required this.busy,
    required this.onToggleInstall,
  });

  final StickerPack pack;
  final bool busy;
  final Future<void> Function() onToggleInstall;

  @override
  State<_StickerPackQuickPreviewSheet> createState() =>
      _StickerPackQuickPreviewSheetState();
}

class _StickerPackQuickPreviewSheetState
    extends State<_StickerPackQuickPreviewSheet> {
  bool _localBusy = false;

  Future<void> _handleToggleInstall() async {
    if (_localBusy || widget.busy) return;
    setState(() => _localBusy = true);
    try {
      await widget.onToggleInstall();
    } finally {
      if (mounted) {
        setState(() => _localBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final previewItems = pack.stickers.take(12).toList();
    final actionBusy = widget.busy || _localBusy;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pack.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${pack.stickersCount} стикеров',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (previewItems.isNotEmpty)
              SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: previewItems.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final sticker = previewItems[i];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        ServerConfig.resolveMediaUrl(sticker.mediaUrl),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 72,
                          height: 72,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: actionBusy ? null : _handleToggleInstall,
                icon: actionBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        pack.isInstalled
                            ? Icons.delete_outline_rounded
                            : Icons.download_for_offline_outlined,
                      ),
                label: Text(
                  actionBusy
                      ? 'Подождите...'
                      : (pack.isInstalled
                          ? 'Удалить из установленных'
                          : 'Установить'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerPacksBottomBar extends StatelessWidget {
  const _StickerPacksBottomBar({
    required this.packs,
    required this.selectedPackId,
    required this.onSelectPack,
    required this.onPreviewPack,
    required this.isDark,
  });

  final List<StickerPack> packs;
  final int? selectedPackId;
  final ValueChanged<int?> onSelectPack;
  final ValueChanged<int> onPreviewPack;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isDark
        ? _ChatAttachSheetState._sheetBgDark
        : theme.colorScheme.surfaceContainerLow;
    return SafeArea(
      top: false,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            top: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.2),
            ),
          ),
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          children: [
            _StickerPackBottomTab(
              selected: selectedPackId == null,
              tooltip: 'Все',
              child: const Icon(Icons.apps_rounded, size: 20),
              onTap: () => onSelectPack(null),
            ),
            for (final pack in packs)
              _StickerPackBottomTab(
                selected: selectedPackId == pack.id,
                tooltip: pack.title,
                child: _StickerPackAvatar(pack: pack),
                onTap: () => onSelectPack(pack.id),
                onLongPress: () => onPreviewPack(pack.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _StickerPackBottomTab extends StatelessWidget {
  const _StickerPackBottomTab({
    required this.selected,
    required this.tooltip,
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  final bool selected;
  final String tooltip;
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerPackAvatar extends StatelessWidget {
  const _StickerPackAvatar({required this.pack});

  final StickerPack pack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = pack.stickers.isEmpty ? null : pack.stickers.first.mediaUrl;
    if (first == null || first.trim().isEmpty) {
      return const Icon(Icons.emoji_emotions_outlined, size: 20);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.network(
        ServerConfig.resolveMediaUrl(first),
        width: 28,
        height: 28,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.image_not_supported_outlined,
          color: theme.colorScheme.onSurfaceVariant,
          size: 18,
        ),
      ),
    );
  }
}

class _StickerSectionGrid extends StatelessWidget {
  const _StickerSectionGrid({
    required this.title,
    required this.items,
    required this.groupBg,
    required this.theme,
    required this.favoriteUrls,
    required this.onTap,
    this.onLongPress,
  });

  final String? title;
  final List<ChatRecentStickerEntry> items;
  final Color groupBg;
  final ThemeData theme;
  final Set<String> favoriteUrls;
  final ValueChanged<ChatRecentStickerEntry> onTap;
  final ValueChanged<ChatRecentStickerEntry>? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Text(
              title!,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            final isFavorite = favoriteUrls.contains(item.mediaUrl.trim());
            final lower = item.mediaUrl.toLowerCase();
            final isLottieLike = lower.endsWith('.json') ||
                lower.endsWith('.lottie') ||
                lower.endsWith('.tgs');
            final isAnimated =
                (item.stickerType ?? '').toLowerCase() == 'animated' ||
                    lower.endsWith('.gif') ||
                    lower.endsWith('.webm') ||
                    lower.endsWith('.mp4') ||
                    lower.endsWith('.mov') ||
                    isLottieLike;
            return Material(
              color: groupBg,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(item),
                onLongPress:
                    onLongPress == null ? null : () => onLongPress!(item),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isLottieLike)
                      Icon(
                        Icons.animation_outlined,
                        color: theme.colorScheme.primary,
                        size: 26,
                      )
                    else
                      Image.network(
                        ServerConfig.resolveMediaUrl(item.mediaUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.broken_image_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (isAnimated)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    if (isFavorite)
                      const Positioned(
                        top: 4,
                        right: 4,
                        child: Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: 16,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ContactsPanel extends StatelessWidget {
  const _ContactsPanel({
    required this.scrollController,
    required this.contacts,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onSelect,
    required this.isDark,
  });

  final ScrollController scrollController;
  final List<_AttachSheetContact> contacts;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<_AttachSheetContact> onSelect;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      );
    }
    if (contacts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Нет контактов.\nДобавьте людей в разделе «Контакты» '
            'или импортируйте телефонную книгу.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final grouped = _groupContacts(contacts);
    final letters = grouped.keys.toList()..sort(_letterSort);

    return Stack(
      children: [
        ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(12, 0, 28, 8),
          itemCount: letters.length,
          itemBuilder: (context, sectionIndex) {
            final letter = letters[sectionIndex];
            final sectionContacts = grouped[letter]!;
            final groupBg = isDark
                ? _ChatAttachSheetState._groupBgDark
                : Theme.of(context).colorScheme.surfaceContainerHighest;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                  child: Text(
                    letter,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.8),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                _GroupedSurface(
                  color: groupBg,
                  children: [
                    for (var i = 0; i < sectionContacts.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 68,
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.2),
                        ),
                      _ContactTile(
                        contact: sectionContacts[i],
                        onTap: () => onSelect(sectionContacts[i]),
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
        Positioned(
          right: 4,
          top: 8,
          bottom: 8,
          child: _AlphabetRail(letters: letters),
        ),
      ],
    );
  }

  Map<String, List<_AttachSheetContact>> _groupContacts(
    List<_AttachSheetContact> items,
  ) {
    final map = <String, List<_AttachSheetContact>>{};
    for (final contact in items) {
      final name = contact.displayName.trim();
      final first = name.isNotEmpty ? name[0].toUpperCase() : '#';
      final key = RegExp(r'[A-ZА-ЯЁ]', caseSensitive: false).hasMatch(first)
          ? first
          : '#';
      map.putIfAbsent(key, () => []).add(contact);
    }
    for (final list in map.values) {
      list.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    }
    return map;
  }

  int _letterSort(String a, String b) {
    if (a == '#') return 1;
    if (b == '#') return -1;
    return a.compareTo(b);
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onTap});

  final _AttachSheetContact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUser = contact.avatarUser;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: avatarUser != null
          ? ChatHubUserAvatar(user: avatarUser)
          : CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.person_outline,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      title: Text(
        contact.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      subtitle: Text(
        contact.subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _AlphabetRail extends StatelessWidget {
  const _AlphabetRail({required this.letters});

  final List<String> letters;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final letter in letters)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              letter,
              style: const TextStyle(
                color: _ChatAttachSheetState._telegramBlue,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _TelegramAttachDock extends StatelessWidget {
  const _TelegramAttachDock({
    required this.selected,
    required this.onSelect,
    required this.onOpenMiniApps,
  });

  final ChatAttachTab selected;
  final ValueChanged<ChatAttachTab> onSelect;
  final VoidCallback onOpenMiniApps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        decoration: BoxDecoration(
          color: isDark
              ? _ChatAttachSheetState._sheetBgDark
              : theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.64)
                    : theme.colorScheme.surfaceContainerHigh
                        .withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const width = 52.0;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                    child: Row(
                      children: [
                        _DockItem(
                          icon: Icons.photo_library_outlined,
                          label: 'Галерея',
                          selected: selected == ChatAttachTab.gallery,
                          onTap: () => onSelect(ChatAttachTab.gallery),
                          compact: true,
                          width: width,
                        ),
                        _DockItem(
                          icon: Icons.gif_box_outlined,
                          label: 'GIF',
                          selected: selected == ChatAttachTab.gif,
                          onTap: () => onSelect(ChatAttachTab.gif),
                          compact: true,
                          width: width,
                        ),
                        _DockItem(
                          icon: Icons.insert_drive_file_outlined,
                          label: 'Файл',
                          selected: selected == ChatAttachTab.file,
                          onTap: () => onSelect(ChatAttachTab.file),
                          compact: true,
                          width: width,
                        ),
                        _DockItem(
                          icon: Icons.poll_outlined,
                          label: 'Опрос',
                          selected: selected == ChatAttachTab.poll,
                          onTap: () => onSelect(ChatAttachTab.poll),
                          compact: true,
                          width: width,
                        ),
                        _DockItem(
                          icon: Icons.person_outline_rounded,
                          label: 'Контакт',
                          selected: selected == ChatAttachTab.contact,
                          onTap: () => onSelect(ChatAttachTab.contact),
                          compact: true,
                          width: width,
                        ),
                        _DockItem(
                          icon: Icons.location_on_outlined,
                          label: 'Гео',
                          selected: selected == ChatAttachTab.location,
                          onTap: () => onSelect(ChatAttachTab.location),
                          compact: true,
                          width: width,
                        ),
                        _DockItem(
                          icon: Icons.circle_outlined,
                          label: 'Кружок',
                          selected: selected == ChatAttachTab.videoNote,
                          onTap: () => onSelect(ChatAttachTab.videoNote),
                          compact: true,
                          width: width,
                        ),
                        _DockItem(
                          icon: Icons.emoji_emotions_outlined,
                          label: 'Стикер',
                          selected: selected == ChatAttachTab.sticker,
                          onTap: () => onSelect(ChatAttachTab.sticker),
                          compact: true,
                          width: width,
                        ),
                        _DockItem(
                          icon: Icons.apps_outlined,
                          label: 'Мини',
                          selected: false,
                          onTap: onOpenMiniApps,
                          compact: true,
                          width: width,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.width,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inactiveColor = theme.colorScheme.onSurface.withValues(
      alpha: isDark ? 0.72 : 0.68,
    );
    final activeColor = _ChatAttachSheetState._brandAccent.withValues(
      alpha: isDark ? 0.96 : 0.9,
    );

    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(compact ? 12 : 12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 5 : 10,
              vertical: compact ? 3 : 6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  scale: selected ? 1.03 : 1.0,
                  child: Icon(
                    icon,
                    size: compact ? 19 : 26,
                    color: selected ? activeColor : inactiveColor,
                  ),
                ),
                SizedBox(height: compact ? 1 : 5),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected ? activeColor : inactiveColor,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    fontSize: compact ? 10 : null,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
