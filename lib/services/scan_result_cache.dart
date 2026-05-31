import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/analysis_result.dart';

/// Кэш результатов AI-скана по хешу изображения — одно фото → один результат.
class ScanResultCache {
  ScanResultCache._();
  static final ScanResultCache instance = ScanResultCache._();

  static const _prefsKey = 'scan_result_cache_v1';
  static const _maxEntries = 32;
  static const _ttl = Duration(hours: 48);

  final Map<String, _CacheEntry> _memory = {};

  String keyFor(Uint8List imageBytes) =>
      sha256.convert(imageBytes).toString();

  AnalysisResult? get(Uint8List imageBytes) {
    final key = keyFor(imageBytes);
    final hit = _memory[key];
    if (hit == null || hit.isExpired) {
      if (hit != null) _memory.remove(key);
      return null;
    }
    if (kDebugMode) {
      debugPrint('ScanResultCache: hit $key');
    }
    return hit.result;
  }

  Future<void> put(Uint8List imageBytes, AnalysisResult result) async {
    final key = keyFor(imageBytes);
    _memory[key] = _CacheEntry(result: result, savedAt: DateTime.now());
    _trimMemory();
    await _persist();
  }

  void _trimMemory() {
    final now = DateTime.now();
    _memory.removeWhere((_, e) => e.isExpiredAt(now));
    if (_memory.length <= _maxEntries) return;
    final sorted = _memory.entries.toList()
      ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
    while (_memory.length > _maxEntries) {
      _memory.remove(sorted.removeAt(0).key);
    }
  }

  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final now = DateTime.now();
      for (final e in map.entries) {
        final item = e.value as Map<String, dynamic>;
        final savedAt = DateTime.tryParse(item['saved_at'] as String? ?? '');
        if (savedAt == null || now.difference(savedAt) > _ttl) continue;
        _memory[e.key] = _CacheEntry(
          result: AnalysisResult.fromJson(
            item['analysis'] as Map<String, dynamic>,
          ),
          savedAt: savedAt,
        );
      }
      _trimMemory();
    } catch (e) {
      if (kDebugMode) debugPrint('ScanResultCache.load: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final out = <String, dynamic>{};
      for (final e in _memory.entries) {
        if (e.value.isExpired) continue;
        out[e.key] = {
          'saved_at': e.value.savedAt.toIso8601String(),
          'analysis': e.value.result.toJson(),
        };
      }
      await prefs.setString(_prefsKey, jsonEncode(out));
    } catch (e) {
      if (kDebugMode) debugPrint('ScanResultCache.persist: $e');
    }
  }
}

class _CacheEntry {
  _CacheEntry({required this.result, required this.savedAt});

  final AnalysisResult result;
  final DateTime savedAt;

  bool get isExpired =>
      DateTime.now().difference(savedAt) > ScanResultCache._ttl;

  bool isExpiredAt(DateTime now) =>
      now.difference(savedAt) > ScanResultCache._ttl;
}
