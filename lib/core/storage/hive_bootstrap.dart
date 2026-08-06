import 'dart:io' show Directory;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

Future<void>? _hiveInitFuture;
bool hiveCoreReady = false;

/// Единая точка инициализации Hive — вызывать перед любым [Hive.openBox].
Future<void> ensureHiveReady() async {
  final existing = _hiveInitFuture;
  if (existing != null) return existing;
  final future = _initHiveCoreOnce();
  _hiveInitFuture = future;
  try {
    await future;
    hiveCoreReady = true;
  } catch (e) {
    _hiveInitFuture = null;
    rethrow;
  }
}

Future<void> _recoverHiveAfterLockError() async {
  try {
    await Hive.close();
  } catch (_) {}
  try {
    final appDir = await getApplicationDocumentsDirectory();
    await for (final entity in appDir.list()) {
      final name = entity.path.split('/').last;
      if (name.endsWith('.hive') ||
          name.endsWith('.lock') ||
          name.contains('.hive.')) {
        try {
          await entity.delete();
          debugPrint('Hive recovery: удалён $name');
        } catch (_) {}
      }
    }
  } catch (e) {
    debugPrint('Hive recovery: $e');
  }
}

Future<void> _initHiveCoreOnce() async {
  try {
    await Hive.initFlutter();
  } catch (e, st) {
    debugPrint('Hive.initFlutter failed (продолжаем без Hive): $e\n$st');
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _recoverHiveAfterLockError();
      try {
        await Hive.initFlutter();
      } catch (e2) {
        debugPrint('Hive retry failed: $e2');
        return;
      }
    } else {
      try {
        final dir = await Directory.systemTemp.createTemp('hive_fallback_');
        Hive.init(dir.path);
      } catch (e2) {
        debugPrint('Hive fallback init failed: $e2');
        return;
      }
    }
  }
}
