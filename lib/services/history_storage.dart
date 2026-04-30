import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/analysis_mode.dart';
import '../models/search_history_entry.dart';
import 'api_service.dart';

class HistoryStorage {
  const HistoryStorage._();

  static Box<SearchHistoryEntry> get _box {
    try {
      return Hive.box<SearchHistoryEntry>(SearchHistoryEntry.boxName);
    } catch (e) {
      // Box not opened yet, return empty box
      throw Exception('History box not initialized. Call bootstrap first.');
    }
  }

  static ValueListenable<Box<SearchHistoryEntry>> listenable() {
    try {
      return _box.listenable();
    } catch (_) {
      // Box not initialized, try to open it
      try {
        return Hive.box<SearchHistoryEntry>(SearchHistoryEntry.boxName).listenable();
      } catch (e) {
        // If still fails, return a dummy box
        throw Exception('History box not available: $e');
      }
    }
  }

  static List<SearchHistoryEntry> entries() =>
      _box.values.toList().reversed.toList();

  static Future<void> addQuery(String query, AnalysisMode mode) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await _box.add(
      SearchHistoryEntry(
        query: trimmed,
        timestamp: DateTime.now(),
        mode: mode,
      ),
    );
    if (_box.length > 50) {
      final overflow = _box.length - 50;
      await _box.deleteAll(_box.keys.take(overflow));
    }
  }

  static Future<void> clear() => _box.clear();

  static Future<void> hydrateFromServer() async {
    try {
      final remote = await ApiService.fetchHistory(limit: 50);
      await _box.clear();
      for (final entry in remote) {
        await _box.add(entry);
      }
    } catch (_) {
      // ignore sync errors
    }
  }
}

