import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_models.dart';
import 'chat_service.dart';

/// Кэш папок чатов + синхронизация с API.
class ChatFolderStore {
  ChatFolderStore._();

  static const _key = 'chat_folders_local_v1';

  static Future<List<ChatFolder>> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(ChatFolder.fromJson)
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLocal(List<ChatFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(folders.map((f) => f.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  /// Синхронизирует «зависшие» локальные черновики (legacy) и подтягивает список с сервера.
  static Future<List<ChatFolder>> listFolders() async {
    try {
      var local = await loadLocal();
      final pending = local.where((f) => f.id < 0).toList();
      for (final lf in pending) {
        try {
          await ChatService.createFolder(
            name: lf.name,
            icon: lf.icon,
            conversationIds: lf.conversationIds,
            channelIds: lf.channelIds,
            filters: lf.filters,
          );
          local = local.where((f) => f.id != lf.id).toList();
        } catch (_) {}
      }
      if (pending.isNotEmpty) {
        await saveLocal(local);
      }
      final remote = await ChatService.listFolders();
      await saveLocal(remote);
      return remote;
    } catch (_) {
      return loadLocal();
    }
  }

  static Future<ChatFolder> createFolder({
    required String name,
    String? icon,
    List<int> conversationIds = const [],
    List<int> channelIds = const [],
    ChatFolderFilters filters = const ChatFolderFilters(),
  }) async {
    final folder = await ChatService.createFolder(
      name: name,
      icon: icon,
      conversationIds: conversationIds,
      channelIds: channelIds,
      filters: filters,
    );
    final remote = await ChatService.listFolders();
    await saveLocal(remote);
    return remote.firstWhere(
      (f) => f.id == folder.id,
      orElse: () => folder,
    );
  }

  static Future<ChatFolder> updateFolder(ChatFolder folder) async {
    if (folder.id <= 0) {
      throw StateError('Нельзя обновить локальную папку без id сервера');
    }
    final updated = await ChatService.updateFolder(
      folderId: folder.id,
      name: folder.name,
      icon: folder.icon,
      conversationIds: folder.conversationIds,
      channelIds: folder.channelIds,
      filters: folder.filters,
    );
    final remote = await ChatService.listFolders();
    await saveLocal(remote);
    return remote.firstWhere(
      (f) => f.id == updated.id,
      orElse: () => updated,
    );
  }

  static Future<void> deleteFolder(int folderId) async {
    if (folderId > 0) {
      await ChatService.deleteFolder(folderId: folderId);
    }
    final remote = await ChatService.listFolders();
    await saveLocal(remote);
  }

  static Future<ChatFolder?> addToFolder({
    required int folderId,
    int? conversationId,
    int? channelId,
  }) async {
    if (folderId <= 0) return null;
    final updated = await ChatService.addFolderItem(
      folderId: folderId,
      conversationId: conversationId,
      channelId: channelId,
    );
    final remote = await ChatService.listFolders();
    await saveLocal(remote);
    return remote.firstWhere(
      (f) => f.id == updated.id,
      orElse: () => updated,
    );
  }

  static Future<ChatFolder?> removeFromFolder({
    required int folderId,
    int? conversationId,
    int? channelId,
  }) async {
    if (folderId <= 0) return null;
    final updated = await ChatService.removeFolderItem(
      folderId: folderId,
      conversationId: conversationId,
      channelId: channelId,
    );
    final remote = await ChatService.listFolders();
    await saveLocal(remote);
    return remote.firstWhere(
      (f) => f.id == updated.id,
      orElse: () => updated,
    );
  }

  static Future<List<ChatFolder>> reorderFolders(List<int> folderIds) async {
    try {
      final remote = await ChatService.reorderFolders(folderIds);
      await saveLocal(remote);
      return remote;
    } catch (_) {
      final local = await loadLocal();
      final byId = {for (final f in local) f.id: f};
      final ordered = <ChatFolder>[];
      for (var i = 0; i < folderIds.length; i++) {
        final f = byId[folderIds[i]];
        if (f != null) ordered.add(f.copyWith(position: i));
      }
      for (final f in local) {
        if (!folderIds.contains(f.id)) {
          ordered.add(f.copyWith(position: ordered.length));
        }
      }
      await saveLocal(ordered);
      return ordered;
    }
  }

  static Future<({String token, String name})> shareFolder(int folderId) {
    return ChatService.shareFolder(folderId: folderId);
  }

  static Future<ChatFolder> importSharedFolder(String token) async {
    final folder = await ChatService.importSharedFolder(token: token);
    final remote = await ChatService.listFolders();
    await saveLocal(remote);
    return remote.firstWhere(
      (f) => f.id == folder.id,
      orElse: () => folder,
    );
  }
}
