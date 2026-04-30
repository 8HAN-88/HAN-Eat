import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:han_eat/services/favorites_service.dart';

void main() {
  late Directory tmpDir;
  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('han_eat_test_fav_');
    Hive.init(tmpDir.path);
    // ensure no adapter needed (we store simple types)
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test('Favorites toggle and persistence', () async {
    await FavoritesService.init(startAuthSync: false);
    final svc = FavoritesService.instance;

    expect(svc.isFavorite('r1'), isFalse);

    await svc.toggleFavorite('r1');
    expect(svc.isFavorite('r1'), isTrue);

    await svc.toggleFavorite('r1');
    expect(svc.isFavorite('r1'), isFalse);

    // export
    final jsonMap = svc.exportToJson();
    expect(jsonMap['favorites'], isA<List>());
  });

  test('Favorites import with merge/replace', () async {
    await FavoritesService.init(startAuthSync: false);
    final svc = FavoritesService.instance;
    // seed local
    await svc.toggleFavorite('local1');
    expect(svc.isFavorite('local1'), isTrue);

    // import merge
    final incoming = {
      'favorites': ['remote1', 'local1']
    };
    await svc.importFromJson(incoming, merge: true);
    expect(svc.isFavorite('remote1'), isTrue);
    expect(svc.isFavorite('local1'), isTrue);

    // import replace
    final incoming2 = {
      'favorites': ['only1']
    };
    await svc.importFromJson(incoming2, merge: false);
    expect(svc.isFavorite('only1'), isTrue);
    expect(svc.isFavorite('local1'), isFalse);
  });
}
