import 'dart:async';
import 'dart:js' as js;
import 'package:js/js.dart';

import 'phone_contacts_store_web.dart';

/// Web Contact Picker API (Chrome Android / часть desktop-браузеров).
class PhoneContactsPickerWeb {
  PhoneContactsPickerWeb._();

  static bool get isSupported {
    try {
      final nav = js.context['navigator'];
      if (nav == null) return false;
      final contacts = nav['contacts'];
      if (contacts == null) return false;
      return contacts.hasProperty('select');
    } catch (_) {
      return false;
    }
  }

  static Future<List<WebPhoneBookEntry>> pick() async {
    if (!isSupported) {
      throw UnsupportedError('Contact Picker API недоступен в этом браузере');
    }

    final nav = js.context['navigator'];
    final contactsApi = nav['contacts'];
    final props = js.JsArray.from(['name', 'tel']);
    final opts = js.JsObject.jsify({'multiple': true});

    final promise = contactsApi.callMethod('select', [props, opts]);
    final jsResult = await _promiseToFuture(promise);
    if (jsResult == null) return const [];

    return _parsePickerResult(jsResult);
  }

  static Future<Object?> _promiseToFuture(js.JsObject promise) {
    final completer = Completer<Object?>();
    promise.callMethod('then', [
      allowInterop((Object? value) {
        if (!completer.isCompleted) completer.complete(value);
      }),
      allowInterop((Object? error) {
        if (!completer.isCompleted) {
          completer.completeError(error ?? 'Contact picker failed');
        }
      }),
    ]);
    return completer.future;
  }

  static List<WebPhoneBookEntry> _parsePickerResult(Object jsArray) {
    if (jsArray is! js.JsObject) return const [];
    final length = (jsArray['length'] as num?)?.toInt() ?? 0;
    final out = <WebPhoneBookEntry>[];

    for (var i = 0; i < length; i++) {
      final contact = jsArray[i];
      if (contact is! js.JsObject) continue;
      final names = _readStringList(contact['name']);
      final tels = _readStringList(contact['tel']);
      final name = names.isNotEmpty ? names.first.trim() : '';

      for (final tel in tels) {
        final cleaned =
            tel.replaceFirst(RegExp(r'^tel:', caseSensitive: false), '').trim();
        if (cleaned.isEmpty) continue;
        out.add(
          WebPhoneBookEntry(
            displayName: name.isNotEmpty ? name : cleaned,
            phoneE164: cleaned,
          ),
        );
      }
    }
    return out;
  }

  static List<String> _readStringList(Object? value) {
    if (value is! js.JsObject) return const [];
    final length = (value['length'] as num?)?.toInt() ?? 0;
    final out = <String>[];
    for (var i = 0; i < length; i++) {
      final item = value[i];
      if (item is String && item.trim().isNotEmpty) {
        out.add(item.trim());
      }
    }
    return out;
  }
}
