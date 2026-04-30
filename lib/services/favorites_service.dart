import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';

class FavoritesService {
  static FavoritesService? _instance;
  static FavoritesService get instance {
    if (_instance == null) {
      throw Exception(
          'FavoritesService not initialized. Call FavoritesService.init() first.');
    }
    return _instance!;
  }

  static const String _boxName = 'favorites';
  late final Box _box;

  final ValueNotifier<Set<String>> favorites = ValueNotifier(<String>{});

  StreamSubscription<User?>? _authSub;

  FavoritesService._internal(this._box) {
    final keys = _box.keys.cast<String>();
    favorites.value = Set<String>.from(keys.where((k) => _box.get(k) == true));
  }

  // Allow re-init for tests: dispose previous and create new.
  static Future<void> init({bool startAuthSync = true}) async {
    if (_instance != null) {
      try {
        await _instance!._disposeInternal();
      } catch (_) {}
    }
    final box = await Hive.openBox(_boxName);
    _instance = FavoritesService._internal(box);
    if (startAuthSync && AuthService.isInitialized) {
      await _instance!._startAuthSync();
    }
  }

  Future<void> _startAuthSync() async {
    if (_authSub != null) return;
    try {
      _authSub = AuthService.instance.authStateChanges().listen((user) async {
        if (user != null) {
          await _mergeWithRemote(user.uid);
        }
      });
      final current = AuthService.instance.currentUser;
      if (current != null) {
        await _mergeWithRemote(current.uid);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('FavoritesService _startAuthSync failed: $e');
    }
  }

  Future<void> _mergeWithRemote(String uid) async {
    try {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('favorites');
      final snapshot = await col.get();
      final remoteIds = snapshot.docs.map((d) => d.id).toSet();
      final local = Set<String>.from(favorites.value);
      final merged = {...local, ...remoteIds};

      for (final id in merged) {
        await _box.put(id, true);
      }

      favorites.value = merged;

      final localOnly = local.difference(remoteIds);
      for (final id in localOnly) {
        await col.doc(id).set({'createdAt': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Favorites sync error: $e');
    }
  }

  bool isFavorite(String id) => favorites.value.contains(id);

  Future<void> toggleFavorite(String id) async {
    final currently = isFavorite(id);
    if (currently) {
      await _box.delete(id);
      final newSet = Set<String>.from(favorites.value)..remove(id);
      favorites.value = newSet;
      if (AuthService.isInitialized &&
          AuthService.instance.currentUser != null) {
        final user = AuthService.instance.currentUser!;
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('favorites')
              .doc(id)
              .delete();
        } catch (e) {
          if (kDebugMode)
            debugPrint('Failed to delete remote favorite $id: $e');
        }
      }
    } else {
      await _box.put(id, true);
      final newSet = Set<String>.from(favorites.value)..add(id);
      favorites.value = newSet;
      if (AuthService.isInitialized &&
          AuthService.instance.currentUser != null) {
        final user = AuthService.instance.currentUser!;
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('favorites')
              .doc(id)
              .set({'createdAt': FieldValue.serverTimestamp()});
        } catch (e) {
          if (kDebugMode) debugPrint('Failed to add remote favorite $id: $e');
        }
      }
    }
  }

  Map<String, dynamic> exportToJson() {
    return {
      'favorites': favorites.value.toList(),
      'exportedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> importFromJson(Map<String, dynamic> json,
      {bool merge = true}) async {
    final List<dynamic> raw = json['favorites'] as List<dynamic>? ?? [];
    final incoming = raw.map((e) => e.toString()).toSet();

    final current = Set<String>.from(favorites.value);
    final resultSet = merge ? {...current, ...incoming} : incoming;

    for (final id in resultSet) {
      await _box.put(id, true);
    }

    if (!merge) {
      final toRemove = _box.keys
          .cast<String>()
          .where((k) => !resultSet.contains(k))
          .toList();
      for (final k in toRemove) {
        await _box.delete(k);
      }
    }

    favorites.value = resultSet;

    final user =
        AuthService.isInitialized ? AuthService.instance.currentUser : null;
    if (user != null) {
      try {
        final col = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('favorites');
        for (final id in resultSet) {
          await col.doc(id).set({'createdAt': FieldValue.serverTimestamp()});
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Favorites import remote sync failed: $e');
      }
    }
  }

  Future<void> importFromJsonString(String jsonString,
      {bool merge = true}) async {
    final Map<String, dynamic> map =
        json.decode(jsonString) as Map<String, dynamic>;
    await importFromJson(map, merge: merge);
  }

  Future<void> _disposeInternal() async {
    try {
      await _authSub?.cancel();
    } catch (_) {}
    try {
      await _box.close();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _disposeInternal();
    favorites.dispose();
    _instance = null;
  }
}
