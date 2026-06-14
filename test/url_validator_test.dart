import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/utils/url_validator.dart';

void main() {
  test('normalizeHttpUrl adds https and parses host', () {
    expect(normalizeHttpUrl('example.com'), 'https://example.com');
    expect(normalizeHttpUrl('https://foo.bar/path'), 'https://foo.bar/path');
  });

  test('validateHttpUrl rejects invalid input', () {
    expect(validateHttpUrl(''), isNotNull);
    expect(validateHttpUrl('???'), isNotNull);
    expect(validateHttpUrl('javascript:alert(1)'), isNotNull);
    expect(validateHttpUrl('https://ok.com'), isNull);
  });
}
