import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/channel_service.dart';
import 'package:han_eat/services/channel_sheet_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('listFavoriteIds returns only starred channels', () async {
    await ChannelSheetPrefs.seedForTest({
      1: const ChannelInboxPrefs(channelId: 1, isFavorite: true),
      2: const ChannelInboxPrefs(channelId: 2, isFavorite: false),
      3: const ChannelInboxPrefs(channelId: 3, isFavorite: true),
    });

    expect(await ChannelSheetPrefs.listFavoriteIds(), [1, 3]);
    expect(await ChannelSheetPrefs.getFavorite(2), isFalse);
  });

  test('setFavorite false removes id from list', () async {
    await ChannelSheetPrefs.seedForTest({
      5: const ChannelInboxPrefs(channelId: 5, isFavorite: true),
    });
    await ChannelSheetPrefs.setFavorite(5, false);

    expect(await ChannelSheetPrefs.listFavoriteIds(), isEmpty);
  });
}
