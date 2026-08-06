import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:han_eat/core/storage/hive_bootstrap.dart';
import '../models/analysis_mode.dart';
import '../models/search_history_entry.dart';
import 'package:han_eat/services/api_service.dart';

class HistoryStorage {
  const HistoryStorage._();

  static bool _openInFlight = false;

  /// Открывает бокс при первом обращении (не блокирует экран «Запуск…»).
  static Future<void> ensureOpen() async {
    if (Hive.isBoxOpen(SearchHistoryEntry.boxName)) return;
    if (_openInFlight) {
      while (_openInFlight) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      return;
    }
    _openInFlight = true;
    try {
      await ensureHiveReady();
      const maxAttempts = 4;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          await Hive.openBox<SearchHistoryEntry>(SearchHistoryEntry.boxName);
          return;
        } catch (e) {
          if (attempt == maxAttempts - 1) {
            try {
              await Hive.deleteBoxFromDisk(SearchHistoryEntry.boxName);
              await Hive.openBox<SearchHistoryEntry>(SearchHistoryEntry.boxName);
              return;
            } catch (e2) {
              if (kDebugMode) {
                debugPrint('HistoryStorage.ensureOpen failed: $e2');
              }
              return;
            }
          }
          await Future.delayed(Duration(milliseconds: 50 * (attempt + 1)));
        }
      }
    } finally {
      _openInFlight = false;
    }
  }

  static Box<SearchHistoryEntry>? get _boxOrNull {
    if (!Hive.isBoxOpen(SearchHistoryEntry.boxName)) return null;
    return Hive.box<SearchHistoryEntry>(SearchHistoryEntry.boxName);
  }

  static ValueListenable<Box<SearchHistoryEntry>>? listenable() {
    final box = _boxOrNull;
    return box?.listenable();
  }

  static List<SearchHistoryEntry> entries() {
    final box = _boxOrNull;
    if (box == null) return [];
    return box.values.toList().reversed.toList();
  }

  static Future<void> addQuery(String query, AnalysisMode mode) async {
    await ensureOpen();
    final box = _boxOrNull;
    if (box == null) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await box.add(
      SearchHistoryEntry(
        query: trimmed,
        timestamp: DateTime.now(),
        mode: mode,
      ),
    );
    if (box.length > 50) {
      final overflow = box.length - 50;
      await box.deleteAll(box.keys.take(overflow));
    }
  }

  static Future<void> clear() async {
    await ensureOpen();
    final box = _boxOrNull;
    if (box == null) return;
    await box.clear();
  }

  static Future<void> hydrateFromServer() async {
    await ensureOpen();
    final box = _boxOrNull;
    if (box == null) return;
    try {
      final remote = await ApiService.fetchHistory(limit: 50);
      await box.clear();
      for (final entry in remote) {
        await box.add(entry);
      }
    } catch (_) {
      // ignore sync errors
    }
  }
}
