import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _forbidden = <String>[
  'Telegram',
  'Instagram',
  'BotFather',
  'WhatsApp',
  'Fragment',
  'TikTok',
];

final _stringLit = RegExp("'(?:\\\\.|[^'\\\\])*'|\"(?:\\\\.|[^\"\\\\])*\"");

bool _isCommentLine(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('//') ||
      trimmed.startsWith('*') ||
      trimmed.startsWith('///');
}

Iterable<String> _quotedLiterals(String source) sync* {
  for (final line in source.split('\n')) {
    if (_isCommentLine(line)) continue;
    for (final match in _stringLit.allMatches(line)) {
      yield match.group(0)!;
    }
  }
}

void main() {
  test('lib UI strings do not name other apps or TON', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue);
    final hits = <String>[];
    for (final file in lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final lit in _quotedLiterals(source)) {
        for (final brand in _forbidden) {
          if (lit.contains(brand)) {
            hits.add('${file.path}: $lit');
          }
        }
        if (RegExp(r'\bTON\b').hasMatch(lit)) {
          hits.add('${file.path}: $lit');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
