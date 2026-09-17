import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:han_eat/features/admin/presentation/admin_partner_payouts_screen.dart';
import 'package:han_eat/features/referral/presentation/partner_program_screen.dart';
import 'package:han_eat/services/revenue_share_service.dart';

class _Ledger {
  int available = 56000;
  int pending = 1400;
  int hold = 0;
  int paid = 0;
  final payouts = <Map<String, dynamic>>[];
  int nextId = 1;

  Map<String, dynamic> snap([Map<String, dynamic>? last]) {
    return {
      'referral_code': 'ABC12XYZ',
      'share_url': 'https://haneat.app/invite?ref=ABC12XYZ',
      'extra_ads_enabled': false,
      'referred_count': 2,
      'pending_kopecks': pending,
      'available_kopecks': available,
      'payout_hold_kopecks': hold,
      'paid_kopecks': paid,
      'as_viewer_kopecks': 70,
      'as_referrer_kopecks': 1750,
      'kopecks_per_star': 80,
      'min_card_kopecks': 50000,
      'convertible_stars': available ~/ 80,
      'payouts': List<Map<String, dynamic>>.from(payouts),
      if (last != null) 'last_payout': last,
    };
  }

  http.Response handle(http.Request request) {
    final path = request.url.path;
    Map<String, dynamic>? body;
    if (request.body.isNotEmpty) {
      body = jsonDecode(request.body) as Map<String, dynamic>;
    }

    if (path.endsWith('/revenue-share/me') && request.method == 'GET') {
      return _ok(snap());
    }
    if (path.endsWith('/revenue-share/payouts/stars') &&
        request.method == 'POST') {
      final stars = available ~/ 80;
      if (stars < 1) {
        return _err(400, 'Нужна хотя бы 1 звезда (от 0,80 ₽)');
      }
      final need = stars * 80;
      available -= need;
      paid += need;
      final payout = {
        'id': nextId++,
        'user_id': 1,
        'kind': 'stars',
        'amount_kopecks': need,
        'amount_stars': stars,
        'status': 'paid',
      };
      payouts.insert(0, payout);
      return _ok(snap(payout));
    }
    if (path.endsWith('/revenue-share/payouts/card') &&
        request.method == 'POST') {
      final amount = (body?['amount_kopecks'] as num?)?.toInt() ?? available;
      if (amount < 50000 || amount > available) {
        return _err(400, 'На карту — от 500 ₽');
      }
      available -= amount;
      hold += amount;
      final payout = {
        'id': nextId++,
        'user_id': 1,
        'kind': 'card',
        'amount_kopecks': amount,
        'amount_stars': 0,
        'status': 'pending',
        'phone': body?['phone'],
        'recipient_name': body?['recipient_name'],
        'user_name': 'Партнёр',
        'user_email': 'partner@ex.com',
      };
      payouts.insert(0, payout);
      return _ok(snap(payout));
    }
    if (path.endsWith('/revenue-share/payouts/queue') &&
        request.method == 'GET') {
      return http.Response(
        jsonEncode(
          payouts
              .where((row) => row['kind'] == 'card' && row['status'] == 'pending')
              .toList(),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.contains('/revenue-share/payouts/') &&
        path.endsWith('/review') &&
        request.method == 'POST') {
      final id = int.tryParse(path.split('/')[path.split('/').length - 2]);
      Map<String, dynamic>? row;
      for (final item in payouts) {
        if (item['id'] == id) {
          row = item;
          break;
        }
      }
      if (row == null) return _err(404, 'Заявка не найдена');
      final approve = body?['approve'] == true;
      final amount = (row['amount_kopecks'] as num).toInt();
      if (approve) {
        row['status'] = 'paid';
        hold -= amount;
        paid += amount;
      } else {
        row['status'] = 'rejected';
        hold -= amount;
        available += amount;
      }
      return _ok(row);
    }
    return _err(404, path);
  }

  http.Response _ok(Object payload) {
    return http.Response(
      jsonEncode(payload),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  http.Response _err(int status, String detail) {
    return http.Response(
      jsonEncode({'detail': detail}),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

String _visibleTexts(WidgetTester tester) {
  return find.byType(Text).evaluate().map((el) {
    final widget = el.widget as Text;
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }).where((text) => text.trim().isNotEmpty).join(' | ');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int tries = 50,
}) async {
  for (var i = 0; i < tries; i++) {
    await tester.pump(const Duration(milliseconds: 40));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Не дождались $finder. Видно: ${_visibleTexts(tester)}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Ledger ledger;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ru');
    ledger = _Ledger();
    RevenueShareApi.debugBaseUrl = 'http://127.0.0.1';
    RevenueShareApi.debugAccessToken = () async => 'test-token';
    RevenueShareApi.debugClient = MockClient((request) async => ledger.handle(request));
  });

  tearDown(() {
    RevenueShareApi.debugBaseUrl = null;
    RevenueShareApi.debugAccessToken = null;
    RevenueShareApi.debugClient = null;
  });

  testWidgets(
    'partner taps convert stars and request card, admin pays out',
    (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: PartnerProgramScreen()),
    );
    await _pumpUntil(tester, find.text('Доступно: 560.00 ₽'));
    expect(find.text('На выплате: 0.00 ₽'), findsOneWidget);
    expect(find.textContaining('В звёзды · 700 ★'), findsOneWidget);

    final cardBtn = find.widgetWithText(OutlinedButton, 'На карту / СБП');
    await tester.tap(cardBtn);
    await tester.pump();
    await _pumpUntil(tester, find.text('Отправить'));

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '+79001234567');
    await tester.enterText(fields.at(1), 'Иван Петров');
    await tester.tap(find.text('Отправить'));
    await _pumpUntil(tester, find.text('Заявка отправлена'));
    expect(find.text('Доступно: 60.00 ₽'), findsOneWidget);
    expect(find.text('На выплате: 500.00 ₽'), findsOneWidget);
    expect(find.textContaining('На карту / СБП · 500.00 ₽'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'В звёзды · 75 ★'));
    await tester.pump();
    await _pumpUntil(tester, find.widgetWithText(FilledButton, 'Зачислить'));
    await tester.tap(find.widgetWithText(FilledButton, 'Зачислить'));
    await tester.pump();
    await _pumpUntil(tester, find.textContaining('В звёзды · 60.00 ₽'));
    expect(find.text('Доступно: 0.00 ₽'), findsOneWidget);
    expect(find.text('Уже выплачено: 60.00 ₽'), findsOneWidget);
    expect(find.textContaining('В звёзды · 60.00 ₽'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: AdminPartnerPayoutsScreen()),
    );
    await _pumpUntil(tester, find.text('500.00 ₽'));
    expect(find.textContaining('partner@ex.com'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Выплачено'));
    await tester.pump();
    await _pumpUntil(tester, find.text('Подтвердить выплату'));
    await tester.tap(find.widgetWithText(FilledButton, 'Выплачено').last);
    await _pumpUntil(tester, find.text('Очередь пуста'));
    expect(find.text('Нет заявок на карту или СБП'), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
